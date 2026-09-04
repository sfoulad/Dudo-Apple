import SwiftUI

/// The main screen: the directory itself.
///
/// It is one view used in two navigation shapes. On iPhone it drives a `NavigationStack` and
/// each row is a link. On iPad and on the Mac it is the sidebar of a `NavigationSplitView` and
/// each row is a selection. Those are genuinely different interactions — a push versus a
/// selection that persists while you work in the other column — and pretending otherwise is
/// what makes an iPad app feel like a stretched phone app.
struct CustomerListView: View {
    @Bindable var model: CustomerDirectoryModel
    /// True in a split view, where a row selects rather than pushes.
    let usesSelection: Bool

    var body: some View {
        content
            .navigationTitle("Customers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .searchable(text: $model.searchText, prompt: "Name, email or phone")
            .refreshable { await model.refresh() }
            .toolbar { toolbarContent }
            .task(id: model.queryKey) { await model.load() }
            .task { await model.loadBusinesses() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            loadingList
        case .failed(let error):
            failure(error)
        case .loaded:
            if model.rows.isEmpty {
                emptyState
            } else {
                populatedList
            }
        }
    }

    private var loadingList: some View {
        List(0..<8, id: \.self) { index in
            CustomerRowPlaceholder(widthSeed: index)
                .listRowSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading customers")
    }

    @ViewBuilder
    private var populatedList: some View {
        if usesSelection {
            List(selection: $model.selection) {
                searchScopeNote
                ForEach(model.rows) { row in
                    rowView(row)
                        .tag(row.id)
                }
                paginationFooter
            }
            .listStyle(.inset)
        } else {
            List {
                searchScopeNote
                ForEach(model.rows) { row in
                    NavigationLink(value: row.id) {
                        rowView(row)
                    }
                }
                paginationFooter
            }
            .listStyle(.plain)
        }
    }

    private func rowView(_ row: CustomerSummary) -> some View {
        CustomerRowView(
            summary: row,
            businessLabel: model.hasResolvedBusinessNames
                ? model.businessLabel(for: row.businessID)
                : nil
        )
        .contextMenu { rowActions(row) }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            lifecycleAction(row)
        }
        #endif
    }

    /// Archive and restore, offered where the state machine allows them and nowhere else.
    ///
    /// There is no delete control here, and there will not be one until the platform has a
    /// confirmation mechanism for it. `DeleteCustomer` is contracted and deliberately not
    /// built; an interface offering an action the platform refuses is worse than one that
    /// omits it.
    @ViewBuilder
    private func rowActions(_ row: CustomerSummary) -> some View {
        if let email = row.email {
            Button("Copy Email Address", systemImage: "envelope") {
                copyToPasteboard(email)
            }
        }
        if let phone = row.phone {
            Button("Copy Phone Number", systemImage: "phone") {
                copyToPasteboard(phone)
            }
        }
        Divider()
        switch row.status {
        case .active:
            Button("Archive", systemImage: "archivebox") {
                Task { await model.archive(customerID: row.id) }
            }
        case .archived:
            Button("Restore", systemImage: "arrow.uturn.backward") {
                Task { await model.restore(customerID: row.id) }
            }
        case .pendingDeletion:
            // Reachable only through DeleteCustomer, which this slice does not build. The
            // client still renders the state rather than crashing on a status it cannot cause.
            EmptyView()
        }
    }

    @ViewBuilder
    private func lifecycleAction(_ row: CustomerSummary) -> some View {
        switch row.status {
        case .active:
            Button {
                Task { await model.archive(customerID: row.id) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        case .archived:
            Button {
                Task { await model.restore(customerID: row.id) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        case .pendingDeletion:
            EmptyView()
        }
    }

    /// Told once, in place, rather than in a help page nobody opens: the search field does not
    /// look at notes or addresses, and it needs two characters.
    @ViewBuilder
    private var searchScopeNote: some View {
        if model.hasIncompleteSearchTerm {
            Label("Enter at least two characters to search.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if model.hasMorePages {
            HStack(spacing: 8) {
                Spacer()
                ProgressView().controlSize(.small)
                Text("Loading more customers…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .task(id: model.rows.count) {
                await model.loadNextPage()
            }
        }
    }

    // MARK: - Empty and failed

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearching {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("Dudo searches names, email addresses and phone numbers. Notes and addresses are never searched.")
            } actions: {
                Button("Clear Search") { model.searchText = "" }
            }
        } else {
            switch model.statusFilter {
            case .archived:
                ContentUnavailableView(
                    "No archived customers",
                    systemImage: "archivebox",
                    description: Text("Archiving withdraws a customer from everyday use. Nothing is deleted, and archived records are kept indefinitely.")
                )
            case .pendingDeletion:
                ContentUnavailableView(
                    "Nothing pending deletion",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Permanent deletion is not available in this release.")
                )
            case .active, .all:
                ContentUnavailableView {
                    Label("No customers yet", systemImage: "person.2")
                } description: {
                    Text("Add the people and companies you do business with, and they will appear here.")
                } actions: {
                    Button("Add Customer") { model.isPresentingCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func failure(_ error: CustomerDirectoryError) -> some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Something went wrong", systemImage: error.symbolName)
        } description: {
            Text(error.recoverySuggestion ?? "The directory could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await model.load(debounced: false) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Customer", systemImage: "plus") {
                model.isPresentingCreate = true
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Show", selection: $model.statusFilter) {
                    Text("Active").tag(CustomerStatusFilter.active)
                    Text("Archived").tag(CustomerStatusFilter.archived)
                    Text("All").tag(CustomerStatusFilter.all)
                }
                .pickerStyle(.inline)

                Divider()

                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()
                Text(DudoBuild.label)
            } label: {
                Label("Filter", systemImage: filterSymbol)
            }
        }
    }

    private var filterSymbol: String {
        model.statusFilter == .contractDefault
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    // MARK: - Pasteboard

    private func copyToPasteboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}
