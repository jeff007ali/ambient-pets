import Foundation

/// A loosely typed JSON value, used for open-ended parameter bags (effect params).
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var double: Double? { if case .number(let n) = self { n } else { nil } }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` with a default, so new fields never break old files.
    func decode<T: Decodable>(_ key: Key, default value: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value()
    }
}

/// Human-readable description of a decoding error (path + reason).
public func describeDecodingError(_ error: Error) -> String {
    guard let error = error as? DecodingError else { return String(describing: error) }
    func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return p.isEmpty ? "<root>" : p
    }
    switch error {
    case .keyNotFound(let key, let ctx): return "\(path(ctx)): missing key '\(key.stringValue)'"
    case .typeMismatch(_, let ctx): return "\(path(ctx)): \(ctx.debugDescription)"
    case .valueNotFound(_, let ctx): return "\(path(ctx)): \(ctx.debugDescription)"
    case .dataCorrupted(let ctx): return "\(path(ctx)): \(ctx.debugDescription)"
    @unknown default: return String(describing: error)
    }
}
