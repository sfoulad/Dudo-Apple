import Foundation
import Testing
@testable import Dudo

/// Reading the session credential out of `Set-Cookie`.
///
/// `identity.login.complete` returns `200 {"status":"ok"}` and the body carries NO token — one
/// fixed body for every outcome, because a body that varied in length would itself be a
/// disclosure channel. The only per-request channel is the header, so this parser is the single
/// point at which the Apple client obtains a session at all. If it is wrong, login appears to
/// succeed and the app does not stay signed in.
@Suite("Session credential")
struct SessionCredentialTests {

    /// The exact header `http/pre-auth-http.ts` renders.
    private let issued =
        "dudo_session=sess_abc.def; Max-Age=43200; Path=/; HttpOnly; Secure; SameSite=Lax"

    @Test("The credential is read from the issued cookie")
    func readsTheCredential() {
        let credential = IdentityService.sessionCredential(fromSetCookie: issued)
        #expect(credential?.value == "sess_abc.def")
    }

    /// `Secure` is set unconditionally by Core. A policy-aware parser is entitled to drop such a
    /// cookie arriving over plain HTTP, which is exactly the local development case — and the
    /// failure would present as "login worked but I am still signed out", which is a miserable
    /// thing to debug. Hand-parsing is what avoids it, and this test is what pins it.
    @Test("A Secure cookie is still read over an insecure connection")
    func secureAttributeDoesNotBlockReading() {
        #expect(IdentityService.sessionCredential(fromSetCookie: issued) != nil)
    }

    @Test("Max-Age becomes the absolute expiry")
    func maxAgeBecomesExpiry() throws {
        let credential = try #require(IdentityService.sessionCredential(fromSetCookie: issued))
        let lifetime = credential.expiresAt.timeIntervalSinceNow
        // 12 hours, per 0015 §B. The window allows for the time this test takes to run.
        #expect(lifetime > 43_100 && lifetime <= 43_200)
        #expect(!credential.isExpired)
    }

    /// `Max-Age=0` with an empty value is Core's CLEARING cookie. Treating it as a credential
    /// would sign a user in with the empty string.
    @Test("The clearing cookie is not a credential")
    func clearingCookieIsRefused() {
        let clearing = "dudo_session=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax"
        #expect(IdentityService.sessionCredential(fromSetCookie: clearing) == nil)
    }

    @Test("An unrelated cookie yields nothing")
    func unrelatedCookieIsIgnored() {
        #expect(IdentityService.sessionCredential(fromSetCookie: "other=1; Path=/") == nil)
    }

    /// Cookie shadowing — sending `dudo_session` twice so that two ends of the connection
    /// disagree about which is real — is a known attack. Core takes the first occurrence
    /// deterministically in `readPresentedCredentials`, and this client applies the same rule.
    @Test("First occurrence wins when a cookie is shadowed")
    func firstOccurrenceWins() {
        let shadowed =
            "dudo_session=first; Max-Age=43200; Path=/,dudo_session=second; Max-Age=43200"
        #expect(IdentityService.sessionCredential(fromSetCookie: shadowed)?.value == "first")
    }

    @Test("A credential with no Max-Age falls back to the contract's 12 hours")
    func missingMaxAgeFallsBack() throws {
        let header = "dudo_session=sess_abc.def; Path=/; HttpOnly; Secure"
        let credential = try #require(IdentityService.sessionCredential(fromSetCookie: header))
        let lifetime = credential.expiresAt.timeIntervalSinceNow
        #expect(lifetime > SessionCredential.defaultLifetime - 100)
    }

    @Test("An expired credential reports itself expired")
    func expiryIsHonoured() {
        let stale = SessionCredential(value: "x", expiresAt: Date().addingTimeInterval(-1))
        #expect(stale.isExpired)
    }
}
