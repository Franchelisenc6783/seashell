// WaveHelperHandlers.swift

// Pineapple 🍍
//
// MCP tool handlers that delegate to the Wave helper block via TCP.
// Every handler gracefully degrades: if the helper is not connected it returns
// a clear error message telling the user how to start it.

import Foundation
import MCP
import Logging

// MARK: - Auto-connect + shared error

/// Ensures the helper is connected, retrying a few times if needed.
/// Returns nil if connected (caller can proceed), or an error result if unavailable.
private func ensureHelperConnected(toolName: String) async -> CallTool.Result? {
    if await connectHelperWithRetry() { return nil }

    return .init(content: [.text("""
        ⚠️  Wave helper block is not connected.

        Helper-block tools (\(toolName)) require the Seashell Helper running inside Wave Terminal.

        To start it:
        1. Open Wave Terminal
        2. Click the "Seashell Helper" widget in the widget bar
        3. Wait for "Wave environment ready" to appear in the block
        4. Try this tool again

        Direct-config tools (wave_get_settings, wave_get_widgets, etc.) work without the helper.
        """)], isError: true)
}

/// Describe an AnyCodableValue result as a formatted JSON string for MCP output.
private func resultJSON(_ value: AnyCodableValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let str = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return str
}

// MARK: - wave_list_workspaces

