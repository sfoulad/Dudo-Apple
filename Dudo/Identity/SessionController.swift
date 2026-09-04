import Foundation
import Observation

/// Who is signed in, what the app is therefore showing, and the one place that changes.
///
/// ===========================================================================================
/// AN UNAUTHENTICATED LAUNCH SHOWS SIGN-IN, NEVER THE DIRECTORY
/// ===========================================================================================
///
/// The customer list is not rendered — not empty, not greyed out, not behind a spinner — until
/// there is a session. That is a product decision as much as a security one: a directory that
/// appears and then fails every request teaches a person that Dudo is broken, when in fact they
/// simply are not signed in.
///
/// It is NOT a security control, and nothing here should be mistaken for one. Every request is
/// authorized on the server, on every call, and hiding a screen changes nothing about what a
/// request would be allowed to do. `.claude/rules/security.md` §2: UI-level hiding is
/// presentation, never security.
@MainActor
@Observable
final class SessionController {

    enum Phase: Equatable {
        /// Reading the Keychain at launch. Brief, and shown as a blank progress state rather
        /// than as a flash of the sign-in screen for someone who is already signed in.
        case restoring
        case signedOut
        /// Signed in against a real Dudo server.
        case signedIn
        /// The fixture directory. No server, no session, no network.
        case demonstration
    }

    // MARK: State

    private(set) var phase: Phase = .restoring

    /// The directory the interface renders. Rebuilt on every transition so that a model holding
    /// one person's rows can never be handed to the next person to sign in.
    private(set) var directory: CustomerDirectoryModel?

    /// How far the key derivation has got, 0...1, or nil when nothing is deriving.
    ///
    /// IT IS A REAL MEASUREMENT. `LoginSecretDerivation` reports it from the PBKDF2 loop itself,
    /// so the bar tracks work that is actually happening rather than an animation timed against
    /// a guess. See that file for why the derivation is hand-written to make this possible.
    private(set) var derivationProgress: Double?

    /// True from the moment Sign In is tapped until the answer arrives.
    private(set) var isSigningIn = false

    /// What the sign-in screen shows when the last attempt failed.
    ///
    /// ONE MESSAGE FOR EVERY REFUSAL. Core answers a fixed 401 for a wrong password, an unknown
    /// address, a suspended account and a deleted principal alike, because an endpoint that
    /// distinguished them would tell an attacker which addresses have accounts. This client must
    /// not reconstruct that distinction, and it has nothing to reconstruct it from.
    var signInFailure: String?

    private let client: DudoHTTPClient?

    // MARK: Init

    init(client: DudoHTTPClient? = DudoHTTPClient()) {
        self.client = client
        client?.onUnauthenticated = { [weak self] in
            self?.sessionEnded()
        }
    }

    var hasConfiguredServer: Bool { client != nil }

    // MARK: - Launch

    /// Restores a stored session, if there is a live one.
    ///
    /// A stored credential is used WITHOUT being checked against the server first. There is no
    /// endpoint to check it against — `identity.session.refresh` has no handler under `0015`
    /// §B.3, and calling a business Action just to test a credential would spend rate budget to
    /// learn something the next real call learns anyway. If it has expired or been revoked the
    /// first request answers `unauthenticated` and `sessionEnded()` puts the person back here.
    func restore() {
        guard client != nil else {
            phase = .signedOut
            return
        }
        if let stored = SessionCredentialStore.load() {
            adopt(stored)
        } else {
            phase = .signedOut
        }
    }

    // MARK: - Signing in

    /// Derives the login secret and exchanges it for a session.
    ///
    /// THE PASSWORD DOES NOT LEAVE THIS FUNCTION. It goes into `deriveLoginSecret` and what
    /// comes out is 43 base64url characters; `IdentityService` has no parameter that could
    /// carry a password even if someone tried.
    func signIn(email: String, password: String) async {
        guard let client else {
            signInFailure = "This build has no Dudo server configured."
            return
        }
        signInFailure = nil

        if let refusal = LoginSecretDerivation.refusalReason(forSubmittedIdentifier: email) {
            // Decided entirely by the shape of what was typed. It consults nothing, and it
            // cannot tell a real address from an invented one, so it is not an existence signal.
            signInFailure = refusal.message
            return
        }

        isSigningIn = true
        derivationProgress = 0
        defer {
            isSigningIn = false
            derivationProgress = nil
        }

        // ===================================================================================
        // 600,000 ITERATIONS RUN OFF THE MAIN ACTOR. This is not a nicety.
        // ===================================================================================
        // The derivation takes on the order of half a second on a fast Mac and appreciably
        // longer on an older iPhone. On the main actor that is a frozen window and a spinner
        // that does not spin — which a person reads as a crash, and on macOS earns a beachball.
        let derivedKey = await Task.detached(priority: .userInitiated) { [weak self] in
            LoginSecretDerivation.deriveLoginSecret(email: email, password: password) { fraction in
                Task { @MainActor in self?.derivationProgress = fraction }
            }
        }.value

        do {
            let identity = IdentityService(client: client)
            // THE NORMALISED FORM GOES ON THE WIRE, not the raw typed one. Core normalises
            // whatever it receives, so both work — but sending the normalised value makes the
            // string in the request provably the same string that was used as the PBKDF2 salt.
            // If the two ever diverge, this is the line that would hide it.
            let credential = try await identity.completeLogin(
                email: LoginSecretDerivation.normalizeIdentifier(email),
                derivedKey: derivedKey
            )
            SessionCredentialStore.save(credential)
            adopt(credential)
        } catch let error as CustomerDirectoryError {
            signInFailure = signInMessage(for: error)
        } catch is CancellationError {
            return
        } catch {
            signInFailure = CustomerDirectoryError.unavailable.errorDescription
        }
    }

