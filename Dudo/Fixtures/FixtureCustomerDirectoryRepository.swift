import Foundation

/// An in-memory Customer Directory that behaves the way the contract says the server will.
///
/// WHY THIS EXISTS. There is no Dudo server. Nothing authenticates, nothing is deployed, and
/// this app makes no request of any kind — no URLSession, no socket, no third party. So that
/// the interface can nevertheless be built, reviewed and used, this type plays the part of
/// Core: it holds records in memory and applies the contract's ordering, search semantics,
/// pagination, field rules and state machine as written.
///
/// WHAT IT IS NOT. It is not Core, and it decides nothing Core decides. In particular it
/// performs **no authorization**: there is no principal, no Organization and no authorized
/// Business set to evaluate against. Every rule it does apply is a *shape* or a *state*
/// rule — the kind the client would see the effect of anyway. Tenant isolation, permission
/// evaluation and the not_found/forbidden distinction are Core's, they are deliberately
/// absent here, and their absence must never be read as this client having been shown to
/// handle them.
///
/// Replace it with a transport-backed conformer and no view changes.
@Observable
final class FixtureCustomerDirectoryRepository: CustomerDirectoryRepository, BusinessReferenceProviding {

    /// The records, held in the order they were seeded. Ordering for display is applied at
    /// read time by the contract's rule, never by insertion order.
    private var records: [Customer]
    private let businesses: [BusinessReference]

    /// Deliberate latency, so that loading, paging and in-flight states are visible and can
    /// be designed against rather than discovered when a real network arrives.
    private let readDelay = Duration.milliseconds(320)
    private let writeDelay = Duration.milliseconds(420)

    init(
        records: [Customer] = FixtureCustomerSeed.records(),
        businesses: [BusinessReference] = FixtureCustomerSeed.businesses
    ) {
        self.records = records
        self.businesses = businesses
    }

    // MARK: - BusinessReferenceProviding (placeholder — see BusinessReference.swift)

    func authorizedBusinesses() async throws -> [BusinessReference] {
        businesses
    }

    // MARK: - customers.CreateCustomer

    func createCustomer(_ input: CreateCustomerInput) async throws -> Customer {
        try await Task.sleep(for: writeDelay)

        var issues: [FieldIssue] = []
        if let issue = CustomerFieldRules.validateDisplayName(input.displayName) { issues.append(issue) }
        issues.append(contentsOf: optionalFieldIssues(
            email: input.email, phone: input.phone,
            country: input.country, address: input.address, notes: input.notes
        ))
        guard issues.isEmpty else { throw CustomerDirectoryError.invalidArgument(details: issues) }

        // A business_id that is not a Business of this Organization is not_found, identically
        // to one that exists nowhere. The fixture has one Organization, so "unknown to the
        // fixture" is the only case it can represent.
        guard businesses.contains(where: { $0.id == input.businessID }) else {
            throw CustomerDirectoryError.notFound
        }

        let now = Date()
        let customer = Customer(
            customerID: Self.freshCustomerID(),
            businessID: input.businessID,
            displayName: input.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerType: input.customerType,
            email: CustomerFieldRules.optionalValue(input.email ?? ""),
            phone: CustomerFieldRules.optionalValue(input.phone ?? ""),
            country: CustomerFieldRules.optionalValue(input.country ?? ""),
            address: CustomerFieldRules.optionalValue(input.address ?? ""),
            notes: CustomerFieldRules.optionalValue(input.notes ?? ""),
            // Status is never accepted on create. A new customer starts active.
            status: .active,
            deletionScheduledAt: nil,
            createdAt: now,
            createdByPrincipalID: FixtureCustomerSeed.principalID,
            updatedAt: now,
            updatedByPrincipalID: FixtureCustomerSeed.principalID
        )
        records.append(customer)
        return customer
    }

    // MARK: - customers.GetCustomer

    func getCustomer(customerID: String) async throws -> Customer {
        try await Task.sleep(for: readDelay)
        guard let customer = records.first(where: { $0.customerID == customerID }) else {
            throw CustomerDirectoryError.notFound
        }
        // Archived and pending-deletion records remain readable by identifier. They are only
        // withheld from the default listing.
        return customer
    }

    // MARK: - customers.ListCustomers

    func listCustomers(_ input: ListCustomersInput) async throws -> CustomerPage {
        try await Task.sleep(for: readDelay)
        try validatePageSize(input.pageSize)

        let position = try resolveCursor(
            input.cursor,
            pageSize: input.pageSize,
            status: input.status,
            businessID: input.businessID,
            query: nil
        )

        let candidates = orderedCandidates(status: input.status, businessID: input.businessID)
        return page(from: candidates, at: position, input.pageSize, input.status, input.businessID, nil)
    }

