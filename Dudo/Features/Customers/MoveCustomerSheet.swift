import SwiftUI

/// `customers.MoveCustomerToBusiness`.
///
/// This is a screen of its own, and not a field on the edit form, because the platform makes
/// it a separate Action with its own permission and its own audit record. Folding it into an
/// edit would be this client offering the same capability without either of those — which is
/// exactly why the contract leaves `business_id` off the update input and says it may not be
/// added.
///
/// A move never changes the customer's Organization. There is no such operation, and there
/// never will be: a customer's tenant is assigned at creation and is immutable.
struct MoveCustomerSheet: View {
    let customer: Customer
    @Bindable var model: CustomerDirectoryModel
    var onMoved: (Customer) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var destination: String = ""
    @State private var isMoving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Currently in") {
                    Label(
                        model.businessLabel(for: customer.businessID),
                        systemImage: "briefcase"
                    )
                    .foregroundStyle(.secondary)
                }

                Section {
                    if destinations.isEmpty {
                        Text("There is no other business to move this customer to.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Move to", selection: $destination) {
                            ForEach(destinations) { business in
                                Text(business.displayLabel).tag(business.id)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                } header: {
                    Text("Move to")
                } footer: {
                    Text("The customer's details and status do not change — only which business it belongs to.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Move Customer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isMoving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isMoving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Move") { Task { await move() } }
                            .disabled(destination.isEmpty)
                    }
                }
            }
        }
        .onAppear { destination = destinations.first?.id ?? "" }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    /// The Business the customer is already in is not offered: a move that moves nothing is
    /// refused, because it would still write an audit record saying a customer changed
    /// Business.
    private var destinations: [BusinessReference] {
        model.businesses.filter { $0.id != customer.businessID }
    }

    private func move() async {
        isMoving = true
        defer { isMoving = false }
        if let moved = await model.move(customerID: customer.customerID, to: destination) {
            onMoved(moved)
            dismiss()
        }
    }
}
