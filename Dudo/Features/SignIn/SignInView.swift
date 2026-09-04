import SwiftUI

/// Signing in to Dudo.
///
/// ===========================================================================================
/// ONE MESSAGE FOR EVERY REFUSAL, AND THE INTERFACE MUST NOT TRY TO BE MORE HELPFUL
/// ===========================================================================================
///
/// Core answers a single fixed 401 for a wrong password, an address nobody has ever registered,
/// a suspended account and a deleted principal alike. That is not a limitation to work around —
/// it is the property the whole pre-authentication path is built to have, because an endpoint
/// that said "no such account" would let anyone test whether an address belongs to a Dudo
/// customer. This screen therefore shows one sentence, it never suggests the address might be
/// unknown, and it never offers "did you mean to register?".
///
/// The one place it IS specific is the email-shape refusal, which is decided entirely here, from
/// characters the person just typed, without asking anything of anyone.
///
/// ===========================================================================================
/// THE PROGRESS BAR MEASURES REAL WORK
/// ===========================================================================================
///
/// 600,000 PBKDF2 iterations happen on this device before anything is sent, and on an older
/// iPhone that is a noticeable wait. It is reported from inside the derivation loop, so the bar
/// is showing work rather than an animation timed against a guess, and the label says what the
/// device is doing rather than a generic "please wait".
struct SignInView: View {
    let session: SessionController

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: DudoStyle.Space.section) {
                header
                form
                if let failure = session.signInFailure {
                    failureNotice(failure)
                }
                actions
                serverNotice
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 40))
                .foregroundStyle(DudoStyle.navy)
                .accessibilityHidden(true)
            Text("Dudo")
                .font(.largeTitle.weight(.semibold))
            Text("Sign in to your organisation's directory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: DudoStyle.Space.row) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("you@company.com", text: $email)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .email)
                    #if os(iOS)
                    // The keyboard must not autocapitalise or autocorrect: the address is the
                    // PBKDF2 salt, and a capital letter the person did not type would still
                    // normalise correctly, but an autocorrected domain would not.
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
            }
        }
        .disabled(session.isSigningIn)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: DudoStyle.Space.row) {
            if session.isSigningIn {
                signingInIndicator
            }

            Button {
                submit()
            } label: {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)

            // THE FIXTURE STAYS AND STAYS REACHABLE. It is how the interface is demonstrated
            // and reviewed with no server running, which is the ordinary case today.
            Button("Explore with sample data") {
                session.enterDemonstrationMode()
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.medium))
            .foregroundStyle(DudoStyle.scarlet)
            .disabled(session.isSigningIn)
        }
    }

    private var signingInIndicator: some View {
        VStack(spacing: 6) {
            if let progress = session.derivationProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("Securing your password on this device…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signing in")
    }

    private func failureNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(DudoStyle.scarlet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DudoStyle.Space.row)
            .background(DudoStyle.scarlet.opacity(0.08), in: .rect(cornerRadius: 10))
            .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Which server

    /// Names the server this build talks to, and warns when the connection is not encrypted.
    ///
    /// A tester who cannot tell which backend a build points at cannot report a useful bug, and
    /// the plain-HTTP warning is not decoration: the derived login secret and the session
    /// credential both cross this connection. Over HTTP anything on the path can read them,
    /// which is tolerable pointed at a laptop and is not tolerable anywhere else.
    @ViewBuilder
    private var serverNotice: some View {
        VStack(spacing: 6) {
            if session.hasConfiguredServer {
                Text(DudoBackendConfiguration.serverLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if DudoBackendConfiguration.isInsecureTransport {
                    Label("Unencrypted connection — development only", systemImage: "lock.open")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No Dudo server is configured for this build. Sample data is available.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(DudoBuild.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Submission

    private var canSubmit: Bool {
        session.hasConfiguredServer
            && !session.isSigningIn
            && !email.isEmpty
            && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let submittedEmail = email
        let submittedPassword = password
        Task {
            await session.signIn(email: submittedEmail, password: submittedPassword)
            // The password is cleared whatever the outcome. On success it is spent; on failure
            // re-typing it is the correct next step, and leaving it in a live SecureField keeps
            // it in memory on a screen that may sit untouched.
            password = ""
        }
    }
}

#Preview("Sign in") {
    SignInView(session: SessionController(client: nil))
}