    // MARK: - customers.SearchCustomers

    func searchCustomers(_ input: SearchCustomersInput) async throws -> CustomerPage {
        try await Task.sleep(for: readDelay)
        try validatePageSize(input.pageSize)

        let trimmed = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CustomerFieldRules.queryMinLength,
              trimmed.count <= CustomerFieldRules.queryMaxLength
        else {
            throw CustomerDirectoryError.invalidArgument(
                details: [FieldIssue(field: "query", issue: "out_of_range")]
            )
        }

        let position = try resolveCursor(
            input.cursor,
            pageSize: input.pageSize,
            status: input.status,
            businessID: input.businessID,
            query: trimmed
        )

        // The bound is applied to the CANDIDATE SET before matching, never to the results
        // after it.
        let candidates = orderedCandidates(status: input.status, businessID: input.businessID)
            .filter { Self.matches(query: trimmed, customer: $0) }
        return page(from: candidates, at: position, input.pageSize, input.status, input.businessID, trimmed)
    }

    // MARK: - customers.UpdateCustomer

    func updateCustomer(_ input: UpdateCustomerInput) async throws -> Customer {
        try await Task.sleep(for: writeDelay)

        // minProperties: 2. An update that changes nothing still writes an audit record and
        // moves updated_at, so it is refused rather than accepted as a no-op.
        guard !input.carriesNoChange else {
            throw CustomerDirectoryError.invalidArgument(
                details: [FieldIssue(field: "customer_id", issue: "no_fields_to_update")]
            )
        }

        var issues: [FieldIssue] = []
        if let name = input.displayName, let issue = CustomerFieldRules.validateDisplayName(name) {
            issues.append(issue)
        }
        issues.append(contentsOf: optionalFieldIssues(
            email: value(of: input.email), phone: value(of: input.phone),
            country: value(of: input.country), address: value(of: input.address),
            notes: value(of: input.notes)
        ))
        guard issues.isEmpty else { throw CustomerDirectoryError.invalidArgument(details: issues) }

        let index = try indexOf(input.customerID)
        // Only an active customer may be edited. A record withdrawn from use that can still be
        // quietly changed is neither withdrawn nor a record.
        guard records[index].status == .active else {
            throw CustomerDirectoryError.failedPrecondition
        }

        let existing = records[index]
        let updated = Customer(
            customerID: existing.customerID,
            businessID: existing.businessID,
            displayName: (input.displayName ?? existing.displayName)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            customerType: input.customerType ?? existing.customerType,
            email: input.email.apply(to: existing.email),
            phone: input.phone.apply(to: existing.phone),
            country: input.country.apply(to: existing.country),
            address: input.address.apply(to: existing.address),
            notes: input.notes.apply(to: existing.notes),
            status: existing.status,
            deletionScheduledAt: existing.deletionScheduledAt,
            createdAt: existing.createdAt,
            createdByPrincipalID: existing.createdByPrincipalID,
            updatedAt: Date(),
            updatedByPrincipalID: FixtureCustomerSeed.principalID
        )
        records[index] = updated
        return updated
    }

    // MARK: - customers.ArchiveCustomer

    func archiveCustomer(customerID: String) async throws -> Customer {
        try await Task.sleep(for: writeDelay)
        let index = try indexOf(customerID)
        // Transitions are strict, not idempotent. Archiving an already-archived customer is
        // failed_precondition: the permissive alternative writes an audit record saying a
        // customer was archived when nothing changed.
        guard records[index].status == .active else {
            throw CustomerDirectoryError.failedPrecondition
        }
        records[index] = records[index].transitioned(to: .archived)
        return records[index]
    }

    // MARK: - customers.RestoreCustomer

    func restoreCustomer(customerID: String) async throws -> Customer {
        try await Task.sleep(for: writeDelay)
        let index = try indexOf(customerID)
        // Refuses pending_deletion, and that is not an inconsistency: countermanding a
        // destruction order is RestoreDeletedCustomer, at organization scope.
        guard records[index].status == .archived else {
            throw CustomerDirectoryError.failedPrecondition
        }
        records[index] = records[index].transitioned(to: .active)
        return records[index]
    }

    // MARK: - customers.MoveCustomerToBusiness

    func moveCustomerToBusiness(customerID: String, businessID: String) async throws -> Customer {
        try await Task.sleep(for: writeDelay)

        guard businesses.contains(where: { $0.id == businessID }) else {
            throw CustomerDirectoryError.notFound
        }
        let index = try indexOf(customerID)
        // Moving an archived customer is allowed; moving a pending-deletion one is not.
        guard records[index].status != .pendingDeletion else {
            throw CustomerDirectoryError.failedPrecondition
        }
        // A move that moves nothing still writes an audit record saying a customer changed
        // Business, so the destination may not be the Business it is already in.
        guard records[index].businessID != businessID else {
            throw CustomerDirectoryError.failedPrecondition
        }
        records[index] = records[index].moved(to: businessID)
        return records[index]
    }

