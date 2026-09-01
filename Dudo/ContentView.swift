import SwiftUI

/// Placeholder shell for the Dudo Apple application.
///
/// There is deliberately no business logic here and no data access. Both belong
/// to Dudo-Core, and this app will reach them only through published contracts.
/// No Dudo-Core technology stack has been selected yet, so there is no API to
/// call — this screen exists to prove the build, signing, and TestFlight
/// pipeline works end to end.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Dudo")
                .font(.largeTitle.weight(.semibold))

            Text("Pre-alpha")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Self.buildLabel)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #endif
    }

    /// Version and build, shown so a tester can confirm which build they are on.
    private static var buildLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}

#Preview {
    ContentView()
}
