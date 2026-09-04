import Foundation
import Observation

/// The state behind the Customer Directory: one page of rows, the filter and search term that
/// produced them, and the outcome of the last thing the person did.
///
/// It calls the eight in-scope Actions through `CustomerDirectoryRepository` and holds no
/// business rules of its own. Every decision that matters — whether a customer may be
/// archived, whether an edit is allowed, which records the caller may see — is the server's,
/// and this type only reflects the answer. Where it appears to decide something (disabling a
/// button, hiding a control) that is presentation: the same request would still be refused if
/// it were made.
@MainActor
@Observable
final class CustomerDirectoryModel {

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(CustomerDirectoryError)
    }

    // MARK: Dependencies

    private let repository: any CustomerDirectoryRepository
    private let businessProvider: any BusinessReferenceProviding

    init(
        repository: any CustomerDirectoryRepository,
        businessProvider: any BusinessReferenceProviding
    ) {
        self.repository = repository
        self.businessProvider = businessProvider
    }

    // MARK: Query

    /// The lifecycle filter. Defaults to `active`, as the contract does: archiving a customer
    /// means withdrawing it from normal use, and a default that kept showing archived records
    /// would defeat the operation the user just performed.
    var statusFilter: CustomerStatusFilter = .contractDefault
    /// What is typed in the search field. Not necessarily what has been searched for — below
    /// two characters nothing is sent.
    var searchText: String = ""

    /// The two inputs that together decide which request is made. One key so that a change to
    /// either one replaces the in-flight request instead of racing it.
    struct QueryKey: Hashable {
        var status: CustomerStatusFilter
        var text: String
    }

    var queryKey: QueryKey { QueryKey(status: statusFilter, text: searchText) }

    /// Whether the current text will actually be searched for. Below the contract's two-
    /// character floor the directory keeps showing the unsearched listing, and the interface
    /// says so rather than appearing to have found nothing.
    var isSearching: Bool { CustomerFieldRules.normalisedQueryIfSendable(searchText) != nil }

    var hasIncompleteSearchTerm: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    // MARK: Results

    private(set) var rows: [CustomerSummary] = []
    private(set) var nextCursor: String?
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var businesses: [BusinessReference] = []

    var hasMorePages: Bool { nextCursor != nil }

    // MARK: Interface state

    var selection: CustomerSummary.ID?
    var isPresentingCreate = false
    /// The last failed Action, surfaced as an alert. Cleared when the alert is dismissed.
    var actionError: CustomerDirectoryError?
    /// A short confirmation of what just happened — the one place the app says "done".
    var lastActionMessage: String?
    /// True while a mutation is in flight, so a screen can disable its own controls without
    /// each one tracking that separately.
    private(set) var isMutating = false

    // MARK: - Loading

    /// Load the first page for the current filter and search term.
    ///
    /// The short wait is a debounce: it is what stops every keystroke becoming a request. The
    /// enclosing `task(id:)` cancels this call when the query changes again, so a superseded
    /// search never lands after the one that replaced it.
    func load(debounced: Bool = true) async {
        if debounced {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
        }

        phase = .loading
        do {
            let page = try await firstPage()
            guard !Task.isCancelled else { return }
            rows = page.data
            nextCursor = page.nextCursor
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            rows = []
            nextCursor = nil
            phase = .failed(error.asCustomerDirectoryError)
        }
    }

    /// Re-fetch the first page without emptying the list. Used by pull-to-refresh, by ⌘R, and
    /// after every successful mutation — a mutation can move a record out of the current
    /// filter, and a list that kept showing it would be lying about the record's state.
    func refresh() async {
        do {
            let page = try await firstPage()
            rows = page.data
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            // A failed refresh leaves the rows that are already on screen. They are stale, not
            // wrong, and throwing them away would be a worse answer than keeping them.
            actionError = error.asCustomerDirectoryError
        }
    }

    /// Fetch the next page. Cursor pagination only — there is no page number and no total, so
    /// the only thing the client knows is whether another page exists.
    func loadNextPage() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await nextPage(cursor: cursor)
            // Guard against a filter change that landed while this was in flight.
            guard nextCursor == cursor else { return }
            rows.append(contentsOf: page.data)
            nextCursor = page.nextCursor
        } catch {
            actionError = error.asCustomerDirectoryError
        }
    }

    func loadBusinesses() async {
        businesses = (try? await businessProvider.authorizedBusinesses()) ?? []
    }

    private func firstPage() async throws -> CustomerPage {
        if let query = CustomerFieldRules.normalisedQueryIfSendable(searchText) {
            return try await repository.searchCustomers(
                SearchCustomersInput(query: query, status: statusFilter)
            )
        }
        return try await repository.listCustomers(
            ListCustomersInput(status: statusFilter)
        )
    }

    private func nextPage(cursor: String) async throws -> CustomerPage {
        if let query = CustomerFieldRules.normalisedQueryIfSendable(searchText) {
            return try await repository.searchCustomers(
                SearchCustomersInput(query: query, status: statusFilter, cursor: cursor)
            )
        }
        return try await repository.listCustomers(
            ListCustomersInput(status: statusFilter, cursor: cursor)
        )
    }

    // A SELECTED CUSTOMER IS DELIBERATELY NOT CLEARED WHEN IT LEAVES THE LISTING.
    //
    // Archiving is the case that matters: the record drops out of the default filter the
    // instant the Action succeeds. Clearing the selection would close the record the person
    // was working on at the exact moment they acted on it, leaving no way back except to
    // change the filter and find it again. An archived customer remains readable by
    // identifier, so the record stays on screen, shows its new state, and offers Restore.

    // MARK: - Actions

    /// `customers.CreateCustomer`
    func create(_ input: CreateCustomerInput) async -> Customer? {
        await perform(successMessage: "Customer added.") {
            try await self.repository.createCustomer(input)
        }
    }

    /// `customers.UpdateCustomer`
    func update(_ input: UpdateCustomerInput) async -> Customer? {
        await perform(successMessage: "Changes saved.") {
            try await self.repository.updateCustomer(input)
        }
    }

    /// `customers.ArchiveCustomer` — withdraws the record from active use. It deletes nothing
    /// and starts no clock.
    @discardableResult
    func archive(customerID: String) async -> Customer? {
        await perform(successMessage: "Customer archived.") {
            try await self.repository.archiveCustomer(customerID: customerID)
        }
    }

    /// `customers.RestoreCustomer` — returns an archived record to active use.
    @discardableResult
    func restore(customerID: String) async -> Customer? {
        await perform(successMessage: "Customer restored.") {
            try await self.repository.restoreCustomer(customerID: customerID)
        }
    }

    /// `customers.MoveCustomerToBusiness`
    func move(customerID: String, to businessID: String) async -> Customer? {
        await perform(successMessage: "Customer moved.") {
            try await self.repository.moveCustomerToBusiness(
                customerID: customerID, businessID: businessID
            )
        }
    }

    /// `customers.GetCustomer` — the full record, for the detail screen.
    func customer(withID customerID: String) async throws -> Customer {
        try await repository.getCustomer(customerID: customerID)
    }

    /// Runs one Action, refreshes the listing behind it, and reports the outcome once.
    ///
    /// The refresh is not optional: archive, restore and move all change whether a record
    /// belongs in the current filter, and a create adds one that may sort anywhere in the
    /// order. Re-asking the server is the only way the client can be right about that,
    /// because it does not know the ordering rule's outcome for a name it has not seen.
    private func perform(
        successMessage: String,
        _ action: @escaping () async throws -> Customer
    ) async -> Customer? {
        isMutating = true
        defer { isMutating = false }
        do {
            let customer = try await action()
            await refresh()
            lastActionMessage = successMessage
            return customer
        } catch {
            actionError = error.asCustomerDirectoryError
            return nil
        }
    }

    /// Takes the field-level complaints from the last failure, if it had any, and clears it.
    ///
    /// A rejection that names fields belongs on those fields. Anything else stays in
    /// `actionError` for the directory's alert to show, because a form cannot fix a
    /// `forbidden` or an `unavailable`.
    func takeFieldIssues() -> [FieldIssue] {
        guard case .invalidArgument(let details)? = actionError else { return [] }
        actionError = nil
        return details
    }

    // MARK: - Business labels

    /// The Business a record belongs to, as a person should see it.
    ///
    /// Falls back to the raw identifier. That is the honest rendering: `business_id` is
    /// opaque, no published contract resolves one to a name, and a blank or an invented label
    /// would both be worse than showing what the record actually says. See
    /// `BusinessReference.swift`.
    func businessLabel(for businessID: String) -> String {
        businesses.first { $0.id == businessID }?.displayLabel ?? businessID
    }

    var hasResolvedBusinessNames: Bool { !businesses.isEmpty }
}

// MARK: - Build identity

enum DudoBuild {
    /// Version and build number, shown so a TestFlight tester can say which build they are on
    /// without being asked to find it in Settings.
    static var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