    // MARK: - Ordering and paging

    /// The contract's fixed, total order: normalised `display_name` ascending **by Unicode
    /// code point**, then `customer_id` ascending as the tiebreaker. A total order is what
    /// makes a cursor correct; ordering on a non-unique field alone silently duplicates and
    /// skips rows across pages.
    ///
    /// Code-point order is not locale-correct for Arabic or for accented Latin scripts. That
    /// is a known, recorded limitation of the contract (open question CD-6), and this client
    /// reproduces it rather than quietly sorting more cleverly than the server will.
    private func orderedCandidates(status: CustomerStatusFilter, businessID: String?) -> [Customer] {
        records
            .filter { status.matches($0.status) }
            .filter { businessID == nil || $0.businessID == businessID }
            .sorted { left, right in
                let a = Self.normalise(left.displayName)
                let b = Self.normalise(right.displayName)
                if a != b { return Self.codePointPrecedes(a, b) }
                return Self.codePointPrecedes(left.customerID, right.customerID)
            }
    }

    private func page(
        from candidates: [Customer],
        at offset: Int,
        _ pageSize: Int,
        _ status: CustomerStatusFilter,
        _ businessID: String?,
        _ query: String?
    ) -> CustomerPage {
        guard offset < candidates.count else { return .empty }
        let end = min(offset + pageSize, candidates.count)
        let slice = candidates[offset..<end].map(\.summary)
        let next: String? = end < candidates.count
            ? FixtureCursor(offset: end, pageSize: pageSize, status: status,
                            businessID: businessID, query: query).encoded
            : nil
        return CustomerPage(data: slice, nextCursor: next)
    }

    private func validatePageSize(_ size: Int) throws {
        guard size >= 1, size <= CustomerPagination.maximumPageSize else {
            throw CustomerDirectoryError.invalidArgument(
                details: [FieldIssue(field: "page_size", issue: "out_of_range")]
            )
        }
    }

    /// A cursor bound to different filter parameters is rejected, exactly as a malformed one
    /// is, and with the same error — a page 2 under different filters is not page 2.
    private func resolveCursor(
        _ cursor: String?,
        pageSize: Int,
        status: CustomerStatusFilter,
        businessID: String?,
        query: String?
    ) throws -> Int {
        guard let cursor else { return 0 }
        guard let decoded = FixtureCursor(encoded: cursor),
              decoded.pageSize == pageSize,
              decoded.status == status,
              decoded.businessID == businessID,
              decoded.query == query
        else {
            throw CustomerDirectoryError.invalidArgument(
                details: [FieldIssue(field: "cursor", issue: "not_usable")]
            )
        }
        return decoded.offset
    }

    // MARK: - Matching

