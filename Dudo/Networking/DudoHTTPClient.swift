import Foundation

/// The real transport. One `URLSession`, one request builder, one error path.
///
/// ===========================================================================================
/// THE COOKIE STORE IS TURNED OFF ON PURPOSE, AND THIS IS THE MOST IMPORTANT LINE IN THE FILE
/// ===========================================================================================
///
/// `identity.login.complete` returns the session credential in a `Set-Cookie` header.
/// `URLSession` would happily accept it into `HTTPCookieStorage`, send it automatically
/// thereafter, and — on a non-ephemeral configuration — **write it to disk in a file with no
/// protection class of its own**. That would put a bearer credential for a business's customer
/// records somewhere other than the Keychain, and leave a second copy that "sign out" would
/// have to remember to clear.
///
/// So the store is disabled outright: the configuration is ephemeral, `httpCookieStorage` is
/// nil, cookies are neither accepted nor sent, and the `Set-Cookie` header is parsed by hand in
/// `IdentityService`. The credential then exists in exactly two places — the Keychain, and this
/// object's memory for as long as the app is running — and `Authorization: Bearer` is how it
/// goes back out.
///
/// `platform/core/identity/session-credential.ts` documents that direction as the supported
/// one: *"an Apple client obtains the credential by reading the `Set-Cookie` header … and may
/// then present it as `Authorization: Bearer`"*. It also refuses a request presenting a cookie
/// and a header with DIFFERENT values, which is a confusion attack — with the store off, this
/// client cannot produce that request even by accident.
final class DudoHTTPClient {

    /// What a request is allowed to carry.
    enum Authorization {
        /// A pre-authentication endpoint. No credential is attached even if one is held.
        case none
        /// An Action route. Fails before sending if no credential is held, rather than making
        /// an anonymous request that would come back `unauthenticated` and look like an expired
        /// session.
        case sessionCredential

        /// A named credential, presented as `Authorization: Bearer` without consulting
        /// `sessionCredential`.
        ///
        /// IT EXISTS FOR LOGOUT AND FOR NOTHING ELSE. Sign-out discards the Keychain copy and
        /// this object's copy FIRST and unconditionally — the local credential must be gone
        /// whatever the server does — so by the time the revocation request is built there is no
        /// held credential left to read. This case is what lets that request still carry the
        /// value being revoked.
        ///
        /// A `401` on this path does NOT end a session, because there is no longer one to end.
        case explicitCredential(String)
    }

    struct Request {
        var method: String
        var path: String
        var query: [URLQueryItem] = []
        var body: JSONValue?
        var authorization: Authorization
    }

    struct RawResponse {
        var statusCode: Int
        var data: Data
        /// `X-Request-Id`, returned on every response, success or error. Kept so a person can
        /// quote it to support without being asked to share anything about their records.
        var requestID: String?
        /// The raw `Set-Cookie` value, if any. Only `IdentityService` looks at this.
        var setCookie: String?
        var retryAfterSeconds: Int?
    }

    private let baseURL: URL
    private let session: URLSession

    /// The session credential, held only while the app is running. The durable copy is in the
    /// Keychain and `SessionController` owns keeping the two in step.
    var sessionCredential: String?

    /// Called when an authenticated request comes back `unauthenticated`.
    ///
    /// It exists so that exactly one place decides what an expired session means — clear the
    /// Keychain and return to sign-in — instead of every screen discovering it separately and
    /// two of them getting it wrong.
    var onUnauthenticated: (() -> Void)?

