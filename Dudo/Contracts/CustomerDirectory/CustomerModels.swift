import Foundation

// MARK: - Customer Directory, contract v1 — wire shapes
//
// A Swift transcription of packages/contracts/apps/customers/customer-directory-v1.schema.json
// in Dudo-Core. These types EXIST TO MATCH THAT CONTRACT and for no other reason. The Apple
// client is a consumer of the contract; it never authors one. If a shape here disagrees with
// the schema, the schema is right and this file is a defect.
//
// The `CodingKeys` on every type carry the snake_case wire names even though nothing in this
// slice sends or receives JSON. They are here so that the day a real transport lands, the
// mapping is already stated and reviewed rather than invented in a hurry.
//
// EVERY OPTIONAL FIELD IS PRESENT AND NULL ON THE WIRE, never absent (schema, `customer`).
// Swift's `Optional` models exactly that, and the decoders below use `decode` rather than
// `decodeIfPresent` so that an absent key is a decoding failure and not a silent nil.

/// Whether a customer is a natural person or an organisation.
///
/// Lowercase string enumeration, never an integer. Adding a member is a breaking change for
/// any client that switches on it, so this enum is deliberately not `@unknown`-tolerant: a
/// third member is a contract revision, not a patch.
nonisolated enum CustomerType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case person
    case company

    var id: String { rawValue }
}

/// The lifecycle state. SERVER-CONTROLLED — never accepted on create or update.
///
/// `pendingDeletion` is contracted and is reachable only through `DeleteCustomer`, which is
/// out of scope for the MVP (contract §11.1). This client must therefore *tolerate and
/// display* the state without ever being able to produce it. That is required behaviour, not
/// dead code: "a client must tolerate a status it will never see in this slice rather than
/// crash on it".
nonisolated enum CustomerStatus: String, Codable, Hashable, Sendable {
    case active
    case archived
    case pendingDeletion = "pending_deletion"
}

/// Which lifecycle states a listing or a search returns. Defaults to `active`.
nonisolated enum CustomerStatusFilter: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case active
    case archived
    case pendingDeletion = "pending_deletion"
    case all

    var id: String { rawValue }

    /// The contract default. Archiving means withdrawing a record from normal use, so a
    /// listing that kept showing archived rows would undo the operation the user performed.
    static let contractDefault: CustomerStatusFilter = .active

    func matches(_ status: CustomerStatus) -> Bool {
        switch self {
        case .all: return true
        case .active: return status == .active
        case .archived: return status == .archived
        case .pendingDeletion: return status == .pendingDeletion
        }
    }
}

/// The full wire representation of a Customer — all fifteen fields.
///
/// Returned by CreateCustomer, GetCustomer, UpdateCustomer, ArchiveCustomer, RestoreCustomer
/// and MoveCustomerToBusiness.
///
/// There is no `organization_id` here and there never will be: the Organization is the
/// isolation boundary, derived server-side, and no client ever learns a tenant identifier it
/// could be tempted to send back. `business_id` *is* present — it is an authorization scope
/// inside one Organization, and a client must be able to show which Business a record is in.
nonisolated struct Customer: Identifiable, Hashable, Sendable, Codable {
    let customerID: String
    let businessID: String
    let displayName: String
    let customerType: CustomerType
    let email: String?
    let phone: String?
    let country: String?
    let address: String?
    let notes: String?
    let status: CustomerStatus
    /// Non-null if and only if `status == .pendingDeletion`. Returned rather than computed,
    /// so that both clients show one date for one legally meaningful deadline.
    let deletionScheduledAt: Date?
    let createdAt: Date
    let createdByPrincipalID: String
    let updatedAt: Date
    let updatedByPrincipalID: String

    var id: String { customerID }

    enum CodingKeys: String, CodingKey {
        case customerID = "customer_id"
        case businessID = "business_id"
        case displayName = "display_name"
        case customerType = "customer_type"
        case email
        case phone
        case country
        case address
        case notes
        case status
        case deletionScheduledAt = "deletion_scheduled_at"
        case createdAt = "created_at"
        case createdByPrincipalID = "created_by_principal_id"
        case updatedAt = "updated_at"
        case updatedByPrincipalID = "updated_by_principal_id"
    }

    /// The list projection of this record, used by the fixture repository so that one seed
    /// produces both shapes without them being able to drift.
    var summary: CustomerSummary {
        CustomerSummary(
            customerID: customerID,
            businessID: businessID,
            displayName: displayName,
            customerType: customerType,
            email: email,
            phone: phone,
            country: country,
            status: status,
            deletionScheduledAt: deletionScheduledAt,
            updatedAt: updatedAt
        )
    }
}

/// One row of the directory — the projection returned by ListCustomers and SearchCustomers.
///
/// It deliberately EXCLUDES `address` and `notes`, the two sensitive-personal free-text
/// fields. That exclusion is the whole reason `list` is a separate permission from `read`,
/// and this client must never reconstruct either field from a listing. Reaching them takes
/// a GetCustomer, one record at a time.
nonisolated struct CustomerSummary: Identifiable, Hashable, Sendable, Codable {
    let customerID: String
    let businessID: String
    let displayName: String
    let customerType: CustomerType
    let email: String?
    let phone: String?
    let country: String?
    let status: CustomerStatus
    let deletionScheduledAt: Date?
    let updatedAt: Date

    var id: String { customerID }

    enum CodingKeys: String, CodingKey {
        case customerID = "customer_id"
        case businessID = "business_id"
        case displayName = "display_name"
        case customerType = "customer_type"
        case email
        case phone
        case country
        case status
        case deletionScheduledAt = "deletion_scheduled_at"
        case updatedAt = "updated_at"
    }
}

/// The standard collection envelope: a page and a continuation token.
///
/// There is NO total count, deliberately, and the consequence is a product one this client
/// must live with: Dudo cannot show "247 customers" anywhere.
nonisolated struct CustomerPage: Hashable, Sendable, Codable {
    let data: [CustomerSummary]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }

    static let empty = CustomerPage(data: [], nextCursor: nil)
}

// MARK: - Pagination

/// Cursor pagination only. Default page size 25, maximum 100 — both fixed by
/// `urn:dudo:schema:pagination:1`.
nonisolated enum CustomerPagination {
    static let defaultPageSize = 25
    static let maximumPageSize = 100
}

// MARK: - Wire coding

nonisolated extension Customer {
    /// Timestamps are RFC 3339 with an explicit offset. Stated here so that the transport,
    /// when it exists, does not get to choose a different one per client.
    static func wireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Fractional seconds are OPTIONAL in the contract pattern, so both forms are
            // accepted. A parser that handled only one would reject valid server output.
            // `Date.ISO8601FormatStyle` is a value type, so it is built here rather than held
            // in a shared formatter that would have to be made safe to share.
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "not RFC 3339")
            )
        }
        return decoder
    }
}
