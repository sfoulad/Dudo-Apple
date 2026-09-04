import SwiftUI

/// The Dudo application shell.
///
/// One feature is in it: the Customer Directory. Dudo is built one complete vertical slice at
/// a time, so there is no navigation to modules that do not exist and no menu of greyed-out
/// promises — what is here works, and nothing else is implied.
///
/// THREE PLATFORMS, ONE CODEBASE, TWO NAVIGATION SHAPES. iPhone pushes; iPad and the Mac put
/// the directory and the record side by side. That divergence is deliberate — it is one of
/// the places Apple's platforms genuinely differ — rather than a reason to make three apps
/// out of one.
struct ContentView: View {
    @Bindable var model: CustomerDirectoryModel

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Both columns, from launch. Left to itself an iPad in portrait hides the sidebar and
    /// opens on an empty detail column, so the first thing anyone would see of Dudo is a
    /// placeholder telling them to reveal the list they came for.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        shell
            .sheet(isPresented: $model.isPresentingCreate) {
                CustomerFormView(mode: .create, model: model) { created in
                    // Land on the record that was just added, so the person sees the result of
                    // what they did rather than a list they now have to search.
                    model.selection = created.customerID
                }
            }
            .alert(
                model.actionError?.errorDescription ?? "Something went wrong",
                isPresented: alertBinding,
                presenting: model.actionError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                }
            }
            .overlay(alignment: .bottom) { confirmation }
            .animation(.snappy(duration: 0.25), value: model.lastActionMessage)
    }

    // MARK: - Navigation

    @ViewBuilder
    private var shell: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            stackShell
        } else {
            splitShell
        }
        #else
        splitShell
        #endif
    }

    /// iPhone: a stack. A row pushes a record, and the back button returns to the directory.
    private var stackShell: some View {
        NavigationStack {
            CustomerListView(model: model, usesSelection: false)
                .navigationDestination(for: CustomerSummary.ID.self) { customerID in
                    CustomerDetailView(customerID: customerID, model: model)
                }
        }
    }

    /// iPad and Mac: two columns. A row selects, the record stays on screen while the list is
    /// filtered or searched, and the window keeps its shape.
    private var splitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CustomerListView(model: model, usesSelection: true)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                #endif
        } detail: {
            NavigationStack {
                if let selection = model.selection {
                    CustomerDetailView(customerID: selection, model: model)
                        // A fresh identity per customer, so the detail screen reloads rather
                        // than showing the previous record while the next one arrives.
                        .id(selection)
                } else {
                    CustomerDetailPlaceholder()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Feedback

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )
    }

    /// One short confirmation after something worked. It says what happened and gets out of
    /// the way — a business tool should not need a dialog dismissed after every save.
    @ViewBuilder
    private var confirmation: some View {
        if let message = model.lastActionMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.2))
                    guard !Task.isCancelled else { return }
                    model.lastActionMessage = nil
                }
        }
    }
}

#Preview("Customer Directory") {
    let repository = FixtureCustomerDirectoryRepository()
    ContentView(
        model: CustomerDirectoryModel(repository: repository, businessProvider: repository)
    )
}