    /// `protocolClasses` IS A TEST SEAM AND HAS EXACTLY ONE LEGITIMATE USE.
    ///
    /// It lets the test target insert a `URLProtocol` subclass that answers requests in process,
    /// so the transport can be exercised with no server, no port, no external process and no
    /// network — which is what makes those tests runnable on a simulator, on a device, and in a
    /// future CI job that has none of the above.
    ///
    /// IT DEFAULTS TO `nil` AND THE APP NEVER PASSES ANYTHING. A shipped build has the standard
    /// protocol stack and cannot be steered onto another one: nothing in `Dudo/` calls this with
    /// a value, and a parameter that only tests supply is a far smaller surface than a mutable
    /// static someone could set at runtime.
    init?(baseURL: URL? = DudoBackendConfiguration.baseURL, protocolClasses: [AnyClass]? = nil) {
        guard let baseURL else { return nil }
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // Long enough for a slow connection, short enough that a wrong address fails while the
        // person is still looking at the screen rather than after they have given up.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Sending

    /// Performs a request and returns the raw response for any 2xx.
    ///
    /// A NON-2XX IS THROWN AS A `CustomerDirectoryError`, DECODED FROM THE ENVELOPE. The status
    /// code is consulted only when the body is not an envelope, which in practice means
    /// something other than Dudo answered.
    func perform(_ request: Request) async throws -> RawResponse {
        var urlRequest = try makeURLRequest(request)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw TransportFailureMapping.fromURLError(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CustomerDirectoryError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw CustomerDirectoryError.internalFailure
        }

        let raw = RawResponse(
            statusCode: http.statusCode,
            data: data,
            requestID: http.value(forHTTPHeaderField: "X-Request-Id"),
            setCookie: http.value(forHTTPHeaderField: "Set-Cookie"),
            retryAfterSeconds: http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        )

        guard (200..<300).contains(http.statusCode) else {
            throw failure(from: raw, authorization: request.authorization)
        }
        return raw
    }

    /// Performs a request and decodes the Action's output shape from the body.
    func send<Output: Decodable>(_ request: Request, as _: Output.Type) async throws -> Output {
        let raw = try await perform(request)
        do {
            return try Customer.wireDecoder().decode(Output.self, from: raw.data)
        } catch {
            // A 2xx whose body does not match the contract is not something the interface can
            // recover from or explain, and showing the decoding error would leak internal
            // structure into the UI. It is reported as an internal failure, which is what it is.
            throw CustomerDirectoryError.internalFailure
        }
    }

    // MARK: - Building

    private func makeURLRequest(_ request: Request) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: request.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw CustomerDirectoryError.internalFailure
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else { throw CustomerDirectoryError.internalFailure }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method

        if let body = request.body {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try? encoder.encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        switch request.authorization {
        case .none:
            break
        case .sessionCredential:
            guard let sessionCredential else {
                // NOT an anonymous request. A missing credential is the same condition as an
                // expired one from the user's point of view, and it is answered the same way,
                // without a pointless round trip that would look like a server rejection.
                throw CustomerDirectoryError.unauthenticated
            }
            urlRequest.setValue("Bearer \(sessionCredential)", forHTTPHeaderField: "Authorization")
        case .explicitCredential(let credential):
            urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }

        // NO `Cookie` HEADER IS EVER SET, ON ANY PATH, AND THAT IS THE POINT OF THE DISABLED
        // COOKIE STORE. Core refuses a request presenting a cookie and a bearer header that
        // disagree — a confusion attack, where a cookie an attacker planted cross-site sits
        // beside the header the application set and the server is free to pick a winner. On
        // `identity.session.revoke` the consequence of that refusal is specific: nothing is
        // revoked, and the caller is told the same fixed thing regardless. Presenting exactly
        // one carrier is what makes that case unreachable from this client.
        return urlRequest
    }

    // MARK: - Failure

    private func failure(from raw: RawResponse, authorization: Authorization) -> CustomerDirectoryError {
        let decoded = (try? JSONDecoder().decode(ErrorEnvelope.self, from: raw.data))?
            .asDirectoryError()
        let error = decoded ?? TransportFailureMapping.fromStatusCode(
            raw.statusCode, retryAfterHeader: raw.retryAfterSeconds
        )

        // The envelope's `retry_after_seconds` is authoritative; the `Retry-After` header is
        // derived from it by the HTTP adapter. If the envelope carried no number but the header
        // did, use the header rather than telling the person "try again later" with no "when".
        let withRetry: CustomerDirectoryError
        switch error {
        case .rateLimited(nil):
            withRetry = .rateLimited(retryAfterSeconds: raw.retryAfterSeconds)
        case .quotaExceeded(nil):
            withRetry = .quotaExceeded(retryAfterSeconds: raw.retryAfterSeconds)
        default:
            withRetry = error
        }

        if case .unauthenticated = withRetry, case .sessionCredential = authorization {
            // Only an AUTHENTICATED request that comes back unauthenticated means the session
            // ended. A 401 from the login endpoint means the credential was wrong, and routing
            // that through here would sign the user out of a session they never had.
            onUnauthenticated?()
        }
        return withRetry
    }
}

// MARK: - Reachability

extension DudoHTTPClient {
    /// Calls `platform.health`, which renders a fixed constant body and touches no account.
    ///
    /// It exists so that "the address is wrong or the server is down" can be distinguished from
    /// "the credential is wrong" BEFORE a password is typed. Those two produce very different
    /// advice and Dudo's login endpoint deliberately cannot tell them apart — its answers are a
    /// fixed table precisely so that they carry no information.
    func isReachable() async -> Bool {
        let request = Request(method: "GET", path: DudoPath.health, authorization: .none)
        return (try? await perform(request)) != nil
    }
}
