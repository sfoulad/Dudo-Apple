import Foundation

// MARK: - A gap in the contract set, isolated rather than papered over
//
// `business_id` is REQUIRED on CreateCustomer and is shown on every row and every record.
// It is an opaque identifier. To let a person choose a Business, or to show which Business a
// customer is in, this client needs two things the published contract set does not contain:
//
//   1. A way to resolve a business_id to a name.
//   2. The set of Businesses the authenticated principal is authorized over.
//
// `Business` exists in packages/contracts/registries/core-object-registry.yaml as a
// tenant-scoped object with appAccess `read-via-contract`, status `proposed` — but no
// contract defines its shape and no Action lists it. The Customer Directory contract is
// explicit that the authorized business set is derived server-side from the authenticated
// context and never from a request, so the client cannot compute it either.
//
// WHAT THIS FILE IS. A client-local placeholder, kept in one file so that the gap is visible
// and so that the fix is a single replacement. It is NOT a contract, it is NOT a wire shape,
// and nothing here may be treated as one. It has been reported to the Team Lead as a contract
// request. Until that contract exists, the app shows names supplied by the fixture and falls
// back to the raw identifier when it has none, which is the honest rendering of an opaque id.

/// A Business the current principal may file customers into.
///
/// PLACEHOLDER — not a contracted shape. See the note above.
nonisolated struct BusinessReference: Identifiable, Hashable, Sendable {
    let id: String
    /// A human-readable label. Absent in the real world until a Business contract exists.
    let name: String?

    /// What the interface shows. A Business with no known name shows its identifier, plainly,
    /// rather than a guess or a blank.
    var displayLabel: String {
        name ?? id
    }
}

/// Supplies the Businesses the principal is authorized over.
///
/// PLACEHOLDER — this is the shape of the question, not an approved answer. When Core
/// publishes a Business contract this protocol is replaced by it, and only the adapter and
/// this file change.
@MainActor
protocol BusinessReferenceProviding: AnyObject {
    /// The principal's authorized Business set, in a stable display order.
    ///
    /// A client-supplied `business_id` SELECTS within this set; it never widens it. Core
    /// re-validates every value against the authenticated context, so this list is a
    /// convenience for the person filling in the form and never an authorization decision.
    func authorizedBusinesses() async throws -> [BusinessReference]
}
