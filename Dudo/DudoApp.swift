import SwiftUI

@main
struct DudoApp: App {
    /// The one directory model the app runs on, owned here so that the macOS menu bar can act
    /// on the same state the window is showing.
    ///
    /// It is built on `FixtureCustomerDirectoryRepository`: an in-memory stand-in for Core.
    /// **The app makes no network request of any kind** — there is no Dudo server, nothing
    /// authenticates, and no deployment exists. Swapping in a transport-backed repository is a
    /// one-line change here and changes no view.
    @State private var model: CustomerDirectoryModel

    init() {
        let fixture = FixtureCustomerDirectoryRepository()
        _model = State(
            initialValue: CustomerDirectoryModel(repository: fixture, businessProvider: fixture)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 720)
        .commands {
            // macOS gets a real menu bar. This is one of the documented places where the Apple
            // platforms deliberately diverge rather than sharing a single layout: the same two
            // actions exist on iPhone and iPad, where they live in the toolbar instead.
            CommandGroup(replacing: .newItem) {
                Button("New Customer") {
                    model.isPresentingCreate = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Directory") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}
