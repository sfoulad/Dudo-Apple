import Foundation

/// Signs a person in. One request, one answer.
///
/// ===========================================================================================
/// THE WHOLE OF LOGIN IS `POST /auth/login/complete`. `identity.login.start` IS NOT CALLED.
/// ===========================================================================================
///
/// `platform/core/identity/login.ts` registers a handler for `identity.login.start` that
/// **accepts an email and does nothing with it**, and says why: under `0015` §D the client's
/// PBKDF2 salt is the normalised email, so there is nothing for the server to send back before
/// the client can derive. Calling it would spend a rate-limit allowance and an entry-point
/// declaration for no payload.
///
///     POST /auth/login/complete
///     Content-Type: application/json
///     { "email": "<address>", "derived_key": "<43 base64url characters>" }
///
/// `derived_key` is `0015` §D's `kdf_output`, named to match the snake_case every field on this
/// platform uses. The field names are `IDENTIFIER_FIELD` and `DERIVED_KEY_FIELD` in `login.ts`
/// and are not this client's to choose.
///
/// ===========================================================================================
/// THE SUCCESS BODY CARRIES NO TOKEN, AND THAT IS A SECURITY PROPERTY RATHER THAN AN OVERSIGHT
/// ===========================================================================================
///
/// Success is `200 {"status":"ok"}` — byte for byte the same body the endpoint returns for an
/// acknowledgement. The ONLY per-request channel is `Set-Cookie`. Putting a token in the body
/// would make the issued and acknowledged responses differ in LENGTH, which is a disclosure
/// channel `pre-auth-admission.ts` enumerates. So this client reads the credential out of the
/// header and presents it afterwards as `Authorization: Bearer` — `0015` §A's "one value, two
/// carriers" works in that direction and not the reverse.
///
/// ===========================================================================================
/// FAILURE IS ONE FIXED 401 AND THIS CLIENT MUST NOT PRETEND OTHERWISE
/// ===========================================================================================
///
/// There is no "no such account", no "wrong password", no lockout notice, and no field any of
/// them could be written into — because an endpoint that answered differently for a real
/// address than for one nobody has ever used is an account-existence oracle. The interface
/// therefore shows ONE message for every refusal, and any attempt to be more helpful here would
/// undo the property the whole pre-auth path is built around.
@MainActor
struct IdentityService {

    private let client: DudoHTTPClient

    init(client: DudoHTTPClient) {
        self.client = client
    }

    /// Verifies a derived key and returns the issued session credential.
    ///
    /// `derivedKey` must already be the 43-character base64url output of
    /// `LoginSecretDerivation`. THE RAW PASSWORD IS NOT A PARAMETER OF THIS FUNCTION and must
    /// never become one: the type is the last place this client can guarantee that a password
    /// does not reach the transport.
    func completeLogin(email: String, derivedKey: String) async throws -> SessionCredential {
        let request = DudoHTTPClient.Request(
            method: "POST",
            path: DudoPath.loginComplete,
            body: .object([
                "email": .string(email),
                "derived_key": .string(derivedKey),
            ]),
            authorization: .none
        )

        let response = try await client.perform(request)

        guard let header = response.setCookie,
              let issued = Self.sessionCredential(fromSetCookie: header)
        else {
            // A 200 with no credential in it. Dudo does not produce this — `issued` always
            // carries exactly one `Set-Cookie` — so reaching here means something between this
            // app and Core stripped the header, which a proxy or a corporate tunnel will do.
            // It is `unavailable` rather than `unauthenticated`: the credential was probably
            // correct, and telling the person to re-type their password would waste their time.
            throw CustomerDirectoryError.unavailable
        }
        return issued
    }

    // MARK: - Logout