/// List all Wave workspaces (requires helper).
func handleWaveListWorkspaces(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    if let err = await ensureHelperConnected(toolName: "wave_list_workspaces") { return err }

    do {
        let result = try await sharedWaveHelperClient.listWorkspaces()
        return .init(content: [.text("Wave workspaces:\n\n\(resultJSON(result))")])
    } catch {
        return .init(content: [.text("Error listing workspaces: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wave_list_blocks

/// List blocks in Wave, optionally filtered (requires helper).
func handleWaveListBlocks(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    if let err = await ensureHelperConnected(toolName: "wave_list_blocks") { return err }

    let workspaceId = params.arguments?["workspace_id"]?.stringValue
    let tabId       = params.arguments?["tab_id"]?.stringValue
    let view        = params.arguments?["view"]?.stringValue

    do {
        let result = try await sharedWaveHelperClient.listBlocks(
            workspaceId: workspaceId,
            tabId: tabId,
            view: view
        )
        return .init(content: [.text("Wave blocks:\n\n\(resultJSON(result))")])
    } catch {
        return .init(content: [.text("Error listing blocks: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wave_create_block

/// Create a new Wave block (requires helper, Tier B).
func handleWaveCreateBlock(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let tabIdValue = arguments["tab_id"], case .string(let tabId) = tabIdValue, !tabId.isEmpty else {
        return .init(content: [.text("Missing required parameter: tab_id")], isError: true)
    }

    guard let viewValue = arguments["view"], case .string(let view) = viewValue else {
        return .init(content: [.text("Missing required parameter: view (term, preview, web, sysinfo)")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_create_block",
            action: "Create a new '\(view)' block in tab '\(tabId)'",
            targetFile: "Wave Terminal (live block)"
        ))])
    }

    if let err = await ensureHelperConnected(toolName: "wave_create_block") { return err }

    // Build meta dict
    var meta: [String: AnyCodableValue] = ["view": .string(view)]

    if let cmdValue = arguments["command"], case .string(let cmd) = cmdValue {
        meta["controller"] = .string("cmd")
        meta["cmd"] = .string(cmd)
    }
    if let cwdValue = arguments["cwd"], case .string(let cwd) = cwdValue {
        meta["cmd:cwd"] = .string(cwd)
    }
    if let runOnStart = arguments["run_on_start"], case .bool(let b) = runOnStart {
        meta["cmd:runonstart"] = .bool(b)
    }
    if let closeOnExit = arguments["close_on_exit"], case .bool(let b) = closeOnExit {
        meta["cmd:closeonexit"] = .bool(b)
    }
    if let urlValue = arguments["url"], case .string(let url) = urlValue {
        meta["url"] = .string(url)
    }
    if let fileValue = arguments["file"], case .string(let file) = fileValue {
        meta["file"] = .string(file)
    }

    do {
        let result = try await sharedWaveHelperClient.createBlock(tabId: tabId, meta: meta)
        let blockId = result.dictValue?["block_id"]?.stringValue ?? "unknown"
        logger.info("Wave block created: \(blockId) in tab \(tabId)")
        return .init(content: [.text("✓ Wave block created:\n\n\(resultJSON(result))")])
    } catch {
        return .init(content: [.text("Error creating Wave block: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wave_delete_block

/// Delete a Wave block (requires helper, Tier B).
func handleWaveDeleteBlock(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let blockIdValue = arguments["block_id"], case .string(let blockId) = blockIdValue, !blockId.isEmpty else {
        return .init(content: [.text("Missing required parameter: block_id")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_delete_block",
            action: "Delete block '\(blockId)' from Wave Terminal",
            targetFile: "Wave Terminal (live block)"
        ))])
    }

    if let err = await ensureHelperConnected(toolName: "wave_delete_block") { return err }

    do {
        _ = try await sharedWaveHelperClient.deleteBlock(blockId: blockId)
        logger.info("Wave block deleted: \(blockId)")
        return .init(content: [.text("✓ Wave block deleted: '\(blockId)'")])
    } catch {
        return .init(content: [.text("Error deleting Wave block: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wave_get_scrollback

/// Get terminal scrollback from a Wave block (requires helper).
func handleWaveGetScrollback(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let blockIdValue = arguments["block_id"], case .string(let blockId) = blockIdValue, !blockId.isEmpty else {
        return .init(content: [.text("Missing required parameter: block_id")], isError: true)
    }

    let lastCommandOnly: Bool
    if let v = arguments["last_command_only"], case .bool(let b) = v {
        lastCommandOnly = b
    } else {
        lastCommandOnly = false
    }

    if let err = await ensureHelperConnected(toolName: "wave_get_scrollback") { return err }

    do {
        let result = try await sharedWaveHelperClient.getScrollback(blockId: blockId, lastCommandOnly: lastCommandOnly)

        if let dict = result.dictValue,
           let lines = dict["lines"]?.arrayValue {
            let text = lines.compactMap { $0.stringValue }.joined(separator: "\n")
            let count = dict["line_count"]?.intValue ?? lines.count
            return .init(content: [.text("Scrollback from block '\(blockId)' (\(count) lines):\n\n\(text)")])
        }

        return .init(content: [.text("Scrollback (raw):\n\n\(resultJSON(result))")])
    } catch {
        return .init(content: [.text("Error getting scrollback: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wave_run_in_block

/// Run a command in a new Wave terminal block (requires helper, Tier B).
func handleWaveRunInBlock(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    guard let tabIdValue = arguments["tab_id"], case .string(let tabId) = tabIdValue, !tabId.isEmpty else {
        return .init(content: [.text("Missing required parameter: tab_id")], isError: true)
    }

    guard let cmdValue = arguments["command"], case .string(let command) = cmdValue, !command.isEmpty else {
        return .init(content: [.text("Missing required parameter: command")], isError: true)
    }

    // Tier B confirmation
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_run_in_block",
            action: "Run '\(command.prefix(60))' in a new Wave block (tab: \(tabId))",
            targetFile: "Wave Terminal (new block)"
        ))])
    }

    if let err = await ensureHelperConnected(toolName: "wave_run_in_block") { return err }

    let cwd: String? = arguments["cwd"].flatMap { if case .string(let s) = $0 { return s } else { return nil } }
    let closeOnExit: Bool
    if let v = arguments["close_on_exit"], case .bool(let b) = v {
        closeOnExit = b
    } else {
        closeOnExit = false
    }

    // Build env dict if provided
    var env: [String: AnyCodableValue]? = nil
    if let envValue = arguments["env"], case .object(let envObj) = envValue {
        var d: [String: AnyCodableValue] = [:]
        for (k, v) in envObj {
            if case .string(let s) = v { d[k] = .string(s) }
        }
        if !d.isEmpty { env = d }
    }

    do {
        let result = try await sharedWaveHelperClient.runCommand(
            tabId: tabId, command: command, cwd: cwd, env: env, closeOnExit: closeOnExit
        )
        let blockId = result.dictValue?["block_id"]?.stringValue ?? "unknown"
        logger.info("Wave command started in block: \(blockId)")
        return .init(content: [.text("✓ Command running in Wave block '\(blockId)':\n\(command)")])
    } catch {
        return .init(content: [.text("Error running command in Wave: \(error.localizedDescription)")], isError: true)
    }
}

// MARK: - wsh direct fallback (direct path for view/edit)

/// Path to the wsh binary installed by Wave Terminal.
private let wshPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/Application Support/waveterm/bin/wsh"
}()

/// Returns true if WAVETERM_JWT is present in the environment — meaning this
/// process was launched from inside a Wave terminal tab and can call wsh directly.
private var hasWaveJWT: Bool {
    ProcessInfo.processInfo.environment["WAVETERM_JWT"] != nil
}

/// Spawn wsh with the given arguments, inheriting the current environment
/// (which includes WAVETERM_JWT when Claude Code runs inside Wave).
/// Returns the stdout output or throws on non-zero exit.
private func runWsh(_ args: [String]) async throws -> String {
    guard FileManager.default.fileExists(atPath: wshPath) else {
        throw NSError(domain: "wsh", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "wsh not found at \(wshPath)"])
    }

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: wshPath)
            process.arguments = args
            process.environment = ProcessInfo.processInfo.environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let out = String(
                    data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let err = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let msg = err.isEmpty ? out : err
                    continuation.resume(throwing: NSError(
                        domain: "wsh", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)]
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - wave_view_file

/// Open a file for preview in Wave.
///
/// Resolution order:
///   1. Helper TCP RPC  (helper block connected)
///   2. wsh direct call (direct fallback — WAVETERM_JWT inherited from Wave tab)
///   3. Error with actionable message
func handleWaveViewFile(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    // tab_id is only needed for the helper path; wsh uses current Wave context
    let tabId = arguments["tab_id"]?.stringValue ?? ""

    guard let fileValue = arguments["file"], case .string(let file) = fileValue, !file.isEmpty else {
        return .init(content: [.text("Missing required parameter: file")], isError: true)
    }

    // ── Auto-connect helper if not already connected (with retry) ────────────
    _ = await connectHelperWithRetry()

    // ── Helper TCP RPC ──────────────────────────────────────────────────────
    if await sharedWaveHelperClient.isConnected() {
        guard !tabId.isEmpty else {
            return .init(content: [.text("Missing required parameter: tab_id (needed when helper is connected)")], isError: true)
        }
        do {
            let result = try await sharedWaveHelperClient.viewFile(tabId: tabId, file: file)
            let blockId = result.dictValue?["block_id"]?.stringValue ?? "unknown"
            logger.info("wave_view_file via helper: block \(blockId)")
            return .init(content: [.text("✓ File preview opened in Wave block '\(blockId)':\n\(file)")])
        } catch {
            logger.warning("wave_view_file helper error, trying wsh fallback: \(error)")
            // fall through to wsh
        }
    }

    // ── direct fallback: wsh direct ─────────────────────────────────────────
    if hasWaveJWT {
        do {
            _ = try await runWsh(["view", file])
            logger.info("wave_view_file via wsh direct: \(file)")
            return .init(content: [.text("✓ File preview opened in Wave (wsh direct):\n\(file)")])
        } catch {
            return .init(content: [.text("wsh view failed: \(error.localizedDescription)")], isError: true)
        }
    }

    // ── No path available ─────────────────────────────────────────────────────
    return .init(content: [.text("""
        ⚠️  wave_view_file: no available path to Wave Terminal.

        Option A — Run Claude Code inside a Wave terminal tab.
          Claude Code inherits WAVETERM_JWT from the Wave shell, which allows
          wsh to open preview blocks directly without the helper.

        Option B — Start the Seashell Helper widget.
          Open Wave Terminal → click "Seashell Helper" in the widget bar.
          Then call wave_connect_helper and retry.
        """)], isError: true)
}

// MARK: - wave_edit_file

/// Open a file for editing in Wave.
///
/// Resolution order:
///   1. Helper TCP RPC  (helper block connected)
///   2. wsh direct call (direct fallback — WAVETERM_JWT inherited from Wave tab)
///   3. Error with actionable message
func handleWaveEditFile(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    guard let arguments = params.arguments else {
        return .init(content: [.text("Missing required parameters")], isError: true)
    }

    // tab_id only needed for helper path
    let tabId = arguments["tab_id"]?.stringValue ?? ""

    guard let fileValue = arguments["file"], case .string(let file) = fileValue, !file.isEmpty else {
        return .init(content: [.text("Missing required parameter: file")], isError: true)
    }

    // Tier B confirmation (edit modifies files)
    if !PermissionGuard.isApproved(arguments) {
        return .init(content: [.text(PermissionGuard.confirmationMessage(
            for: "wave_edit_file",
            action: "Open '\(file)' for editing in Wave",
            targetFile: file
        ))])
    }

    // ── Auto-connect helper if not already connected (with retry) ────────────
    _ = await connectHelperWithRetry()

    // ── Helper TCP RPC ──────────────────────────────────────────────────────
    if await sharedWaveHelperClient.isConnected() {
        guard !tabId.isEmpty else {
            return .init(content: [.text("Missing required parameter: tab_id (needed when helper is connected)")], isError: true)
        }
        do {
            let result = try await sharedWaveHelperClient.editFile(tabId: tabId, file: file)
            let blockId = result.dictValue?["block_id"]?.stringValue ?? "unknown"
            logger.info("wave_edit_file via helper: block \(blockId)")
            return .init(content: [.text("✓ File editor opened in Wave block '\(blockId)':\n\(file)")])
        } catch {
            logger.warning("wave_edit_file helper error, trying wsh fallback: \(error)")
            // fall through to wsh
        }
    }

    // ── direct fallback: wsh direct ─────────────────────────────────────────
    if hasWaveJWT {
        do {
            _ = try await runWsh(["edit", file])
            logger.info("wave_edit_file via wsh direct: \(file)")
            return .init(content: [.text("✓ File editor opened in Wave (wsh direct):\n\(file)\n\n💡 Tip: start the Seashell Helper widget for richer helper-block control.")])
        } catch {
            return .init(content: [.text("wsh edit failed: \(error.localizedDescription)")], isError: true)
        }
    }

    // ── No path available ─────────────────────────────────────────────────────
    return .init(content: [.text("""
        ⚠️  wave_edit_file: no available path to Wave Terminal.

        Option A — Run Claude Code inside a Wave terminal tab.
          Claude Code inherits WAVETERM_JWT from the Wave shell, which allows
          wsh to open editor blocks directly without the helper.

        Option B — Start the Seashell Helper widget.
          Open Wave Terminal → click "Seashell Helper" in the widget bar.
          Then call wave_connect_helper and retry.
        """)], isError: true)
}

// MARK: - wave_connect_helper

/// Instruct the MCP server to connect to the Wave helper block.
func handleWaveConnectHelper(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    if await sharedWaveHelperClient.isConnected() {
        return .init(content: [.text("✓ Wave helper is already connected.")])
    }

    logger.info("Attempting to connect to Wave helper on port \(config.wave.helperPort)...")
    await sharedWaveHelperClient.connect()

    if await sharedWaveHelperClient.isConnected() {
        return .init(content: [.text("✓ Connected to Wave helper on port \(config.wave.helperPort). Helper-block tools are now available.")])
    } else {
        return .init(content: [.text("""
            ✗ Could not connect to Wave helper on port \(config.wave.helperPort).

            Make sure the Seashell Helper widget is running inside Wave Terminal:
            1. Open Wave Terminal
            2. Open the "Seashell Helper" widget from the widget bar
            3. Wait for "Ready to proxy Wave RPC requests" to appear
            4. Try again
            """)], isError: true)
    }
}

// MARK: - wave_helper_status

/// Check whether the Wave helper block is connected.
func handleWaveHelperStatus(
    params: CallTool.Parameters,
    logger: Logger,
    config: Configuration
) async -> CallTool.Result {
    let connected = await sharedWaveHelperClient.isConnected()
    let status = connected ? "✓ Connected" : "✗ Not connected"
    let detail = connected
        ? "Helper-block tools (wave_list_workspaces, wave_list_blocks, wave_create_block, etc.) are available."
        : "Direct-config tools are available. Open the Seashell Helper widget in Wave to enable helper-block tools."
    return .init(content: [.text("Wave helper status: \(status)\n\(detail)")])
}

