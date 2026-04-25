// WaveToolHandlers.swift

// Pineapple 🍍
//
// MCP tool handler functions for all Wave Terminal tools.
// Every handler follows the standard signature:
//   func handleWave*(params:logger:config:) async -> CallTool.Result
//
// Read handlers (Tier A) proceed immediately.
// Write handlers (Tier B) require `approved: true` on the second call.

import Foundation
import MCP
import Logging

// MARK: - Shared config manager

/// Module-level singleton so concurrent handlers share actor state and don't race
/// on the same config files by creating independent instances per call.
/// Passes nil to trigger auto-detection of the Wave config directory.
let sharedWaveConfigManager = WaveConfigManager(configDir: nil)

/// Returns the shared WaveConfigManager. Propagates mutable config flags on each call
/// so changes to settings.json take effect without restarting the server.
func makeWaveManager(_ config: Configuration) -> WaveConfigManager {
    Task { await sharedWaveConfigManager.setBackupBeforeWrite(config.wave.backupBeforeWrite) }
    return sharedWaveConfigManager
}

// MARK: - Read handlers (Tier A)

// ─── wave_get_settings ────────────────────────────────────────────────────────

/// Read Wave Terminal settings.
/// Optional `namespace` parameter filters to a key prefix (e.g. "ai", "term").
func handleWaveGetSettings(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        let settings = try await waveManager.readSettings()

        // Filter by namespace if requested
        let namespace = params.arguments?["namespace"]?.stringValue
        let result = namespace.map { filterByNamespace(settings, $0) } ?? settings

        if result.isEmpty {
            let msg = namespace.map { "No settings found for namespace '\($0)'" } ?? "Settings file is empty"
            return .init(content: [.text(msg)])
        }

        let json = try formatJSON(result)
        let header = namespace.map { "Wave settings (namespace: \($0)):" } ?? "Wave settings:"
        return .init(content: [.text("\(header)\n\n\(json)")])
    } catch {
        return .init(content: [.text("Error reading Wave settings: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_get_widgets ─────────────────────────────────────────────────────────

/// List all custom Wave Terminal widgets.
func handleWaveGetWidgets(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        let widgets = try await waveManager.readWidgets()

        if widgets.isEmpty {
            return .init(content: [.text("No custom widgets configured in Wave Terminal.")])
        }

        let json = try formatJSON(widgets)
        return .init(content: [.text("Wave widgets (\(widgets.count) total):\n\n\(json)")])
    } catch {
        return .init(content: [.text("Error reading Wave widgets: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_get_ai_presets ──────────────────────────────────────────────────────

/// List all AI presets configured in Wave Terminal.
func handleWaveGetAIPresets(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        let presets = try await waveManager.readAIPresets()

        if presets.isEmpty {
            return .init(content: [.text("No AI presets configured in Wave Terminal.")])
        }

        let json = try formatJSON(presets)
        return .init(content: [.text("Wave AI presets (\(presets.count) total):\n\n\(json)")])
    } catch {
        return .init(content: [.text("Error reading Wave AI presets: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_get_backgrounds ─────────────────────────────────────────────────────

/// List all tab backgrounds configured in Wave Terminal.
func handleWaveGetBackgrounds(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        let backgrounds = try await waveManager.readBackgrounds()

        if backgrounds.isEmpty {
            return .init(content: [.text("No backgrounds configured in Wave Terminal.")])
        }

        let json = try formatJSON(backgrounds)
        return .init(content: [.text("Wave backgrounds (\(backgrounds.count) total):\n\n\(json)")])
    } catch {
        return .init(content: [.text("Error reading Wave backgrounds: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - Write handlers (Tier B — require approved: true)

// ─── wave_set_setting ─────────────────────────────────────────────────────────

/// Update a single Wave Terminal setting.
/// Requires approved=true on second call.
func handleWaveSetSetting(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments,
          let keyValue = arguments["key"],
          let rawValue = arguments["value"] else {
        return .init(content: [.text("Missing required parameters: key, value")], isError: true)
    }

    guard case .string(let key) = keyValue, !key.isEmpty else {
        return .init(content: [.text("Parameter 'key' must be a non-empty string")], isError: true)
    }

    // Convert MCP Value → AnyCodableValue
    guard let codableValue = anyCodable(from: rawValue) else {
        return .init(content: [.text("Unsupported value type for key '\(key)'")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_set_setting",
            action: "Set \(key) = \(describeValue(rawValue))",
            targetFile: "~/.waveterm/settings.json"
        ))])
    }

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.writeSetting(key: key, value: codableValue)
        logger.info("Wave setting updated: \(key)")
        return .init(content: [.text("✓ Wave setting updated: \(key) = \(describeValue(rawValue))")])
    } catch {
        return .init(content: [.text("Error updating Wave setting: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_create_widget ───────────────────────────────────────────────────────

/// Create a new Wave Terminal widget.
/// Requires approved=true on second call.
func handleWaveCreateWidget(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let idValue = arguments["id"], case .string(let id) = idValue, !id.isEmpty else {
        return .init(content: [.text("Missing or invalid required parameter: id")], isError: true)
    }

    guard let labelValue = arguments["label"], case .string(let label) = labelValue else {
        return .init(content: [.text("Missing required parameter: label")], isError: true)
    }

    guard let viewValue = arguments["view"], case .string(let view) = viewValue else {
        return .init(content: [.text("Missing required parameter: view (term, preview, web, sysinfo)")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_create_widget",
            action: "Create widget '\(id)' (view: \(view), label: \(label))",
            targetFile: "~/.waveterm/widgets.json"
        ))])
    }

    // Build BlockDef meta from arguments
    var meta: [String: AnyCodableValue] = ["view": .string(view)]

    if let cmdValue = arguments["command"], case .string(let cmd) = cmdValue {
        meta["controller"] = .string("cmd")
        meta["cmd"] = .string(cmd)
    }

    if let cwdValue = arguments["cwd"], case .string(let cwd) = cwdValue {
        meta["cmd:cwd"] = .string(cwd)
    }

    if let shellValue = arguments["shell_path"], case .string(let shell) = shellValue {
        meta["term:localshellpath"] = .string(shell)
    }

    if let runOnStartValue = arguments["run_on_start"], case .bool(let run) = runOnStartValue {
        meta["cmd:runonstart"] = .bool(run)
    }

    if let closeOnExitValue = arguments["close_on_exit"], case .bool(let close) = closeOnExitValue {
        meta["cmd:closeonexit"] = .bool(close)
    }

    if let envValue = arguments["env"], case .object(let envObj) = envValue {
        var envDict: [String: AnyCodableValue] = [:]
        for (k, v) in envObj {
            if case .string(let s) = v {
                envDict[k] = .string(s)
            }
        }
        if !envDict.isEmpty {
            meta["cmd:env"] = .dict(envDict)
        }
    }

    let blockDef = BlockDef(meta: meta)

    // Build WidgetConfig
    var icon: String? = nil
    if let iconValue = arguments["icon"], case .string(let i) = iconValue { icon = i }

    var color: String? = nil
    if let colorValue = arguments["color"], case .string(let c) = colorValue { color = c }

    let widget = WidgetConfig(
        blockdef: blockDef,
        icon: icon,
        color: color,
        label: label
    )

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.writeWidget(id: id, config: widget)
        logger.info("Wave widget created: \(id)")
        return .init(content: [.text("✓ Wave widget created: '\(id)' — restart Wave or reload widgets to see it.")])
    } catch {
        return .init(content: [.text("Error creating Wave widget: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_update_widget ───────────────────────────────────────────────────────

/// Update an existing Wave Terminal widget.
/// Requires approved=true on second call.
func handleWaveUpdateWidget(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let idValue = arguments["id"], case .string(let id) = idValue, !id.isEmpty else {
        return .init(content: [.text("Missing or invalid required parameter: id")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_update_widget",
            action: "Update widget '\(id)'",
            targetFile: "~/.waveterm/widgets.json"
        ))])
    }

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        var widgets = try await waveManager.readWidgets()

        guard var existing = widgets[id] else {
            return .init(content: [.text("Widget '\(id)' not found. Use wave_create_widget to create it first.")], isError: true)
        }

        // Apply updates selectively
        if let labelValue = arguments["label"], case .string(let label) = labelValue {
            existing.label = label
        }
        if let iconValue = arguments["icon"], case .string(let icon) = iconValue {
            existing.icon = icon
        }
        if let colorValue = arguments["color"], case .string(let color) = colorValue {
            existing.color = color
        }
        if let descValue = arguments["description"], case .string(let desc) = descValue {
            existing.description = desc
        }
        if let hiddenValue = arguments["hidden"], case .bool(let hidden) = hiddenValue {
            existing.displayHidden = hidden
        }

        // Update blockdef meta keys if provided
        if let viewValue = arguments["view"], case .string(let view) = viewValue {
            existing.blockdef.meta["view"] = .string(view)
        }
        if let cmdValue = arguments["command"], case .string(let cmd) = cmdValue {
            existing.blockdef.meta["cmd"] = .string(cmd)
            existing.blockdef.meta["controller"] = .string("cmd")
        }
        if let cwdValue = arguments["cwd"], case .string(let cwd) = cwdValue {
            existing.blockdef.meta["cmd:cwd"] = .string(cwd)
        }

        widgets[id] = existing
        try await waveManager.writeWidget(id: id, config: existing)
        logger.info("Wave widget updated: \(id)")
        return .init(content: [.text("✓ Wave widget updated: '\(id)'")])
    } catch {
        return .init(content: [.text("Error updating Wave widget: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_delete_widget ───────────────────────────────────────────────────────

/// Delete a Wave Terminal widget by ID.
/// Requires approved=true on second call.
func handleWaveDeleteWidget(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let idValue = arguments["id"], case .string(let id) = idValue, !id.isEmpty else {
        return .init(content: [.text("Missing or invalid required parameter: id")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_delete_widget",
            action: "Delete widget '\(id)' from widgets.json",
            targetFile: "~/.waveterm/widgets.json"
        ))])
    }

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.deleteWidget(id: id)
        logger.info("Wave widget deleted: \(id)")
        return .init(content: [.text("✓ Wave widget deleted: '\(id)'")])
    } catch {
        return .init(content: [.text("Error deleting Wave widget: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_set_ai_preset ───────────────────────────────────────────────────────

/// Create or update a Wave Terminal AI preset.
/// Requires approved=true on second call.
func handleWaveSetAIPreset(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let idValue = arguments["id"], case .string(let id) = idValue, !id.isEmpty else {
        return .init(content: [.text("Missing or invalid required parameter: id")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_set_ai_preset",
            action: "Create/update AI preset '\(id)'",
            targetFile: "~/.waveterm/aipresets.json"
        ))])
    }

    // Build AIPresetConfig settings from arguments
    var settings: [String: AnyCodableValue] = [:]

    let stringKeys: [(String, String)] = [
        ("name", "display:name"),
        ("model", "ai:model"),
        ("api_type", "ai:apitype"),
        ("base_url", "ai:baseurl"),
        ("api_token", "ai:apitoken"),
        ("ai_name", "ai:name"),
        ("org_id", "ai:orgid"),
        ("api_version", "ai:apiversion"),
        ("proxy_url", "ai:proxyurl"),
    ]

    for (argKey, settingKey) in stringKeys {
        if let v = arguments[argKey], case .string(let s) = v {
            settings[settingKey] = .string(s)
        }
    }

    let numberKeys: [(String, String)] = [
        ("max_tokens", "ai:maxtokens"),
        ("timeout_ms", "ai:timeoutms"),
        ("display_order", "display:order"),
        ("font_size", "ai:fontsize"),
    ]

    for (argKey, settingKey) in numberKeys {
        if let v = arguments[argKey] {
            if case .double(let d) = v {
                settings[settingKey] = .double(d)
            } else if case .int(let i) = v {
                settings[settingKey] = .double(Double(i))
            }
        }
    }

    if settings.isEmpty {
        return .init(content: [.text("No preset fields provided. Supply at least one of: name, model, api_type, base_url, api_token, etc.")], isError: true)
    }

    let preset = AIPresetConfig(settings: settings)
    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.writeAIPreset(id: id, config: preset)
        logger.info("Wave AI preset written: \(id)")
        return .init(content: [.text("✓ Wave AI preset '\(id)' saved with \(settings.count) setting(s).")])
    } catch {
        return .init(content: [.text("Error saving Wave AI preset: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_set_theme ───────────────────────────────────────────────────────────

/// Set the terminal theme in Wave Terminal global settings (term:theme).
/// Requires approved=true on second call.
func handleWaveSetTheme(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let themeValue = arguments["theme"], case .string(let theme) = themeValue, !theme.isEmpty else {
        return .init(content: [.text("Missing or invalid required parameter: theme")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_set_theme",
            action: "Set terminal theme to '\(theme)'",
            targetFile: "~/.waveterm/settings.json"
        ))])
    }

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.writeSetting(key: "term:theme", value: .string(theme))
        logger.info("Wave theme set to: \(theme)")
        return .init(content: [.text("✓ Wave terminal theme set to '\(theme)'. Reload Wave to apply.")])
    } catch {
        return .init(content: [.text("Error setting Wave theme: \(error.localizedDescription)")], isError: true)
    }
}

// ─── wave_set_appearance ──────────────────────────────────────────────────────

/// Update window or terminal appearance settings.
/// Supported keys: font_size (term:fontsize), font_family (term:fontfamily),
///   transparency (term:transparency), tab_bar (app:tabbar), window_opacity, etc.
/// Requires approved=true on second call.
func handleWaveSetAppearance(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    // Build the settings map from the incoming arguments
    var updates: [String: AnyCodableValue] = [:]

    let stringMappings: [(String, String)] = [
        ("font_family",      "term:fontfamily"),
        ("tab_bar",          "app:tabbar"),
        ("default_new_block","app:defaultnewblock"),
        ("focus_follows_cursor","app:focusfollowscursor"),
        ("editor_font_family","editor:fontfamily"),
    ]

    for (argKey, settingKey) in stringMappings {
        if let v = arguments[argKey], case .string(let s) = v {
            updates[settingKey] = .string(s)
        }
    }

    let numberMappings: [(String, String)] = [
        ("font_size",        "term:fontsize"),
        ("transparency",     "term:transparency"),
        ("editor_font_size", "editor:fontsize"),
    ]

    for (argKey, settingKey) in numberMappings {
        if let v = arguments[argKey] {
            if case .double(let d) = v {
                updates[settingKey] = .double(d)
            } else if case .int(let i) = v {
                updates[settingKey] = .int(i)
            }
        }
    }

    let boolMappings: [(String, String)] = [
        ("ctrl_v_paste",     "app:ctrlvpaste"),
        ("confirm_quit",     "app:confirmquit"),
        ("mac_option_is_meta","term:macoptionismeta"),
        ("bell_sound",       "term:bellsound"),
        ("bell_indicator",   "term:bellindicator"),
    ]

    for (argKey, settingKey) in boolMappings {
        if let v = arguments[argKey], case .bool(let b) = v {
            updates[settingKey] = .bool(b)
        }
    }

    if updates.isEmpty {
        return .init(content: [.text("""
            No appearance settings provided. Supported parameters:
            • font_size (number) — term:fontsize
            • font_family (string) — term:fontfamily
            • transparency (number 0.0–1.0) — term:transparency
            • tab_bar ("top"|"left") — app:tabbar
            • font_family (string) — term:fontfamily
            • ctrl_v_paste (bool) — app:ctrlvpaste
            • confirm_quit (bool) — app:confirmquit
            • mac_option_is_meta (bool) — term:macoptionismeta
            • bell_sound (bool) — term:bellsound
            • bell_indicator (bool) — term:bellindicator
            • default_new_block (string) — app:defaultnewblock
            """)], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        let keyList = updates.keys.joined(separator: ", ")
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_set_appearance",
            action: "Update appearance settings: \(keyList)",
            targetFile: "~/.waveterm/settings.json"
        ))])
    }

    let waveManager = makeWaveManager(config)

    guard await waveManager.waveIsInstalled() else {
        return .init(
            content: [.text(WaveConfigError.notInstalled(config.wave.configDir).errorDescription ?? "")],
            isError: true
        )
    }

    do {
        try await waveManager.writeSettings(updates)
        logger.info("Wave appearance updated: \(updates.keys.joined(separator: ", "))")
        let keyList = updates.keys.sorted().joined(separator: ", ")
        return .init(content: [.text("✓ Wave appearance updated (\(updates.count) setting(s)): \(keyList). Reload Wave to apply.")])
    } catch {
        return .init(content: [.text("Error updating Wave appearance: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - Private conversion helpers

/// Convert an MCP `Value` to `AnyCodableValue`. Returns nil if unsupported.
private func anyCodable(from value: Value) -> AnyCodableValue? {
    switch value {
    case .string(let s):  return .string(s)
    case .bool(let b):    return .bool(b)
    case .int(let i):     return .int(i)
    case .double(let d):  return .double(d)
    case .array(let arr):
        let items = arr.compactMap { anyCodable(from: $0) }
        return .array(items)
    case .object(let obj):
        var d: [String: AnyCodableValue] = [:]
        for (k, v) in obj {
            if let wrapped = anyCodable(from: v) { d[k] = wrapped }
        }
        return .dict(d)
    case .null:           return .null
    case .data:           return nil
    @unknown default:     return nil
    }
}

/// Produce a human-readable description of a Value for confirmation messages.
private func describeValue(_ value: Value) -> String {
    switch value {
    case .string(let s):  return "\"\(s)\""
    case .bool(let b):    return b ? "true" : "false"
    case .int(let i):     return String(i)
    case .double(let d):  return String(d)
    case .array:          return "[array]"
    case .object:         return "{object}"
    case .null:           return "null"
    case .data:           return "<binary data>"
    @unknown default:     return "unknown"
    }
}

// MARK: - Value string extension (internal — shared with WaveHelperHandlers)

extension Value {
    /// Convenience: extract string from .string case.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
