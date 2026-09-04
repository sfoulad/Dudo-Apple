import SwiftUI

/// One customer's full record — all fifteen contracted fields.
///
/// The listing deliberately withholds `address` and `notes`, so this screen calls
/// `customers.GetCustomer` for the whole record rather than decorating the row it came from.
/// That is the contract's shape, not an optimisation to remove later: reaching a customer's
/// address or notes is a separate disclosure under a separate permission, one record at a
/// time.
struct CustomerDetailView: View {
    let customerID: String
    @Bindable var model: CustomerDirectoryModel

    @State private var customer: Customer?
    @State private var loadFailure: CustomerDirectoryError?
    @State private var isLoading = false
    @State private var editing: Customer?
    @State private var moving: Customer?
    @State private var isConfirmingArchive = false

    var body: some View {
        Group {
            if let customer {
                record(customer)
            } else if let loadFailure {
                failure(loadFailure)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(customer?.displayName ?? "Customer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task(id: customerID) { await load() }
        .sheet(item: $editing) { subject in
            CustomerFormView(mode: .edit(subject), model: model) { updated in
                customer = updated
            }
        }
        .sheet(item: $moving) { subject in
            MoveCustomerSheet(customer: subject, model: model) { moved in
                customer = moved
            }
        }
        .confirmationDialog(
            "Archive this customer?",
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button("Archive") {
                Task {
                    if let updated = await model.archive(customerID: customerID) {
                        customer = updated
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The truth about archiving, said where the decision is made. Archiving is not a
            // delete and starts no countdown; the record is kept indefinitely and can be
            // restored at any time.
            Text("The record is withdrawn from everyday lists and searches. Nothing is deleted — it is kept indefinitely and you can restore it at any time.")
        }
    }

    // MARK: - Record

    private func record(_ customer: Customer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DudoStyle.Space.section) {
                header(customer)
                lifecycleNotice(customer)

                card("Contact", systemImage: "envelope") {
                    emailRow(customer)
                    Divider()
                    phoneRow(customer)
                }

                card("Location", systemImage: "mappin.and.ellipse") {
                    CustomerFieldRow(
                        label: "Country",
                        value: customer.country.map { code in
                            let name = CustomerFieldRules.countryName(for: code)
                            return name == code ? code : "\(name) (\(code))"
                        },
                        systemImage: "globe"
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Address",
                        value: customer.address,
                        systemImage: "building",
                        allowsMultipleLines: true
                    )
                }

                card("Notes", systemImage: "note.text") {
                    CustomerFieldRow(
                        label: "Internal notes",
                        value: customer.notes,
                        allowsMultipleLines: true
                    )
                }

                card("Record", systemImage: "clock.arrow.circlepath") {
                    CustomerFieldRow(
                        label: "Business",
                        value: model.businessLabel(for: customer.businessID),
                        systemImage: "briefcase"
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Status",
                        value: customer.status.label,
                        systemImage: customer.status.symbolName
                    )
                    if let scheduled = customer.deletionScheduledAt {
                        Divider()
                        CustomerFieldRow(
                            label: "Data permanently deleted on",
                            value: scheduled.dudoLongForm,
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    }
                    Divider()
                    CustomerFieldRow(
                        label: "Created",
                        value: customer.createdAt.dudoLongForm,
                        systemImage: "plus.circle"
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Created by",
                        value: customer.createdByPrincipalID,
                        systemImage: "person.badge.key",
                        isMonospaced: true
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Last updated",
                        value: customer.updatedAt.dudoLongForm,
                        systemImage: "pencil.circle"
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Updated by",
                        value: customer.updatedByPrincipalID,
                        systemImage: "person.badge.key",
                        isMonospaced: true
                    )
                    Divider()
                    CustomerFieldRow(
                        label: "Customer ID",
                        value: customer.customerID,
                        systemImage: "number",
                        isMonospaced: true
                    )
                }
            }
            .padding(DudoStyle.Space.section)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ customer: Customer) -> some View {
        HStack(alignment: .top, spacing: DudoStyle.Space.card) {
            CustomerAvatar(name: customer.displayName, size: 60)
            VStack(alignment: .leading, spacing: 8) {
                Text(customer.displayName)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    CustomerTypeBadge(type: customer.customerType)
                    CustomerStatusBadge(status: customer.status, alwaysVisible: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DudoStyle.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DudoStyle.navy.opacity(0.06))
        )
    }

    /// Why some controls are not available, said plainly instead of leaving a person to guess
    /// at a greyed-out button.
    @ViewBuilder
    private func lifecycleNotice(_ customer: Customer) -> some View {
        switch customer.status {
        case .active:
            EmptyView()
        case .archived:
            notice(
                symbol: "archivebox",
                tint: .orange,
                title: "Archived",
                detail: "This customer is kept indefinitely and does not appear in everyday lists or searches. Restore it to make changes."
            )
        case .pendingDeletion:
            notice(
                symbol: "clock.badge.exclamationmark",
                tint: DudoStyle.scarlet,
                title: "Deletion requested",
                detail: customer.deletionScheduledAt.map {
                    "This customer's data is scheduled to be permanently deleted on \($0.dudoLongForm)."
                } ?? "This customer's data is scheduled to be permanently deleted."
            )
        }
    }

    private func notice(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DudoStyle.Space.row) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DudoStyle.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func emailRow(_ customer: Customer) -> some View {
        CustomerFieldRow(label: "Email", value: customer.email, systemImage: "envelope")
            .contextMenu {
                if let email = customer.email {
                    Button("Copy", systemImage: "doc.on.doc") { copy(email) }
                    if let url = mailURL(for: email) {
                        Link(destination: url) { Label("Compose Email", systemImage: "square.and.pencil") }
                    }
                }
            }
    }

    /// Phone is shown and copyable but is deliberately **not** a `tel:` link.
    ///
    /// The contract records the number as the tenant typed it, does not require E.164, and
    /// states outright that the value is not dial-safe. Offering a dial button would be this
    /// client asserting something about the data that the contract refuses to assert.
    private func phoneRow(_ customer: Customer) -> some View {
        CustomerFieldRow(label: "Phone", value: customer.phone, systemImage: "phone")
            .contextMenu {
                if let phone = customer.phone {
                    Button("Copy", systemImage: "doc.on.doc") { copy(phone) }
                }
            }
    }

    private func card(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(DudoStyle.Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
        }
    }

    private func failure(_ error: CustomerDirectoryError) -> some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Something went wrong", systemImage: error.symbolName)
        } description: {
            Text(error.recoverySuggestion ?? "This record could not be loaded.")
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let customer {
                    // Only an active customer may be edited. Archived and pending-deletion
                    // records are refused by the server, so the control is not offered —
                    // and the server would refuse it anyway if it were.
                    Button("Edit Details", systemImage: "pencil") { editing = customer }
                        .disabled(customer.status != .active)

                    switch customer.status {
                    case .active:
                        Button("Archive", systemImage: "archivebox") { isConfirmingArchive = true }
                    case .archived:
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            Task {
                                if let updated = await model.restore(customerID: customerID) {
                                    self.customer = updated
                                }
                            }
                        }
                    case .pendingDeletion:
                        EmptyView()
                    }

                    // Moving an archived customer is allowed; moving one under a deletion
                    // order is not.
                    Button("Move to Another Business…", systemImage: "arrow.left.arrow.right") {
                        moving = customer
                    }
                    .disabled(customer.status == .pendingDeletion)

                    Divider()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(customer == nil || model.isMutating)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        loadFailure = nil
        do {
            customer = try await model.customer(withID: customerID)
        } catch {
            customer = nil
            loadFailure = error.asCustomerDirectoryError
        }
    }

    // MARK: - Helpers

    private func mailURL(for email: String) -> URL? {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "mailto:\(encoded)")
    }

    private func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

/// What the detail column shows before a customer is chosen. Only ever seen on iPad and on the
/// Mac, where two columns exist at once.
struct CustomerDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            ContentUnavailableView(
                "Select a customer",
                systemImage: "person.crop.rectangle.stack",
                description: Text("Choose someone from the directory to see their full record.")
            )
            Text(DudoBuild.label)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
