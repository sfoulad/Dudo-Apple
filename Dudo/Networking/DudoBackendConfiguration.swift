import Foundation

/// Where this build talks to, and whether it talks to anything at all.
///
/// ===========================================================================================
/// THE BASE URL IS A BUILD SETTING, NOT A LITERAL IN SWIFT
/// ===========================================================================================
///
/// `DUDO_API_BASE_URL` is defined per build configuration in the Xcode project and reaches the
/// bundle through `Config/Info.plist`. Debug points at a local `wrangler dev`; Release is
/// **deliberately empty**, because no Dudo server is deployed and a Release build carrying a
/// developer's laptop address would be a build that silently fails to connect in the hands of a
/// tester who has no way to see why.
///
/// AN EMPTY VALUE IS A STATE, NOT A MISCONFIGURATION. It means "this build has no server", the
/// sign-in screen says so in those words, and the fixture directory remains available so the
/// interface can still be demonstrated. That is the honest behaviour for a client whose backend
/// does not exist yet.
nonisolated enum DudoBackendConfiguration {

    /// The Info.plist key, populated from the `DUDO_API_BASE_URL` build setting.
    static let infoPlistKey = "DudoAPIBaseURL"

    /// The configured API origin, or `nil` when this build has no server.
    ///
    /// A value that is present but unusable — not a URL, or missing a scheme and host — is
    /// treated as absent rather than as something to repair at runtime. A client that guessed
    /// `https://` in front of a malformed setting would be inventing an address to send
    /// credentials to.
    static let baseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil,
              url.host() != nil
        else {
            return nil
        }
        return url
    }()

    static var hasConfiguredServer: Bool { baseURL != nil }

    /// What the sign-in screen shows under the heading, so that a tester can tell at a glance
    /// which server a build is pointed at without being asked to look in Settings.
    ///
    /// It shows the ORIGIN ONLY — scheme, host and port. Never a path, never a query, and there
    /// is nothing here that could carry a credential into the interface or into a screenshot.
    static var serverLabel: String {
        guard let baseURL, let host = baseURL.host() else { return "No server configured" }
        let scheme = baseURL.scheme ?? "https"
        if let port = baseURL.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// True when the configured server is plain HTTP.
    ///
    /// The sign-in screen warns about this, and the warning is not decoration: a password-derived
    /// secret and a session credential both cross this connection, and over HTTP both are
    /// readable by anything on the path. It is tolerable pointed at `localhost` during
    /// development and is not tolerable anywhere else, so the interface says so rather than
    /// letting it pass unremarked.
    static var isInsecureTransport: Bool {
        guard let scheme = baseURL?.scheme else { return false }
        return scheme.lowercased() != "https"
    }
}

// MARK: - Reserved paths

/// The endpoints this client calls, written once.
///
/// The pre-authentication paths are ABSOLUTE and are not relative to any App's base path —
/// `platform/core/identity/pre-auth-registry.ts` reserves `/auth/` and `/health` for Core and
/// matches them before any App router runs.
nonisolated enum DudoPath {
    /// `identity.login.complete` — the whole of login. See `IdentityService`.
    static let loginComplete = "/auth/login/complete"

    /// `identity.session.revoke` — logout. Deletes the session row.
    ///
    /// IT IS THE ONLY PRE-AUTHENTICATION ROUTE THAT READS `Authorization: Bearer`, and that is a
    /// closed allow-list in `http/pre-auth-http.ts` rather than a general rule
    /// (`docs/decisions/0018` §A). The other four entry points are blind to the header, so
    /// nothing else on this path may assume a bearer credential will be seen.
    static let sessionRevoke = "/auth/session/revoke"

    /// `platform.health` — a constant body, useful for telling "wrong address" apart from
    /// "wrong credential" before anyone types a password.
    static let health = "/health"

    /// The Customer Directory App's base path, from
    /// `packages/contracts/apps/customers/customer-directory-v1.contract.yaml` -> httpBinding.
    static let customersBase = "/api/v1/apps/customers"
    /// Core's own read surface, from `packages/contracts/core/organization/business-read-v1.contract.yaml`.
    static let coreBase = "/api/v1"
}
