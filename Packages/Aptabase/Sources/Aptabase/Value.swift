import Foundation

/// Protocol for supported property values.
public protocol Value {}
extension Int: Value {}
extension Double: Value {}
extension String: Value {}
extension Float: Value {}
extension Bool: Value {}

public enum AnyCodableValue: Codable, Sendable, Equatable {
    case integer(Int)
    case string(String)
    case float(Float)
    case double(Double)
    case boolean(Bool)
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .integer(x):
            try container.encode(x)
        case let .string(x):
            try container.encode(x)
        case let .float(x):
            try container.encode(x)
        case let .double(x):
            try container.encode(x)
        case let .boolean(x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Float.self) {
            self = .float(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Aptabase property value")
        }
    }
}
