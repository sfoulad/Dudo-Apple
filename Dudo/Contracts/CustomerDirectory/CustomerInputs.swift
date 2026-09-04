import Foundation

// MARK: - Customer Directory, contract v1 — request shapes
//
// Transcribed from customer-directory-v1.schema.json. Unknown fields are REJECTED by the
// server, not ignored, which is what makes `organization_id`, `status`, `customer_id` and
// `created_by_principal_id` unsettable rather than merely undocumented. None of them appear
// here, and none may be added.

/// The three-way distinction a partial update needs, made explicit in the type system.
///
///   - `.unchanged` — the field is ABSENT from the request; the server leaves it alone.
///   - `.set(v)`    — the field is PRESENT with a value; the server stores it.
///   - `.cleared`   — the field is PRESENT and null; the server clears it.
///
/// The contract states this as normative because "absent means clear" and "null means
/// unchanged" are both plausible readings, two clients would pick differently, and the
/// failure is silent data loss in a customer's records. Modelling it as an enum means this
/// client cannot express the ambiguity even by accident.
nonisolated enum FieldUpdate<Value: Sendable & Equatable>: Sendable, Equatable {
    case unchanged
    case set(Value)
    case cleared

    var isUnchanged: Bool {
        if case .unchanged = self { return true }
        return false
    }

    /// The value to store, for a repository that keeps records rather than JSON.
    /// Returns `current` when the field is absent from the request.
    func apply(to current: Value?) -> Value? {
        switch self {
        case .unchanged: return current
        case .set(let value): return value
        case .cleared: return nil
        }
    }
}

/// CreateCustomer input.
///
/// `businessID` is REQUIRED and is required rather than defaulted: a principal may be
/// authorized over several Businesses, so there is no single one the server can infer, and
/// inferring one from "the Business you were last looking at" would file a customer into the
/// wrong Business silently.
nonisolated struct CreateCustomerInput: Sendable, Equatable {
    var businessID: String
    var displayName: String
    var customerType: CustomerType
    var email: String?
    var phone: String?
    var country: String?
    var address: String?
    var notes: String?
}

/// UpdateCustomer input — a partial update.
///
/// `status` is not here: archiving is ArchiveCustomer. `businessID` is not here either, and
/// may not be added: moving a customer between Businesses is MoveCustomerToBusiness, with its
/// own permission and its own audit record.
nonisolated struct UpdateCustomerInput: Sendable, Equatable {
    var customerID: String
    /// Required on the record, so it is either present with a value or absent — never null.
    var displayName: String?
    /// Required on the record, so it is either present with a value or absent — never null.
    var customerType: CustomerType?
    var email: FieldUpdate<String> = .unchanged
    var phone: FieldUpdate<String> = .unchanged
    var country: FieldUpdate<String> = .unchanged
    var address: FieldUpdate<String> = .unchanged
    var notes: FieldUpdate<String> = .unchanged

    /// The schema's `minProperties: 2` — at least one field besides `customer_id`.
    ///
    /// An update that changes nothing still writes an audit record and moves `updated_at`,
    /// so it is rejected as `invalid_argument` rather than accepted as a no-op that pollutes
    /// the audit trail. The form disables Save in this state; the repository refuses it
    /// anyway, because UI-level prevention is presentation and never enforcement.
    var carriesNoChange: Bool {
        displayName == nil
            && customerType == nil
            && email.isUnchanged
            && phone.isUnchanged
            && country.isUnchanged
            && address.isUnchanged
            && notes.isUnchanged
    }
}

/// ListCustomers input. Every parameter is optional.
///
/// Omitting `businessID` does NOT mean "the whole Organization". It means every Business the
/// authenticated principal is authorized over, which for a business-scope principal is
/// exactly one.
nonisolated struct ListCustomersInput: Sendable, Equatable {
    var businessID: String?
    var status: CustomerStatusFilter = .contractDefault
    var pageSize: Int = CustomerPagination.defaultPageSize
    /// Opaque. The client never parses, constructs, edits or reasons about it.
    var cursor: String?
}

/// SearchCustomers input. Same paging and filtering as ListCustomers, plus a required query.
///
/// The set of searchable fields is fixed by the contract and is NOT selectable by the caller:
/// letting a caller choose the field would let it probe `notes`.
nonisolated struct SearchCustomersInput: Sendable, Equatable {
    /// Minimum two characters after trimming, maximum 128. `%` and `_` are literal
    /// characters — there is no wildcard, glob or regular-expression syntax.
    var query: String
    var businessID: String?
    var status: CustomerStatusFilter = .contractDefault
    var pageSize: Int = CustomerPagination.defaultPageSize
    var cursor: String?
}