    /// `identity.session.revoke` — deletes the session row on the server.
    ///
    /// ===========================================================================================
    /// IT PRESENTS `Authorization: Bearer`, AND EXACTLY ONE CARRIER
    /// ===========================================================================================
    ///
    /// `docs/decisions/0018` §A made revocation read the bearer header. Before it, revocation
    /// parsed `Cookie` only — so this client, which deliberately keeps no cookie jar, reached
    /// `revokeHandler`, presented nothing, and was answered success while **nothing was revoked**.
    /// A security action reporting success without performing it is the worst shape a defect can
    /// take on this path, because no client could detect it.
    ///
    /// The header is honoured here and on **no other pre-authentication route**: it is a closed
    /// allow-list containing this entry point alone. Nothing else on the pre-auth path may assume
    /// a bearer credential will be seen.
    ///
    /// ONE CARRIER, NOT TWO. A cookie and a header that disagree is a confusion attack, and Core
    /// answers it by revoking nothing while returning the same fixed body. This client cannot
    /// produce that request — the cookie store is off — and must not start doing so helpfully.
    ///
    /// ===========================================================================================
    /// THE ANSWER CARRIES NO INFORMATION, WHICH IS WHY THIS RETURNS NOTHING
    /// ===========================================================================================
    ///
    /// Revocation is `disclosure: 'collapsed'`: six outcomes — nothing presented, a carrier
    /// mismatch, an invalid MAC, no such session, a real deletion, and a store or budget failure —
    /// all render the identical response. That is deliberate, so an attacker holding a stolen
    /// credential cannot learn from a logout whether it is still live.
    ///
    /// THE CONSEQUENCE THIS CLIENT LIVES WITH: **it cannot know whether the row was deleted.** The
    /// likeliest silent failure is the platform's daily write ceiling, at which point logout stops
    /// working while still answering success. That is precisely why `SessionController` discards
    /// the local credential BEFORE calling this and conditions nothing on the result.
    func revokeSession(credential: String) async {
        // NO BODY. `revokeHandler` declares `fields: []`, so every field a caller sends is
        // rejected — and there must never be a `session_id` field, because a logout taking an
        // identifier from the body would let any unauthenticated caller delete any session it
        // could name. The session comes from the presented credential, whose MAC is verified
        // before anything is read. Core reads an empty body as `{}`.
        let request = DudoHTTPClient.Request(
            method: "POST",
            path: DudoPath.sessionRevoke,
            authorization: .explicitCredential(credential)
        )
        // The failure is swallowed, and this is the one place in this client where that is right.
        // There is no outcome to report and nothing a person could do differently: the local
        // credential is already gone, so the user IS signed out on this device whatever happened
        // on the wire. Showing "sign-out failed" over an interface that has already returned to
        // the login screen would be alarming and untrue.
        _ = try? await client.perform(request)
    }

    // MARK: - Reading the credential out of `Set-Cookie`

    /// Parses `dudo_session` and its `Max-Age` out of a `Set-Cookie` header.
    ///
    /// ===========================================================================================
    /// WHY THIS IS HAND-PARSED RATHER THAN HANDED TO `HTTPCookie`
    /// ===========================================================================================
    ///
    /// `HTTPCookie.cookies(withResponseHeaderFields:for:)` applies cookie POLICY — domain
    /// matching, and on some paths the `Secure` attribute — and the credential is set with
    /// `Secure` by `http/pre-auth-http.ts` unconditionally. Against a local `http://` dev server
    /// that is precisely the case a policy-aware parser is entitled to drop, and the failure
    /// would look like "login succeeded but the app did not stay signed in", which is a
    /// miserable thing to debug.
    ///
    /// This is not a general cookie parser and must not become one. It looks for one name, takes
    /// the FIRST occurrence, and ignores everything else. First-occurrence-wins is the same rule
    /// Core applies in `readPresentedCredentials`, for the same reason: cookie shadowing, where
    /// two `dudo_session` values are sent so that two ends of the connection disagree about
    /// which is real.
    static func sessionCredential(fromSetCookie header: String) -> SessionCredential? {
        // A folded header can hold several cookies. Splitting on "," is wrong in general —
        // an `Expires` date contains one — but `Max-Age` is what Core emits and it has no
        // comma, so the split is safe for the values this client actually receives. Anything
        // it gets wrong yields no `dudo_session=` prefix and is skipped.
        for candidate in header.split(separator: ",") {
            let attributes = candidate.split(separator: ";")
            guard let first = attributes.first else { continue }
            let pair = first.trimmingCharacters(in: .whitespaces)
            guard pair.hasPrefix("dudo_session=") else { continue }

            let value = String(pair.dropFirst("dudo_session=".count))
            guard !value.isEmpty else {
                // `Max-Age=0` with an empty value is Core's CLEARING cookie, not a credential.
                continue
            }

            var lifetime = SessionCredential.defaultLifetime
            for attribute in attributes.dropFirst() {
                let trimmed = attribute.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("max-age="),
                   let seconds = TimeInterval(trimmed.dropFirst("max-age=".count)),
                   seconds > 0 {
                    lifetime = seconds
                }
            }
            return SessionCredential(value: value, expiresAt: Date().addingTimeInterval(lifetime))
        }
        return nil
    }
}
