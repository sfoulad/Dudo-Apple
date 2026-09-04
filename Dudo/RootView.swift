import SwiftUI

/// What the window contains: sign-in, or the directory.
///
/// The switch is on `SessionController.phase` and there is exactly one of it. Every screen
/// below this point can assume it has a directory to render, which is why none of them carries
/// a "signed out" branch of its own.
struct RootView: View {
    @Bindable var session: SessionController

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                restoring
            case .signedOut:
                SignInView(session: session)
            case .signedIn, .demonstration:
                directory
            }
        }
        .animation(.smooth(duration: 0.25), value: session.phase)
        .task { session.restore() }
    }

    /// Reading the Keychain. It is quick, and it is shown as a neutral progress state rather
    /// than as the sign-in screen, so that someone who is already signed in does not see a
    /// login form flash past on every launch.
    private var restoring: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .accessibilityLabel("Opening Dudo")
    }

    @ViewBuilder
    private var directory: some View {
        if let model = session.directory {
            VStack(spacing: 0) {
                if session.phase == .demonstration {
                    demonstrationBanner
                }
                ContentView(model: model)
            }
            .environment(\.dudoSignOut, DudoSignOutAction { session.signOut() })
        } else {
            // Not reachable: `phase` only becomes `.signedIn` or `.demonstration` after a model
            // is built. It is rendered rather than force-unwrapped because a crash on launch is
            // the worst possible answer to a state that should not occur.
            SignInView(session: session)
        }
    }

    /// Says, permanently and on screen, that these are not real records.
    ///
    /// IT IS NOT DISMISSIBLE, and that is the point. Sample data looks exactly like real data,
    /// and someone reviewing a build has to be able to tell at any moment which they are looking
    /// at. Nothing observed in this mode is evidence about authorization, tenancy or the
    /// not_found/forbidden distinction, because there is no server behind it to make those
    /// decisions.
    private var demonstrationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .accessibilityHidden(true)
            Text("Sample data — not connected to a Dudo server.")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 8)
            Button("Sign In") { session.signOut() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .underline()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(DudoStyle.navy)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Signing out from anywhere below the root

/// Leaving the current session, passed down the environment rather than through every view.
///
/// It is an environment value so that `CustomerListView` — which knows about a directory and
/// deliberately knows nothing about sessions — can offer the control without taking a dependency
/// on `SessionController`. A view that has no session above it simply does not see the action and
/// shows no menu item, which is what the previews rely on.
struct DudoSignOutAction: Equatable {
    private let handler: @MainActor () -> Void
    private let id = UUID()

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction() {
        handler()
    }

    static func == (lhs: DudoSignOutAction, rhs: DudoSignOutAction) -> Bool {
        lhs.id == rhs.id
    }
}

extension EnvironmentValues {
    @Entry var dudoSignOut: DudoSignOutAction?
}
