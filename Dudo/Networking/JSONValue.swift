import Foundation

/// A JSON value this client can construct and send.
///
/// ===========================================================================================
/// WHY A TYPE INSTEAD OF `[String: Any]`
/// ===========================================================================================
///
/// UpdateCustomer needs a three-way distinction the contract states as normative: a field
/// ABSENT means unchanged, PRESENT WITH A VALUE means set, and PRESENT AND NULL means cleared.
/// `Codable` synthesis cannot express that — an `Optional` property encodes to either a value
/// or nothing, and `encodeIfPresent` versus `encode` is a choice made once for the whole type
/// rather than per request. Writing the body as a value lets `.null` and "absent" be two
/// different things, which is what the contract requires and what stops this client silently
/// clearing a customer's address.
///
/// `[String: Any]` would do the same job and is what one would reach for first. It is not
/// `Sendable`, so it cannot cross into the concurrent executor the transport runs on without
/// an unchecked escape hatch — and an unchecked escape hatch on the type carrying a customer's
/// data is not worth saving forty lines.
nonisolated indirect enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }

    /// An optional string as the contract means it: a value, or an explicit null.
    ///
    /// Used on CREATE, where the schema says "an optional field may be omitted or supplied as
    /// null; both mean 'not recorded'". Sending the explicit null is preferred over omitting
    /// the key because it makes the request say what it means.
    static func optionalString(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }
}

nonisolated extension FieldUpdate where Value == String {
    /// The three-way distinction, rendered into a request body.
    ///
    /// Returns `nil` for `.unchanged`, and the CALLER MUST OMIT THE KEY ENTIRELY when it does.
    /// Encoding `.unchanged` as a null would clear the field — the exact silent data loss the
    /// contract calls out as the reason it states this rule as normative.
    var jsonValueIfPresent: JSONValue? {
        switch self {
        case .unchanged: nil
        case .set(let value): .string(value)
        case .cleared: .null
        }
    }
}
