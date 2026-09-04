import SwiftUI

/// Add a customer, or change one.
///
/// The two are one screen because they collect the same fields, and two Actions because the
/// platform has two: `CreateCustomer` and `UpdateCustomer`. Nothing here decides which to
/// call based on the data — the caller says which it opened.
///
/// The field rules are the contract's, mirrored exactly. They are here so the form can say
/// what is wrong while a person is typing; they are not what keeps a bad value out of
/// storage. Core validates every one of them again, and its answer is the one that counts —
/// which is why a server rejection lands on the same fields as a local one.
struct CustomerFormView: View {
    enum Mode {
        case create
        case edit(Customer)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
    }

    let mode: Mode
    @Bindable var model: CustomerDirectoryModel
    var onSaved: (Customer) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var customerType: CustomerType = .company
    @State private var businessID = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var country = ""
    @State private var address = ""
    @State private var notes = ""

    /// Fields the person has touched. A form that shouts about an empty required field before
    /// anyone has typed in it is a form that is wrong more often than it is right.
    @State private var touched: Set<String> = []
    @State private var hasAttemptedSave = false
    /// Field problems the server reported. Shown in the same place as the local ones.
    @State private var serverIssues: [FieldIssue] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                contactSection
                locationSection
                notesSection
            }
            .formStyle(.grouped)
            .navigationTitle(mode.isCreate ? "New Customer" : "Edit Customer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(mode.isCreate ? "Add" : "Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear { prepare() }
        .onChange(of: model.businesses.count) { _, _ in
            if mode.isCreate, businessID.isEmpty {
                businessID = model.businesses.first?.id ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 560, minHeight: 560, idealHeight: 640)
        #endif
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            field("display_name", "Name") {
                TextField("Name", text: $displayName, prompt: Text("Full name or company name"))
                    .onChange(of: displayName) { _, _ in touched.insert("display_name") }
            }

            Picker("Type", selection: $customerType) {
                ForEach(CustomerType.allCases) { type in
                    Label(type.label, systemImage: type.symbolName).tag(type)
                }
            }

            if mode.isCreate {
                businessPicker
            }
        } header: {
            Text("Customer")
        } footer: {
            if mode.isCreate {
                // Required rather than defaulted, and the reason is worth stating: a principal
                // may be authorized over several Businesses, so there is no single one the
                // server can infer, and quietly picking one would file a customer into the
                // wrong Business without anyone noticing.
                Text("Every customer belongs to one business. This cannot be changed by editing later — moving a customer is a separate action.")
            }
        }
    }

    @ViewBuilder
    private var businessPicker: some View {
        if model.businesses.isEmpty {
            HStack {
                Text("Business")
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else {
            Picker("Business", selection: $businessID) {
                ForEach(model.businesses) { business in
                    Text(business.displayLabel).tag(business.id)
                }
            }
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            field("email", "Email address") {
                TextField("Email", text: $email, prompt: Text("Optional"))
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    #endif
                    .onChange(of: email) { _, _ in touched.insert("email") }
            }
            field("phone", "Phone number") {
                TextField("Phone", text: $phone, prompt: Text("Optional"))
                    #if os(iOS)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                    .onChange(of: phone) { _, _ in touched.insert("phone") }
            }
        }
    }

    private var locationSection: some View {
        Section {
            field("country", "Country") {
                HStack {
                    TextField("Country code", text: $country, prompt: Text("Optional, e.g. BH"))
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        #endif
                        .onChange(of: country) { _, newValue in
                            touched.insert("country")
                            let cleaned = String(newValue.prefix(2)).uppercased()
                            if cleaned != newValue { country = cleaned }
                        }
                    if let name = resolvedCountryName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            field("address", "Address") {
                TextField("Address", text: $address, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: address) { _, _ in touched.insert("address") }
            }
        } header: {
            Text("Location")
        } footer: {
            // Well-formedness only: no code list is validated against, so an unassigned but
            // well-formed code is accepted. The field is free text for that reason — a closed
            // picker here would reject values the web client accepts.
            Text("A two-letter ISO country code. The address is kept as a single free-text value.")
        }
    }

    private var notesSection: some View {
        Section {
            field("notes", "Internal notes") {
                TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(3...10)
                    .onChange(of: notes) { _, _ in touched.insert("notes") }
            }
        } header: {
            HStack {
                Text("Notes")
                Spacer()
                if !notes.isEmpty {
                    Text("\(notes.count) / \(CustomerFieldRules.notesMaxLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            notes.count > CustomerFieldRules.notesMaxLength ? DudoStyle.scarlet : .secondary
                        )
                }
            }
        } footer: {
            // Said in the interface because it changes what a person writes here: notes are
            // never searched, so a note is not a way to make a customer findable.
            Text("Notes are for your team only. They are never searched.")
        }
    }

    /// A labelled field plus whatever is currently wrong with it.
    ///
    /// The label is drawn above the field rather than passed to `TextField`, because a
    /// `TextField` given both a title and a prompt shows only the prompt on iOS — the label
    /// disappears and a person is left guessing which "Optional" is the phone number.
    @ViewBuilder
    private func field(
        _ name: String,
        _ label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
            if let issue = visibleIssue(for: name) {
                Label(issue.message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DudoStyle.scarlet)
                    .accessibilityLabel("Error: \(issue.message)")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Validation

    private var localIssues: [FieldIssue] {
        var issues: [FieldIssue] = []
        if let issue = CustomerFieldRules.validateDisplayName(displayName) { issues.append(issue) }
        if let issue = CustomerFieldRules.validateEmail(email) { issues.append(issue) }
        if let issue = CustomerFieldRules.validatePhone(phone) { issues.append(issue) }
        if let issue = CustomerFieldRules.validateCountry(country) { issues.append(issue) }
        if let issue = CustomerFieldRules.validateAddress(address) { issues.append(issue) }
        if let issue = CustomerFieldRules.validateNotes(notes) { issues.append(issue) }
        return issues
    }

    private func visibleIssue(for name: String) -> FieldIssue? {
        if let serverIssue = serverIssues.first(where: { $0.field == name }) { return serverIssue }
        guard touched.contains(name) || hasAttemptedSave else { return nil }
        return localIssues.first { $0.field == name }
    }

    private var resolvedCountryName: String? {
        guard CustomerFieldRules.validateCountry(country) == nil, !country.isEmpty else { return nil }
        let name = CustomerFieldRules.countryName(for: country)
        return name == country ? nil : name
    }

    /// Save is offered only when the form is valid and, on edit, only when something has
    /// changed. An update that changes nothing is refused by the server as
    /// `invalid_argument` — it would still write an audit record and move `updated_at` — so
    /// disabling the button is agreeing with the platform rather than second-guessing it.
    private var canSave: Bool {
        guard localIssues.isEmpty, !isSaving else { return false }
        switch mode {
        case .create:
            return !businessID.isEmpty
        case .edit:
            return !updateInput.carriesNoChange
        }
    }

    // MARK: - Input construction

    private var createInput: CreateCustomerInput {
        CreateCustomerInput(
            businessID: businessID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerType: customerType,
            email: CustomerFieldRules.optionalValue(email),
            phone: CustomerFieldRules.optionalValue(phone),
            country: CustomerFieldRules.optionalValue(country),
            address: CustomerFieldRules.optionalValue(address),
            notes: CustomerFieldRules.optionalValue(notes)
        )
    }

    /// The three-way diff. Absent means unchanged, a value means set, null means cleared —
    /// and this is the one place in the app where that distinction is produced, so it is made
    /// once and made explicitly.
    private var updateInput: UpdateCustomerInput {
        guard case .edit(let original) = mode else {
            return UpdateCustomerInput(customerID: "", displayName: nil, customerType: nil)
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateCustomerInput(
            customerID: original.customerID,
            displayName: trimmedName == original.displayName ? nil : trimmedName,
            customerType: customerType == original.customerType ? nil : customerType,
            email: diff(email, against: original.email),
            phone: diff(phone, against: original.phone),
            country: diff(country, against: original.country),
            address: diff(address, against: original.address),
            notes: diff(notes, against: original.notes)
        )
    }

    private func diff(_ text: String, against original: String?) -> FieldUpdate<String> {
        let value = CustomerFieldRules.optionalValue(text)
        if value == original { return .unchanged }
        guard let value else { return .cleared }
        return .set(value)
    }

    // MARK: - Lifecycle

    private func prepare() {
        switch mode {
        case .create:
            if businessID.isEmpty {
                businessID = model.businesses.first?.id ?? ""
            }
        case .edit(let customer):
            displayName = customer.displayName
            customerType = customer.customerType
            businessID = customer.businessID
            email = customer.email ?? ""
            phone = customer.phone ?? ""
            country = customer.country ?? ""
            address = customer.address ?? ""
            notes = customer.notes ?? ""
        }
    }

    private func save() async {
        hasAttemptedSave = true
        serverIssues = []
        guard localIssues.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let saved: Customer?
        switch mode {
        case .create: saved = await model.create(createInput)
        case .edit: saved = await model.update(updateInput)
        }

        if let saved {
            onSaved(saved)
            dismiss()
        } else {
            // A rejection that names fields belongs on those fields, not in a modal on top of
            // a modal. Anything else — forbidden, unavailable, a stale record — stays with the
            // directory's own alert, because it is not something this form can fix.
            serverIssues = model.takeFieldIssues()
        }
    }
}
