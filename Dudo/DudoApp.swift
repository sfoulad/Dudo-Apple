import SwiftUI

@main
struct DudoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 700)
        .commands {
            // Placeholder for menu-bar commands. macOS gets a real menu bar;
            // this is one of the documented places where the Apple platforms
            // deliberately diverge rather than sharing a single layout.
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
