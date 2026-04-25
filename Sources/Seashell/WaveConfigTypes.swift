// WaveConfigTypes.swift

// Pineapple 🍍
//
// Swift type definitions matching Wave Terminal's JSON schemas.
// Wave uses colon-namespaced keys (ai:model, cmd:cwd, term:theme) which cannot
// be expressed as Swift property names. All config data uses [String: AnyCodableValue]
// dictionaries to preserve these keys faithfully.

import Foundation

// MARK: - AnyCodableValue

/// A type-erased Codable value that handles mixed JSON types.
/// Required because Wave config files contain heterogeneous values
/// (strings, ints, doubles, bools, arrays, nested objects).
public enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dict([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let v = try? container.decode(Int.self) {
            self = .int(v)
            return
        }
        if let v = try? container.decode(Double.self) {
            self = .double(v)
            return
        }
        if let v = try? container.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
            return
        }
        if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .dict(v)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "AnyCodableValue: unsupported JSON type"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v):  try container.encode(v)
        case .int(let v):     try container.encode(v)
        case .double(let v):  try container.encode(v)
        case .bool(let v):    try container.encode(v)
        case .array(let v):   try container.encode(v)
        case .dict(let v):    try container.encode(v)
        case .null:           try container.encodeNil()
        }
    }

    // MARK: Convenience accessors

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int(v) }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    public var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    public var dictValue: [String: AnyCodableValue]? {
        if case .dict(let v) = self { return v }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Factory helpers

    /// Wrap any Swift value into AnyCodableValue (best effort).
    public static func from(_ value: Any) -> AnyCodableValue? {
        switch value {
        case let v as String:    return .string(v)
        case let v as Bool:      return .bool(v)   // Bool must be before Int (Bool is Int in ObjC bridge)
        case let v as Int:       return .int(v)
        case let v as Double:    return .double(v)
        case let v as Float:     return .double(Double(v))
        case is NSNull:          return .null
        case let v as [Any]:
            let items = v.compactMap { AnyCodableValue.from($0) }
            return .array(items)
        case let v as [String: Any]:
            var d: [String: AnyCodableValue] = [:]
            for (k, val) in v {
                if let wrapped = AnyCodableValue.from(val) {
                    d[k] = wrapped
                }
            }
            return .dict(d)
        default:
            return nil
        }
    }
}

// MARK: - Dictionary helpers

public extension Dictionary where Key == String, Value == AnyCodableValue {
    func getString(_ key: String) -> String? {
        return self[key]?.stringValue
    }

    func getInt(_ key: String) -> Int? {
        return self[key]?.intValue
    }

    func getBool(_ key: String) -> Bool? {
        return self[key]?.boolValue
    }

    func getDouble(_ key: String) -> Double? {
        return self[key]?.doubleValue
    }

    func getArray(_ key: String) -> [AnyCodableValue]? {
        return self[key]?.arrayValue
    }

    func getDict(_ key: String) -> [String: AnyCodableValue]? {
        return self[key]?.dictValue
    }
}

// MARK: - Wave Widget types
// Maps to widgets.json WidgetConfigType schema.
// NOTE: Colon-namespaced display keys (display:order, display:hidden) are
// encoded via manual CodingKeys.

public struct WidgetConfig: Codable {
    public var icon: String?
    public var color: String?
    public var label: String?
    public var description: String?
    public var displayOrder: Double?
    public var displayHidden: Bool?
    public var magnified: Bool?
    public var workspaces: [String]?
    public var blockdef: BlockDef

    enum CodingKeys: String, CodingKey {
        case icon
        case color
        case label
        case description
        case displayOrder  = "display:order"
        case displayHidden = "display:hidden"
        case magnified
        case workspaces
        case blockdef
    }

    public init(blockdef: BlockDef,
                icon: String? = nil,
                color: String? = nil,
                label: String? = nil,
                description: String? = nil,
                displayOrder: Double? = nil,
                displayHidden: Bool? = nil,
                magnified: Bool? = nil,
                workspaces: [String]? = nil) {
        self.blockdef = blockdef
        self.icon = icon
        self.color = color
        self.label = label
        self.description = description
        self.displayOrder = displayOrder
        self.displayHidden = displayHidden
        self.magnified = magnified
        self.workspaces = workspaces
    }
}

/// Maps to BlockDef in widgets.json schema.
/// `meta` uses [String: AnyCodableValue] to support colon-namespaced keys like
/// cmd:cwd, term:theme, cmd:runonstart, etc.
public struct BlockDef: Codable {
    public var meta: [String: AnyCodableValue]
    public var files: [String: FileDef]?

    public init(meta: [String: AnyCodableValue], files: [String: FileDef]? = nil) {
        self.meta = meta
        self.files = files
    }
}

/// Maps to FileDef in widgets.json schema.
public struct FileDef: Codable {
    public var content: String?
    public var meta: [String: AnyCodableValue]?

    public init(content: String? = nil, meta: [String: AnyCodableValue]? = nil) {
        self.content = content
        self.meta = meta
    }
}

// MARK: - Wave AI Preset types
// Maps to aipresets.json AiSettingsType.
// Stored as [String: AnyCodableValue] to preserve all colon-namespaced keys.

public struct AIPresetConfig: Codable {
    /// All AI preset keys stored in their original colon-namespaced form.
    /// e.g. "ai:model", "ai:apitoken", "display:name"
    public var settings: [String: AnyCodableValue]

    public init(settings: [String: AnyCodableValue] = [:]) {
        self.settings = settings
    }

    // MARK: - Codable (flat key encoding)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.settings = try container.decode([String: AnyCodableValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(settings)
    }

    // MARK: - Convenience accessors

    public var displayName: String? {
        return settings.getString("display:name")
    }

    public var displayOrder: Double? {
        return settings.getDouble("display:order")
    }

    public var aiModel: String? {
        return settings.getString("ai:model")
    }

    public var aiApiType: String? {
        return settings.getString("ai:apitype")
    }

    public var aiBaseUrl: String? {
        return settings.getString("ai:baseurl")
    }

    public var aiName: String? {
        return settings.getString("ai:name")
    }
}

// MARK: - Wave errors

public enum WaveConfigError: LocalizedError {
    case notInstalled(String)
    case fileNotFound(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case writeFailed(String)
    case backupFailed(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let path):
            return "Wave Terminal is not installed. Config directory not found at \(path)"
        case .fileNotFound(let name):
            return "Wave config file not found: \(name)"
        case .encodingFailed(let detail):
            return "Failed to encode Wave config: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode Wave config: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write Wave config: \(detail)"
        case .backupFailed(let detail):
            return "Failed to back up Wave config: \(detail)"
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        }
    }
}
