// WaveConfigAdapter.swift

// Pineapple 🍍
//
// Thread-safe actor for reading and writing Wave Terminal JSON config files.
// All writes create a timestamped backup and merge into existing content —
// they never clobber unknown keys.

import Foundation
import Logging

// MARK: - WaveConfigManager

/// Actor-based manager for Wave Terminal's JSON configuration files.
/// Auto-detects config directory: ~/.config/waveterm/ (XDG) or ~/.waveterm/ (legacy).
actor WaveConfigManager {
    let configDir: URL
    private let logger: Logger
    /// When true (default), create a timestamped backup before overwriting any config file.
    var backupBeforeWrite: Bool = true

    init(configDir: String? = nil, logger: Logger = Logger(label: "seashell.wave-config")) {
        let resolved: String
        if let configDir = configDir {
            resolved = configDir
        } else {
            resolved = WaveConfigManager.detectConfigDir()
        }
        let expanded = NSString(string: resolved).expandingTildeInPath
        self.configDir = URL(fileURLWithPath: expanded)
        self.logger = logger
    }

    /// Auto-detect the Wave Terminal config directory by checking known locations.
    private static func detectConfigDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // XDG location (Wave 0.10+)
        let xdgPath = "\(home)/.config/waveterm"
        // Legacy location
        let legacyPath = "\(home)/.waveterm"
        if FileManager.default.fileExists(atPath: xdgPath + "/settings.json") {
            return xdgPath
        } else if FileManager.default.fileExists(atPath: xdgPath) {
            return xdgPath
        } else if FileManager.default.fileExists(atPath: legacyPath) {
            return legacyPath
        }
        // Default to XDG if nothing found
        return xdgPath
    }

    func setBackupBeforeWrite(_ value: Bool) {
        backupBeforeWrite = value
    }

    // MARK: - Installation check

    /// Returns true if the Wave config directory exists.
    func waveIsInstalled() -> Bool {
        FileManager.default.fileExists(atPath: configDir.path)
    }

    /// Returns true if a specific config file exists.
    func configFileExists(_ filename: String) -> Bool {
        let url = configDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Settings (settings.json)

    /// Read all settings. Returns empty dict if file doesn't exist.
    func readSettings() throws -> [String: AnyCodableValue] {
        let filename = "settings.json"
        guard configFileExists(filename) else {
            logger.debug("settings.json does not exist, returning empty settings")
            return [:]
        }
        let data = try readConfigFile(filename)
        return try decodeDict(data, filename: filename)
    }

    /// Update a single setting, preserving all other keys.
    func writeSetting(key: String, value: AnyCodableValue) throws {
        try writeSettings([key: value])
    }

    /// Merge a set of settings into the existing settings.json.
    func writeSettings(_ updates: [String: AnyCodableValue]) throws {
        let filename = "settings.json"

        // Read existing, merge, write back
        var existing: [String: AnyCodableValue]
        if configFileExists(filename) {
            let data = try readConfigFile(filename)
            existing = try decodeDict(data, filename: filename)
        } else {
            existing = [:]
        }

        for (k, v) in updates {
            existing[k] = v
        }

        let data = try encodeDict(existing, filename: filename)
        try writeConfigFile(filename, data: data)
        logger.info("Wave settings updated: \(updates.keys.joined(separator: ", "))")
    }

    // MARK: - Widgets (widgets.json)

    /// Read all widget definitions. Returns empty dict if file doesn't exist.
    func readWidgets() throws -> [String: WidgetConfig] {
        let filename = "widgets.json"
        guard configFileExists(filename) else {
            logger.debug("widgets.json does not exist, returning empty widgets")
            return [:]
        }
        let data = try readConfigFile(filename)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: WidgetConfig].self, from: data)
        } catch {
            throw WaveConfigError.decodingFailed("widgets.json: \(error.localizedDescription)")
        }
    }

    /// Write or replace a single widget, preserving all other widgets.
    func writeWidget(id: String, config: WidgetConfig) throws {
        guard !id.isEmpty else {
            throw WaveConfigError.invalidInput("Widget ID cannot be empty")
        }

        let filename = "widgets.json"
        var existing = (try? readWidgets()) ?? [:]
        existing[id] = config

        let data = try encodeWidgets(existing, filename: filename)
        try writeConfigFile(filename, data: data)
        logger.info("Wave widget written: \(id)")
    }

    /// Delete a widget by ID, preserving all other widgets.
    func deleteWidget(id: String) throws {
        let filename = "widgets.json"
        var existing = (try? readWidgets()) ?? [:]

        guard existing[id] != nil else {
            throw WaveConfigError.invalidInput("Widget not found: \(id)")
        }

        existing.removeValue(forKey: id)
        let data = try encodeWidgets(existing, filename: filename)
        try writeConfigFile(filename, data: data)
        logger.info("Wave widget deleted: \(id)")
    }

    // MARK: - AI Presets (aipresets.json)

    /// Read all AI presets. Returns empty dict if file doesn't exist.
    func readAIPresets() throws -> [String: AIPresetConfig] {
        let filename = "aipresets.json"
        guard configFileExists(filename) else {
            logger.debug("aipresets.json does not exist, returning empty presets")
            return [:]
        }
        let data = try readConfigFile(filename)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: AIPresetConfig].self, from: data)
        } catch {
            throw WaveConfigError.decodingFailed("aipresets.json: \(error.localizedDescription)")
        }
    }

    /// Write or replace a single AI preset, preserving all other presets.
    func writeAIPreset(id: String, config: AIPresetConfig) throws {
        guard !id.isEmpty else {
            throw WaveConfigError.invalidInput("AI preset ID cannot be empty")
        }

        let filename = "aipresets.json"
        var existing = (try? readAIPresets()) ?? [:]
        existing[id] = config

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(existing)
        } catch {
            throw WaveConfigError.encodingFailed("aipresets.json: \(error.localizedDescription)")
        }
        try writeConfigFile(filename, data: data)
        logger.info("Wave AI preset written: \(id)")
    }

    /// Delete an AI preset by ID.
    func deleteAIPreset(id: String) throws {
        let filename = "aipresets.json"
        var existing = (try? readAIPresets()) ?? [:]

        guard existing[id] != nil else {
            throw WaveConfigError.invalidInput("AI preset not found: \(id)")
        }

        existing.removeValue(forKey: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(existing)
        } catch {
            throw WaveConfigError.encodingFailed("aipresets.json: \(error.localizedDescription)")
        }
        try writeConfigFile(filename, data: data)
        logger.info("Wave AI preset deleted: \(id)")
    }

    // MARK: - Backgrounds (backgrounds.json)

    /// Read all backgrounds. Returns raw dict for flexibility.
    func readBackgrounds() throws -> [String: AnyCodableValue] {
        let filename = "backgrounds.json"
        guard configFileExists(filename) else {
            logger.debug("backgrounds.json does not exist, returning empty backgrounds")
            return [:]
        }
        let data = try readConfigFile(filename)
        return try decodeDict(data, filename: filename)
    }

    // MARK: - Backup

    /// Create a timestamped backup of a config file.
    /// Returns the URL of the backup file.
    @discardableResult
    func backupFile(_ filename: String) throws -> URL {
        let url = configDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Nothing to back up
            return url
        }

        let timestamp = makeTimestamp()
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        let backupName = "\(base).backup-\(timestamp).\(ext)"
        let backupUrl = configDir.appendingPathComponent(backupName)

        do {
            try FileManager.default.copyItem(at: url, to: backupUrl)
            logger.debug("Backed up \(filename) → \(backupName)")
            return backupUrl
        } catch {
            throw WaveConfigError.backupFailed("Could not back up \(filename): \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    private func readConfigFile(_ filename: String) throws -> Data {
        let url = configDir.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw WaveConfigError.fileNotFound(filename)
        }
    }

    private func writeConfigFile(_ filename: String, data: Data) throws {
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            throw WaveConfigError.writeFailed("Cannot create config directory: \(error.localizedDescription)")
        }

        // Backup before write if configured
        if backupBeforeWrite && configFileExists(filename) {
            try backupFile(filename)
        }

        // Write atomically
        let url = configDir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WaveConfigError.writeFailed("Failed to write \(filename): \(error.localizedDescription)")
        }
    }

    private func decodeDict(_ data: Data, filename: String) throws -> [String: AnyCodableValue] {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: AnyCodableValue].self, from: data)
        } catch {
            throw WaveConfigError.decodingFailed("\(filename): \(error.localizedDescription)")
        }
    }

    private func encodeDict(_ dict: [String: AnyCodableValue], filename: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(dict)
        } catch {
            throw WaveConfigError.encodingFailed("\(filename): \(error.localizedDescription)")
        }
    }

    private func encodeWidgets(_ widgets: [String: WidgetConfig], filename: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(widgets)
        } catch {
            throw WaveConfigError.encodingFailed("\(filename): \(error.localizedDescription)")
        }
    }

    private func makeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = formatter.string(from: Date())
        // Append 4-char hex to avoid collisions when multiple writes happen within one second
        let suffix = String(format: "%04x", Int.random(in: 0...0xFFFF))
        return "\(base)-\(suffix)"
    }
}

// MARK: - Formatting helpers (non-actor)

/// Pretty-print any Encodable as JSON string.
func formatJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

/// Filter a settings dictionary to only keys matching a namespace prefix.
/// e.g. filterByNamespace(settings, "ai") returns all keys starting with "ai:"
func filterByNamespace(_ settings: [String: AnyCodableValue], _ namespace: String) -> [String: AnyCodableValue] {
    let prefix = namespace.hasSuffix(":") ? namespace : "\(namespace):"
    return settings.filter { $0.key.hasPrefix(prefix) || $0.key == namespace }
}