    /// The sign-in screen's wording for a failure.
    ///
    /// `unauthenticated` is the fixed refusal and gets the deliberately uninformative sentence.
    /// Everything else is about Dudo's own availability rather than about the credential, and
    /// saying so is what stops someone re-typing a correct password for ten minutes while the
    /// platform is at its daily write ceiling — a case `login.ts` calls out by name.
    private func signInMessage(for error: CustomerDirectoryError) -> String {
        switch error {
        case .unauthenticated:
            "That email address and password did not match. Check both and try again."
        case .rateLimited(let seconds), .quotaExceeded(let seconds):
            seconds.map { "Too many sign-in attempts. Try again in about \($0) seconds." }
                ?? "Too many sign-in attempts. Wait a moment and try again."
        default:
            [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    // MARK: - Leaving

    /// Signs out: discards the credential here, then asks Core to delete the session row.
    ///
    /// ===========================================================================================
    /// THE ORDER IS THE WHOLE DESIGN. LOCAL FIRST, UNCONDITIONALLY, AND NEVER AWAITED.
    /// ===========================================================================================
    ///
    /// Revocation is `disclosure: 'collapsed'`, so its answer is the same fixed response whether
    /// the row was deleted, was already gone, or could not be deleted at all. **This client
    /// therefore cannot know whether the server did anything**, and the likeliest silent failure
    /// is the platform's daily write ceiling — at which point logout stops working while still
    /// reporting success.
    ///
    /// The Apple client is better placed than the web one here, and this method spends that
    /// advantage: the credential is in the Keychain rather than in an `HttpOnly` cookie, so it can
    /// be destroyed locally regardless of what the server did. It is destroyed FIRST, so there is
    /// no ordering in which a failed or slow request leaves a live credential on the device.
    ///
    /// THE INTERFACE RETURNS TO SIGN-IN IMMEDIATELY, before the request is made. Nothing about the
    /// user's experience is conditioned on a response that carries no information.
    ///
    /// WHAT REMAINS TRUE AND MUST NOT BE OVERSTATED: if the server write silently failed, the
    /// credential is dead on this device and still live on the platform for the remainder of its
    /// twelve hours. Signing out protects the next person to pick up this device. It does not, by
    /// itself, protect against a credential that was already stolen.
    func signOut() {
        // Captured before anything is cleared — this is the value being revoked, and a moment
        // from now there will be nowhere left to read it from.
        let revoked = client?.sessionCredential

        SessionCredentialStore.clear()
        client?.sessionCredential = nil
        directory = nil
        phase = .signedOut

        guard let client, let revoked else { return }
        // Not awaited. There is nothing to wait for: the answer is a constant, and the user is
        // already back at the sign-in screen. If the app is killed before this completes, the
        // local credential is still gone — which is the half this client controls.
        Task { await IdentityService(client: client).revokeSession(credential: revoked) }
    }

    /// The session ended underneath a request. Reached from the transport's `unauthenticated`
    /// path, so it can fire at any moment and from any screen.
    ///
    /// ===========================================================================================
    /// `401` MEANS LOGGED OUT. IT NEVER MEANS RETRY, AND IT NEVER MEANS REVOKE.
    /// ===========================================================================================
    ///
    /// A session can end without anyone signing out: the 12-hour absolute expiry, a membership
    /// revoked, a principal suspended, or `SESSION_HMAC_KEY` rotated during an incident. Under
    /// `0015` §B there is no rotation and no refresh — `identity.session.refresh` has no handler —
    /// so there is nothing to retry WITH. A retry would present the same dead credential, receive
    /// the same `401`, and the loop would be the only thing that changed.
    ///
    /// IT MUST ALSO NOT CALL REVOCATION. The session is already gone, so revoking would spend 3
    /// row-writes deleting a row that is not there — from a control-plane budget where a full
    /// login-and-logout cycle costs 6, capping the platform at roughly 500 cycles a day and 100
    /// per principal. Nothing in this client re-authenticates automatically, for the same reason.
    private func sessionEnded() {
        guard phase == .signedIn else { return }
        SessionCredentialStore.clear()
        client?.sessionCredential = nil
        directory = nil
        phase = .signedOut
        signInFailure = "Your session has ended. Sign in again to continue."
    }

    // MARK: - The fixture, which stays

    /// Shows the directory on in-memory fixture data, with no server and no session.
    ///
    /// IT IS NOT DEAD CODE AND IT IS NOT A TEST DOUBLE THAT ESCAPED. It is how the interface is
    /// demonstrated and reviewed when no Dudo server is running — which is most of the time,
    /// because none is deployed. It is also the only way to exercise this app on a device that
    /// cannot reach a developer's laptop.
    ///
    /// It carries NO authorization, NO tenant and NO principal, so nothing observed in this mode
    /// is evidence about isolation, permissions, or the not_found/forbidden distinction. The
    /// interface labels it, on screen, for exactly that reason.
    func enterDemonstrationMode() {
        let fixture = FixtureCustomerDirectoryRepository()
        directory = CustomerDirectoryModel(repository: fixture, businessProvider: fixture)
        phase = .demonstration
    }

    // MARK: - Private

    private func adopt(_ credential: SessionCredential) {
        guard let client else { return }
        client.sessionCredential = credential.value
        let repository = HTTPCustomerDirectoryRepository(client: client)
        directory = CustomerDirectoryModel(repository: repository, businessProvider: repository)
        phase = .signedIn
    }
}