    /// Normalisation applied identically to the query and to the stored value: Unicode NFC,
    /// simple case folding, trimmed, internal whitespace collapsed.
    ///
    /// **No accent folding and no transliteration**, deliberately: `Muller` does not match
    /// `Müller`. That is a real limitation for Arabic-, French- and German-language
    /// directories, it is stated in the contract rather than implied, and this client must
    /// not quietly fix it — doing so would make the Apple client return a different result
    /// set from the web client for the same query.
    static func normalise(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// A customer matches if **any** of the three field rules matches. Notes and address are
    /// never consulted.
    static func matches(query: String, customer: Customer) -> Bool {
        let normalisedQuery = normalise(query)
        guard !normalisedQuery.isEmpty else { return false }

        // display_name: every term must be a prefix of at least one token. AND across terms.
        let terms = normalisedQuery.split(separator: " ")
        let tokens = normalise(customer.displayName).split(separator: " ")
        if !terms.isEmpty, terms.allSatisfy({ term in tokens.contains { $0.hasPrefix(term) } }) {
            return true
        }

        // email: the normalised query is a prefix of the normalised email.
        if let email = customer.email, normalise(email).hasPrefix(normalisedQuery) {
            return true
        }

        // phone: digits only, suffix match, and the rule participates only at four digits or
        // more — below that it would match most of a directory and charge a scan to say so.
        let queryDigits = query.filter(\.isNumber)
        if queryDigits.count >= 4, let phone = customer.phone {
            let storedDigits = phone.filter(\.isNumber)
            if !storedDigits.isEmpty, storedDigits.hasSuffix(queryDigits) { return true }
        }

        return false
    }

    /// Lexicographic comparison by Unicode scalar value. `String`'s own `<` compares by
    /// canonical equivalence rather than raw code points, which is close but not the rule the
    /// contract states.
    static func codePointPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        var left = lhs.unicodeScalars.makeIterator()
        var right = rhs.unicodeScalars.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case (let a?, let b?):
                if a.value != b.value { return a.value < b.value }
            }
        }
    }

    // MARK: - Helpers

    private func indexOf(_ customerID: String) throws -> Int {
        guard let index = records.firstIndex(where: { $0.customerID == customerID }) else {
            throw CustomerDirectoryError.notFound
        }
        return index
    }

    private func value(of update: FieldUpdate<String>) -> String? {
        if case .set(let value) = update { return value }
        return nil
    }

    private func optionalFieldIssues(
        email: String?, phone: String?, country: String?, address: String?, notes: String?
    ) -> [FieldIssue] {
        var issues: [FieldIssue] = []
        if let email, let issue = CustomerFieldRules.validateEmail(email) { issues.append(issue) }
        if let phone, let issue = CustomerFieldRules.validatePhone(phone) { issues.append(issue) }
        if let country, let issue = CustomerFieldRules.validateCountry(country) { issues.append(issue) }
        if let address, let issue = CustomerFieldRules.validateAddress(address) { issues.append(issue) }
        if let notes, let issue = CustomerFieldRules.validateNotes(notes) { issues.append(issue) }
        return issues
    }

    /// Opaque and non-sequential, matching the contract's identifier pattern. The real
    /// generation scheme is a Core decision and is deliberately not fixed by any client.
    private static func freshCustomerID() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return "cus_" + String((0..<14).map { _ in alphabet.randomElement()! })
    }
}

// MARK: - Record transitions

private extension Customer {
    /// The lifecycle move, with the metadata the contract says carries it. There is no
    /// `archived_at` or `archived_by` field: `updated_at` and `updated_by_principal_id` carry
    /// it, and the audit record carries the rest.
    func transitioned(to newStatus: CustomerStatus) -> Customer {
        Customer(
            customerID: customerID, businessID: businessID, displayName: displayName,
            customerType: customerType, email: email, phone: phone, country: country,
            address: address, notes: notes, status: newStatus,
            // Non-null if and only if pending_deletion. Archiving sets no deadline.
            deletionScheduledAt: newStatus == .pendingDeletion ? deletionScheduledAt : nil,
            createdAt: createdAt, createdByPrincipalID: createdByPrincipalID,
            updatedAt: Date(), updatedByPrincipalID: FixtureCustomerSeed.principalID
        )
    }

    /// A move is not a lifecycle transition: status is unchanged.
    func moved(to newBusinessID: String) -> Customer {
        Customer(
            customerID: customerID, businessID: newBusinessID, displayName: displayName,
            customerType: customerType, email: email, phone: phone, country: country,
            address: address, notes: notes, status: status,
            deletionScheduledAt: deletionScheduledAt,
            createdAt: createdAt, createdByPrincipalID: createdByPrincipalID,
            updatedAt: Date(), updatedByPrincipalID: FixtureCustomerSeed.principalID
        )
    }
}

// MARK: - Cursor

/// The fixture's continuation token.
///
/// A cursor is issued by the server and is OPAQUE to the client: nothing outside this file
/// parses, constructs or reasons about one. It is encoded rather than left as a plain integer
/// so that no view can be written against its contents by accident.
private struct FixtureCursor {
    var offset: Int
    var pageSize: Int
    var status: CustomerStatusFilter
    var businessID: String?
    var query: String?

    var encoded: String {
        let payload = [
            String(offset), String(pageSize), status.rawValue,
            businessID ?? "", query ?? ""
        ].joined(separator: "\u{1}")
        return Data(payload.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init(offset: Int, pageSize: Int, status: CustomerStatusFilter, businessID: String?, query: String?) {
        self.offset = offset
        self.pageSize = pageSize
        self.status = status
        self.businessID = businessID
        self.query = query
    }

    init?(encoded: String) {
        var padded = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded),
              let payload = String(data: data, encoding: .utf8)
        else { return nil }

        let parts = payload.components(separatedBy: "\u{1}")
        guard parts.count == 5,
              let offset = Int(parts[0]),
              let pageSize = Int(parts[1]),
              let status = CustomerStatusFilter(rawValue: parts[2])
        else { return nil }

        self.offset = offset
        self.pageSize = pageSize
        self.status = status
        self.businessID = parts[3].isEmpty ? nil : parts[3]
        self.query = parts[4].isEmpty ? nil : parts[4]
    }
}
