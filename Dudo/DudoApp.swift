import SwiftUI

@main
struct DudoApp: App {
    /// Who is signed in, and therefore what the window shows.
    ///
    /// ===========================================================================================
    /// THE APP NOW MAKES REAL REQUESTS, AND THE FIXTURE IS STILL HERE
    /// ===========================================================================================
    ///
    /// `SessionController` owns both. Signing in produces an `HTTPCustomerDirectoryRepository`
    /// talking to the server named by the `DUDO_API_BASE_URL` build setting; "Explore with
    /// sample data" produces `FixtureCustomerDirectoryRepository`, which holds records in memory
    /// and makes no request of any kind. **Both conform to the same protocol and no view knows
    /// which one it has** — which is what that protocol was put there for before there was
    /// anything to put behind it.
    ///
    /// The fixture is not a leftover. No Dudo server is deployed, so it is how the interface is
    /// demonstrated and reviewed most of the time, and it is the only way to run this app on a
    /// device that cannot reach a developer's laptop.
    @State private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 720)
        .commands {
            // macOS gets a real menu bar. This is one of the documented places where the Apple
            // platforms deliberately diverge rather than sharing a single layout: the same
            // actions exist on iPhone and iPad, where they live in the toolbar instead.
            //
            // EVERY COMMAND IS DISABLED WHEN THERE IS NO DIRECTORY. A menu bar offering "New
            // Customer" over the sign-in screen offers an action that cannot happen, and a
            // command that silently does nothing is worse than one that is visibly unavailable.
            CommandGroup(replacing: .newItem) {
                Button("New Customer") {
                    session.directory?.isPresentingCreate = true
                }
                .keyboardShortcut("n", modifiers: .command)
                // Also unavailable when the principal is authorized over no Business. ⌘N must not
                // be the one remaining route into a form that cannot be submitted, and a menu bar
                // that disagreed with the window's own toolbar would be the more confusing of the
                // two. Presentation, not enforcement — Core refuses the request either way.
                .disabled(session.directory?.canCreateCustomer != true)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Directory") {
                    guard let directory = session.directory else { return }
                    Task { await directory.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.directory == nil)
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button(session.phase == .demonstration ? "Leave Sample Data" : "Sign Out") {
                    session.signOut()
                }
                .disabled(session.directory == nil)
            }
        }
        #endif
    }
}
