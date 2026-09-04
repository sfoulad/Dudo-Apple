import Foundation
@testable import Dudo

/// A stand-in for Dudo-Core that answers inside this process.
///
/// ===========================================================================================
/// WHY A `URLProtocol` AND NOT THE PYTHON SERVER THIS REPLACES
/// ===========================================================================================
///
/// These checks began life against a small HTTP server on a fixed port. That worked on one
/// developer's machine and nowhere else: it needs a Python interpreter, a free port, a process
/// started before the tests and killed afterwards, and it cannot run on a device or in a CI job
/// that has none of those. Evidence that only runs in one place is evidence with an asterisk.
///
/// A `URLProtocol` is registered on the session's own configuration and intercepts requests
/// before any socket is opened. No port, no process, no network, no ordering problem — and it
/// runs identically on macOS, on a simulator, and on a device.
///
/// ===========================================================================================
/// IT IS NOT CORE AND DECIDES NOTHING CORE DECIDES
/// ===========================================================================================
///
/// There is no authorization here, no tenancy, no permission evaluation and no
/// `not_found`/`forbidden` distinction. It knows one credential string and compares it. Nothing
/// observed through this stub is evidence about isolation or authorization, and it must never
/// be reported as though it were. What it does prove is the shape of what this client SENDS and
/// what it does with what it RECEIVES — which is the whole of what a transport is responsible
/// for.
///
/// Every body it returns is transcribed from `packages/contracts`.
nonisolated final class StubCore: URLProtocol {

    // MARK: - What a route answers with

    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
        /// When set, the request fails at the transport layer instead of answering.
        var failure: URLError?

        static func json(_ status: Int, _ object: Any, headers: [String: String] = [:]) -> Reply {
            Reply(
                status: status,
                body: try! JSONSerialization.data(withJSONObject: object),
                headers: headers
            )
        }
    }

    /// What the client actually sent, kept so a test can assert on the request rather than only
    /// on the answer. The PATCH body is the reason this exists: the three-way update
    /// distinction is a claim about the bytes on the wire, and it can only be checked here.
    struct Recorded {
        var method: String
        var path: String
        var query: [String: String]
        var authorization: String?
        var cookie: String?
        var body: [String: Any]?
    }

    // MARK: - Registration

    /// A route table and a request log, shared by every instance the URL loading system makes.
    ///
    /// `URLProtocol` instances are created by Foundation, one per request, on threads it
    /// chooses — so there is nowhere else for this state to live. It is guarded by a lock rather
    /// than isolated to an actor because `canInit` and `startLoading` are synchronous overrides
    /// that cannot await.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var routes: [String: (Recorded) -> Reply] = [:]
        var recorded: [Recorded] = []
    }

    private static let state = State()

    static func reset() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.routes = [:]
        state.recorded = []
    }

    /// Registers the answer for one method and path.
    static func route(_ method: String, _ path: String, _ reply: @escaping (Recorded) -> Reply) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.routes["\(method) \(path)"] = reply
    }

    static func route(_ method: String, _ path: String, _ reply: Reply) {
        route(method, path) { _ in reply }
    }

    static var requests: [Recorded] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.recorded
    }

    static func lastRequest(_ method: String, _ path: String) -> Recorded? {
        requests.last { $0.method == method && $0.path == path }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = Self.record(request)

        Self.state.lock.lock()
        let handler = Self.state.routes["\(recorded.method) \(recorded.path)"]
        Self.state.recorded.append(recorded)
        Self.state.lock.unlock()

        guard let handler else {
            // An unregistered route answers 404 with a contract-shaped envelope rather than
            // hanging or crashing. A test that reaches an address it did not register has a bug
            // in the test, and it should see the same failure vocabulary as everything else.
            return respond(with: .json(404, [
                "error": [
                    "code": "not_found",
                    "message": "fixed developer-facing message",
                    "request_id": "req_ABCDEFGH12345678901234",
                ],
            ]))
        }
        respond(with: handler(recorded))
    }

    override func stopLoading() {}

    // MARK: - Private

    private func respond(with reply: Reply) {
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        var headers = [
            "Content-Type": "application/json; charset=utf-8",
            "X-Request-Id": "req_ABCDEFGH12345678901234",
            "Cache-Control": "no-store",
        ]
        headers.merge(reply.headers) { _, new in new }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func record(_ request: URLRequest) -> Recorded {
        let components = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return Recorded(
            method: request.httpMethod ?? "GET",
            path: components?.path ?? "",
            query: query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            cookie: request.value(forHTTPHeaderField: "Cookie"),
            body: bodyObject(of: request)
        )
    }

    /// Reads the request body, from the stream when necessary.
    ///
    /// THE STREAM CASE IS NOT AN EDGE CASE AND OMITTING IT IS THE CLASSIC BUG HERE. `URLSession`
    /// converts `httpBody` into `httpBodyStream` before a `URLProtocol` ever sees the request,
    /// so a stub that reads only `httpBody` observes `nil` for every POST and PATCH — and every
    /// assertion about what the client sent silently passes by looking at nothing.
    private static func bodyObject(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let size = 4_096
            var buffer = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: size)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data, !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - The contract-shaped bodies these tests are written against

/// Transcribed from `packages/contracts/apps/customers/customer-directory-v1.schema.json` and
/// `packages/contracts/core/organization/business-read-v1.schema.json`. Kept in one place so a
/// contract change is edited once.
nonisolated enum StubBodies {

    static let sessionCredential = "sess_0123456789abcdef.QUJDREVGR0hJSktMTU5PUA"

    /// The 43-character output for `Test@Example.COM` / `correct horse battery staple`,
    /// cross-verified against the web client, CommonCrypto and Python.
    static let derivedKeyForTestVector = "vDKY7nW_Ay6C6JtXqe0QC9cBRmBfrTgqxOmnxr72Kqw"

    /// All fifteen fields. `address` and `notes` are PRESENT AND NULL, which is what the
    /// contract says an unfilled optional looks like — never absent.
    ///
    /// Computed rather than stored: `[String: Any]` is not `Sendable`, so a `static let` of one
    /// is shared mutable state. Building a fresh dictionary per access costs nothing here and
    /// removes the question entirely — and it also means a test that mutates its copy cannot
    /// affect the next test.
    static var customer: [String: Any] {[
        "customer_id": "cus_A1b2C3d4E5f6",
        "business_id": "biz_A1b2C3d4E5f6",
        "display_name": "Gulf Trading WLL",
        "customer_type": "company",
        "email": "accounts@gulftrading.bh",
        "phone": "+973 1700 0000",
        "country": "BH",
        "address": NSNull(),
        "notes": NSNull(),
        "status": "active",
        "deletion_scheduled_at": NSNull(),
        // No fractional seconds.
        "created_at": "2026-08-01T09:15:00Z",
        "created_by_principal_id": "prn_A1b2C3d4E5f6",
        // With fractional seconds. Both forms are legal in the contract pattern and both must
        // parse, which is why the two timestamps here deliberately differ in shape.
        "updated_at": "2026-09-01T11:02:31.482Z",
        "updated_by_principal_id": "prn_A1b2C3d4E5f6",
    ]}

    /// The list projection: no `address`, no `notes`. That exclusion is why `list` is a separate
    /// permission from `read`, so the stub must not quietly include them.
    static var customerSummary: [String: Any] {
        let keys = [
            "customer_id", "business_id", "display_name", "customer_type",
            "email", "phone", "country", "status", "deletion_scheduled_at", "updated_at",
        ]
        return keys.reduce(into: [:]) { $0[$1] = customer[$1] }
    }

    static func page(_ rows: [[String: Any]], nextCursor: String? = nil) -> [String: Any] {
        ["data": rows, "next_cursor": nextCursor as Any? ?? NSNull()]
    }

    static func errorEnvelope(
        _ code: String,
        details: [[String: String]]? = nil,
        retryAfterSeconds: Int? = nil
    ) -> [String: Any] {
        var error: [String: Any] = [
            "code": code,
            "message": "fixed developer-facing message",
            "request_id": "req_ABCDEFGH12345678901234",
        ]
        if let details { error["details"] = details }
        if let retryAfterSeconds { error["retry_after_seconds"] = retryAfterSeconds }
        return ["error": error]
    }
}
