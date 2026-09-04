import Foundation
import Testing
@testable import Dudo

/// The HTTP transport, end to end, against `StubCore`.
///
/// ===========================================================================================
/// `.serialized` IS REQUIRED, NOT A PREFERENCE
/// ===========================================================================================
///
/// `StubCore`'s route table and request log are static, because `URLProtocol` instances are
/// created by Foundation and there is nowhere else for them to live. Swift Testing runs tests in
/// parallel by default, and parallel tests sharing one route table would interleave routes and
/// produce failures that depend on scheduling — the worst kind of flake, because it discredits
/// the suite rather than the code.
@Suite("Transport", .serialized)
struct TransportTests {

    private let base = URL(string: "https://stub.dudo.invalid")!

    private func makeClient() -> DudoHTTPClient {
        StubCore.reset()
        return DudoHTTPClient(baseURL: base, protocolClasses: [StubCore.self])!
    }

    /// Records every `unauthenticated` the client reports as a session ending, so a test can
    /// assert not only that it fired but that it fired exactly once and for the right reason.
    private final class SessionEndings: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func record() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: - Reachability

    @Test("platform.health answers without a credential")
    func healthIsReachable() async throws {
        let client = makeClient()
        StubCore.route("GET", "/health", .json(200, ["status": "ok"]))
        #expect(await client.isReachable())
        // `#require`, NOT `lastRequest(...)?.authorization == nil`. Optional chaining on an
        // ABSENT request yields nil, so the weaker form passes when the client never called this
        // path at all — an assertion about a credential that examines no request. `#require`
        // fails instead, which is the whole point of asserting it.
        let sent = try #require(StubCore.lastRequest("GET", "/health"))
        #expect(sent.authorization == nil)
    }

    // MARK: - Login

    @Test("Login sends email and derived_key, and nothing else")
    func loginSendsTheContractedFields() async throws {
        let client = makeClient()
        StubCore.route("POST", "/auth/login/complete") { _ in
            .json(200, ["status": "ok"], headers: [
                "Set-Cookie":
                    "dudo_session=\(StubBodies.sessionCredential); Max-Age=43200; Path=/; "
                    + "HttpOnly; Secure; SameSite=Lax",
            ])
        }

        let credential = try await IdentityService(client: client).completeLogin(
            email: "test@example.com",
            derivedKey: StubBodies.derivedKeyForTestVector
        )
        #expect(credential.value == StubBodies.sessionCredential)

        let sent = try #require(StubCore.lastRequest("POST", "/auth/login/complete"))
        #expect(sent.body?["email"] as? String == "test@example.com")
        #expect(sent.body?["derived_key"] as? String == StubBodies.derivedKeyForTestVector)
        // THE FIELD SET IS EXACTLY TWO. Core rejects unknown fields, so anything extra here
        // would be a rejected login rather than a tolerated one.
        #expect(sent.body?.keys.sorted() == ["derived_key", "email"])
        // A pre-authentication request carries no credential.
        #expect(sent.authorization == nil)
    }

    /// A 401 from the LOGIN endpoint means the credential was wrong. Routing it through the
    /// session-ended path would sign the user out of a session they never had.
    @Test("A refused login does not clear a session")
    func refusedLoginDoesNotEndASession() async {
        let client = makeClient()
        let endings = SessionEndings()
        client.onUnauthenticated = { endings.record() }
        StubCore.route("POST", "/auth/login/complete",
                       .json(401, StubBodies.errorEnvelope("unauthenticated")))

        await #expect(throws: CustomerDirectoryError.unauthenticated) {
            try await IdentityService(client: client).completeLogin(
                email: "test@example.com", derivedKey: StubBodies.derivedKeyForTestVector)
        }
        #expect(endings.count == 0)
    }

    /// Dudo always sends exactly one `Set-Cookie` on `issued`, so a 200 without one means
    /// something between the app and Core stripped the header — a proxy or a corporate tunnel.
    /// The credential was probably correct, so telling the person to re-type their password
    /// would waste their time.
    @Test("A 200 with no credential is unavailable, not unauthenticated")
    func missingCookieIsUnavailable() async {
        let client = makeClient()
        StubCore.route("POST", "/auth/login/complete", .json(200, ["status": "ok"]))

        await #expect(throws: CustomerDirectoryError.unavailable) {
            try await IdentityService(client: client).completeLogin(
                email: "test@example.com", derivedKey: StubBodies.derivedKeyForTestVector)
        }
    }

    // MARK: - Logout

    /// `docs/decisions/0018` §A. Before it, revocation parsed `Cookie` only — so this client,
    /// which keeps no cookie jar, presented nothing, reached the handler, and was told success
    /// while nothing was revoked. These expectations are what would catch that returning.
    @Test("Revocation presents Bearer, exactly one carrier, and no body")
    func revocationPresentsBearerOnly() async throws {
        let client = makeClient()
        StubCore.route("POST", "/auth/session/revoke", .json(200, ["status": "ok"], headers: [
            // The clearing cookie that `cleared` renders. This client ignores it — the
            // credential's only home is the Keychain — but the stub sends it because Core does.
            "Set-Cookie": "dudo_session=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax",
        ]))

        await IdentityService(client: client)
            .revokeSession(credential: StubBodies.sessionCredential)

        let sent = try #require(StubCore.lastRequest("POST", "/auth/session/revoke"))
        #expect(sent.authorization == "Bearer \(StubBodies.sessionCredential)")
        // ONE CARRIER. A cookie and a header that disagree is a confusion attack, and Core
        // answers it by revoking nothing while returning the identical body — undetectably.
        #expect(sent.cookie == nil)
        // `revokeHandler` declares `fields: []`, so any field would be rejected. There must never
        // be a `session_id` field: a logout taking an identifier from the body would let an
        // unauthenticated caller delete any session it could name.
        #expect(sent.body == nil)
    }

    /// The local credential must be gone whatever the server did. Revocation is collapsed, so a
    /// silent failure — the daily write ceiling being the likeliest — is indistinguishable from
    /// success, and conditioning anything on that answer would be trusting an answer that carries
    /// no information.
    @Test("A failed revocation is swallowed rather than surfaced")
    func failedRevocationIsSwallowed() async {
        let client = makeClient()
        StubCore.route("POST", "/auth/session/revoke",
                       .init(status: 0, body: Data(), failure: URLError(.cannotConnectToHost)))

        // Does not throw. The user is already back at the sign-in screen and the local credential
        // is already destroyed; "sign-out failed" would be alarming and untrue.
        await IdentityService(client: client)
            .revokeSession(credential: StubBodies.sessionCredential)
        #expect(StubCore.lastRequest("POST", "/auth/session/revoke") != nil)
    }

    /// A `401` means the session is already gone. Revoking would spend 3 row-writes deleting a row
    /// that is not there, out of a control-plane budget where a full login-and-logout cycle costs
    /// 6 — roughly 500 cycles a day platform-wide and 100 per principal.
    @Test("An expired session neither retries nor revokes")
    func expiredSessionNeitherRetriesNorRevokes() async {
        let client = makeClient()
        client.sessionCredential = "sess_stale.AAAAAAAAAAAAAAAAAAAAAA"
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(401, StubBodies.errorEnvelope("unauthenticated")))

        await #expect(throws: CustomerDirectoryError.unauthenticated) {
            try await HTTPCustomerDirectoryRepository(client: client)
                .listCustomers(ListCustomersInput())
        }
        // Exactly one request: no retry loop, and no revocation of a session that is already gone.
        #expect(StubCore.requests.count == 1)
        #expect(StubCore.lastRequest("POST", "/auth/session/revoke") == nil)
    }

    // MARK: - Presenting the credential

    @Test("Actions present the credential as Authorization: Bearer and send no cookie")
    func actionsUseBearer() async throws {
        let client = makeClient()
        client.sessionCredential = StubBodies.sessionCredential
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(200, StubBodies.page([StubBodies.customerSummary])))

        _ = try await HTTPCustomerDirectoryRepository(client: client)
            .listCustomers(ListCustomersInput())

        let sent = try #require(StubCore.lastRequest("GET", "/api/v1/apps/customers/customers"))
        #expect(sent.authorization == "Bearer \(StubBodies.sessionCredential)")
        // THE COOKIE STORE IS DISABLED, so no `Cookie` header is ever produced. Core refuses a
        // request presenting a cookie and a header with different values as a confusion attack;
        // with the store off, this client cannot build that request even by accident.
        #expect(sent.cookie == nil)
    }

    /// A missing credential is answered locally. An anonymous request would come back
    /// `unauthenticated` and be indistinguishable from an expired session, after a pointless
    /// round trip.
    @Test("An Action with no credential refuses without sending anything")
    func missingCredentialRefusesLocally() async {
        let client = makeClient()
        let endings = SessionEndings()
        client.onUnauthenticated = { endings.record() }

        await #expect(throws: CustomerDirectoryError.unauthenticated) {
            try await HTTPCustomerDirectoryRepository(client: client)
                .listCustomers(ListCustomersInput())
        }
        #expect(StubCore.requests.isEmpty)
        #expect(endings.count == 0)
    }

    @Test("A 401 on an Action ends the session, exactly once")
    func unauthenticatedActionEndsTheSession() async {
        let client = makeClient()
        let endings = SessionEndings()
        client.onUnauthenticated = { endings.record() }
        client.sessionCredential = "sess_stale.AAAAAAAAAAAAAAAAAAAAAA"
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(401, StubBodies.errorEnvelope("unauthenticated")))

        await #expect(throws: CustomerDirectoryError.unauthenticated) {
            try await HTTPCustomerDirectoryRepository(client: client)
                .listCustomers(ListCustomersInput())
        }
        #expect(endings.count == 1)
    }

    // MARK: - Reads

    @Test("A page decodes, and a null next_cursor becomes nil")
    func listDecodes() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(200, StubBodies.page([StubBodies.customerSummary])))

        let page = try await repository.listCustomers(ListCustomersInput())
        #expect(page.data.count == 1)
        #expect(page.nextCursor == nil)
        #expect(page.data.first?.displayName == "Gulf Trading WLL")
    }

    @Test("List sends the contract's query parameters")
    func listSendsQueryParameters() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(200, StubBodies.page([])))

        _ = try await repository.listCustomers(
            ListCustomersInput(businessID: "biz_A1b2C3d4E5f6", status: .archived,
                               pageSize: 50, cursor: "abc")
        )
        let sent = try #require(StubCore.lastRequest("GET", "/api/v1/apps/customers/customers"))
        #expect(sent.query["status"] == "archived")
        #expect(sent.query["page_size"] == "50")
        #expect(sent.query["business_id"] == "biz_A1b2C3d4E5f6")
        #expect(sent.query["cursor"] == "abc")
    }

    /// Both timestamp forms in the contract's pattern must parse — fractional seconds are
    /// OPTIONAL, so a parser handling only one would reject valid server output. The stub's
    /// `created_at` has none and its `updated_at` has them, deliberately.
    @Test("Both RFC 3339 timestamp forms parse, and a present-null optional becomes nil")
    func fullRecordDecodes() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6",
                       .json(200, StubBodies.customer))

        let customer = try await repository.getCustomer(customerID: "cus_A1b2C3d4E5f6")
        #expect(customer.displayName == "Gulf Trading WLL")
        #expect(customer.address == nil)
        #expect(customer.notes == nil)
        #expect(customer.deletionScheduledAt == nil)
        #expect(customer.createdAt.timeIntervalSince1970 > 0)
        #expect(customer.updatedAt.timeIntervalSince1970 > 0)
        #expect(customer.createdAt != customer.updatedAt)
    }

    @Test("Search sends its query and hits the search sub-resource")
    func searchSendsQuery() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers/search",
                       .json(200, StubBodies.page([StubBodies.customerSummary])))

        let page = try await repository.searchCustomers(SearchCustomersInput(query: "gulf"))
        #expect(page.data.count == 1)
        let sent = try #require(
            StubCore.lastRequest("GET", "/api/v1/apps/customers/customers/search"))
        #expect(sent.query["query"] == "gulf")
    }

    // MARK: - Writes

    @Test("Create posts the contracted field set and decodes a 201")
    func createSendsAllFields() async throws {
        let repository = try signedIn()
        StubCore.route("POST", "/api/v1/apps/customers/customers",
                       .json(201, StubBodies.customer))

        _ = try await repository.createCustomer(CreateCustomerInput(
            businessID: "biz_A1b2C3d4E5f6", displayName: "Gulf Trading WLL",
            customerType: .company, email: "accounts@gulftrading.bh",
            phone: nil, country: "BH", address: nil, notes: nil))

        let sent = try #require(StubCore.lastRequest("POST", "/api/v1/apps/customers/customers"))
        #expect(sent.body?["business_id"] as? String == "biz_A1b2C3d4E5f6")
        #expect(sent.body?["customer_type"] as? String == "company")
        // An optional field may be omitted or supplied as null; both mean "not recorded". This
        // client sends the explicit null so the request says what it means.
        #expect(sent.body?["phone"] is NSNull)
        // Nothing server-controlled may be settable. These are not properties of the input
        // schema, and `additionalProperties: false` makes sending one a rejected request.
        for forbidden in ["customer_id", "status", "organization_id", "created_by_principal_id"] {
            #expect(sent.body?[forbidden] == nil, "\(forbidden) must never be sent")
        }
    }

    /// The normative three-way distinction, asserted on the bytes because that is the only place
    /// it exists: absent means unchanged, present-with-a-value means set, present-and-null means
    /// cleared. Getting it wrong is silent data loss in a customer's records.
    @Test("Update expresses unchanged, set and cleared distinctly")
    func updateExpressesTheThreeWayDistinction() async throws {
        let repository = try signedIn()
        StubCore.route("PATCH", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6",
                       .json(200, StubBodies.customer))

        var input = UpdateCustomerInput(customerID: "cus_A1b2C3d4E5f6")
        input.phone = .set("+973 1700 1111")
        input.address = .cleared
        // email, country and notes stay `.unchanged`.
        _ = try await repository.updateCustomer(input)

        let sent = try #require(
            StubCore.lastRequest("PATCH", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6"))
        #expect(sent.body?["phone"] as? String == "+973 1700 1111")
        #expect(sent.body?["address"] is NSNull)
        #expect(sent.body?.keys.sorted() == ["address", "phone"])
        // `customer_id` travels in the PATH. Core merges path, query and body and rejects the
        // request outright if a field appears twice, so sending it in both places would fail
        // every update.
        #expect(sent.body?["customer_id"] == nil)
    }

    @Test("Archive and restore are sub-resource actions carrying no body")
    func lifecycleActionsCarryNoBody() async throws {
        let repository = try signedIn()
        var archived = StubBodies.customer
        archived["status"] = "archived"
        StubCore.route("POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/archive",
                       .json(200, archived))
        StubCore.route("POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/restore",
                       .json(200, StubBodies.customer))

        #expect(try await repository.archiveCustomer(customerID: "cus_A1b2C3d4E5f6").status
                == .archived)
        #expect(try await repository.restoreCustomer(customerID: "cus_A1b2C3d4E5f6").status
                == .active)

        // `#require` on the request itself before asserting anything about its body. The previous
        // form was `lastRequest(...)?.body == nil`, which passes in TWO ways: the body was empty
        // as intended, OR THE REQUEST WAS NEVER FOUND — a client that changed its path would have
        // kept this green while sending whatever it liked. Same defect class as the httpBody /
        // httpBodyStream finding that `StubCore.bodyObject(of:)` exists to close: an assertion
        // that passes by examining nothing.
        let archive = try #require(StubCore.lastRequest(
            "POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/archive"))
        #expect(archive.body == nil)

        // RESTORE WAS NOT CHECKED AT ALL, despite this test's name naming both. A sub-resource
        // action that quietly started sending a body would have been caught on archive and missed
        // on restore.
        let restore = try #require(StubCore.lastRequest(
            "POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/restore"))
        #expect(restore.body == nil)
    }

    @Test("Move sends only business_id")
    func moveSendsOnlyTheBusiness() async throws {
        let repository = try signedIn()
        var moved = StubBodies.customer
        moved["business_id"] = "biz_ZZZZZZZZZZZZ"
        StubCore.route("POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/move",
                       .json(200, moved))

        let result = try await repository.moveCustomerToBusiness(
            customerID: "cus_A1b2C3d4E5f6", businessID: "biz_ZZZZZZZZZZZZ")
        #expect(result.businessID == "biz_ZZZZZZZZZZZZ")
        let sent = try #require(StubCore.lastRequest(
            "POST", "/api/v1/apps/customers/customers/cus_A1b2C3d4E5f6/move"))
        #expect(sent.body?.keys.sorted() == ["business_id"])
    }

    // MARK: - Errors

    @Test("invalid_argument carries field issues through to the form")
    func invalidArgumentCarriesDetails() async throws {
        let repository = try signedIn()
        StubCore.route("POST", "/api/v1/apps/customers/customers", .json(400,
            StubBodies.errorEnvelope("invalid_argument",
                details: [["field": "display_name", "issue": "must_not_be_blank"]])))

        do {
            _ = try await repository.createCustomer(CreateCustomerInput(
                businessID: "b", displayName: "", customerType: .person,
                email: nil, phone: nil, country: nil, address: nil, notes: nil))
            Issue.record("expected invalid_argument")
        } catch let error as CustomerDirectoryError {
            #expect(error.fieldIssues
                    == [FieldIssue(field: "display_name", issue: "must_not_be_blank")])
        }
    }

    @Test("rate_limited surfaces retry_after_seconds as a human message")
    func rateLimitedIsHuman() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers", .json(429,
            StubBodies.errorEnvelope("rate_limited", retryAfterSeconds: 37),
            headers: ["Retry-After": "37"]))

        do {
            _ = try await repository.listCustomers(ListCustomersInput())
            Issue.record("expected rate_limited")
        } catch let error as CustomerDirectoryError {
            #expect(error == .rateLimited(retryAfterSeconds: 37))
            #expect(error.recoverySuggestion == "Try again in about 37 seconds.")
        }
    }

    /// The platform's daily write ceilings produce values in the tens of thousands, because
    /// `retry_after_seconds` counts down to the next 00:00 UTC reset. "Try again in about 61200
    /// seconds" is arithmetic homework handed to someone trying to add a customer.
    @Test("quota_exceeded rounds a large retry to a usable unit")
    func quotaExceededIsHuman() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers", .json(429,
            StubBodies.errorEnvelope("quota_exceeded", retryAfterSeconds: 61_200)))

        do {
            _ = try await repository.listCustomers(ListCustomersInput())
            Issue.record("expected quota_exceeded")
        } catch let error as CustomerDirectoryError {
            #expect(error == .quotaExceeded(retryAfterSeconds: 61_200))
            #expect(error.recoverySuggestion == "Try again in about 17 hours.")
            #expect(error.errorDescription == "Today's limit has been reached.")
        }
    }

    /// The envelope is authoritative; the header is derived from it. When the envelope carries
    /// no number but the header does, using the header beats telling someone "try again later"
    /// with no "when".
    @Test("The Retry-After header is used when the envelope omits the field")
    func retryAfterHeaderIsAFallback() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers", .json(429,
            StubBodies.errorEnvelope("rate_limited"), headers: ["Retry-After": "45"]))

        do {
            _ = try await repository.listCustomers(ListCustomersInput())
            Issue.record("expected rate_limited")
        } catch let error as CustomerDirectoryError {
            #expect(error == .rateLimited(retryAfterSeconds: 45))
        }
    }

    @Test("Every code in the closed taxonomy maps to a case with a user-facing message")
    func everyErrorCodeMaps() async throws {
        let expected: [(String, Int, CustomerDirectoryError)] = [
            ("forbidden", 403, .forbidden),
            ("not_found", 404, .notFound),
            ("conflict", 409, .conflict),
            ("failed_precondition", 412, .failedPrecondition),
            ("internal", 500, .internalFailure),
            ("not_implemented", 501, .notImplemented),
            ("unavailable", 503, .unavailable),
            ("timeout", 504, .timeout),
        ]
        for (code, status, expectedError) in expected {
            let repository = try signedIn()
            StubCore.route("GET", "/api/v1/apps/customers/customers",
                           .json(status, StubBodies.errorEnvelope(code)))
            do {
                _ = try await repository.listCustomers(ListCustomersInput())
                Issue.record("expected \(code)")
            } catch let error as CustomerDirectoryError {
                #expect(error == expectedError)
                #expect(error.code == code)
                #expect(error.errorDescription != nil)
            }
        }
    }

    /// A body that is not an envelope means something other than Dudo answered — a proxy, a
    /// captive portal, or the wrong address. The status is mapped anyway, so a 401 from a proxy
    /// still returns the user to sign-in rather than leaving them at a failure they cannot act on.
    @Test("A non-envelope body falls back to the status code")
    func nonEnvelopeBodyFallsBackToStatus() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .init(status: 403, body: Data("<html>Forbidden</html>".utf8)))

        await #expect(throws: CustomerDirectoryError.forbidden) {
            try await repository.listCustomers(ListCustomersInput())
        }
    }

    /// A connection that never reached Dudo is `unavailable`, not `internal`. The distinction is
    /// the one a person acts on: "try again in a moment" is true when the dev server is not
    /// running, whereas "something went wrong at our end" blames a server never contacted.
    @Test("An unreachable server is unavailable, not internal")
    func unreachableServerIsUnavailable() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .init(status: 0, body: Data(),
                             failure: URLError(.cannotConnectToHost)))

        await #expect(throws: CustomerDirectoryError.unavailable) {
            try await repository.listCustomers(ListCustomersInput())
        }
    }

    @Test("A 2xx whose body does not match the contract is an internal failure")
    func undecodableSuccessIsInternal() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/apps/customers/customers",
                       .json(200, ["unexpected": true]))

        await #expect(throws: CustomerDirectoryError.internalFailure) {
            try await repository.listCustomers(ListCustomersInput())
        }
    }

    // MARK: - Businesses

    /// `display_name` is ALWAYS null today — `migrations/0002_business.sql` defines the business
    /// table as exactly `(tenant_id, business_id)` and declined a name column. Showing the
    /// identifier is the honest rendering of an opaque value, not a fallback for a bug.
    @Test("Authorized businesses decode, and a null name falls back to the identifier")
    func businessesDecode() async throws {
        let repository = try signedIn()
        StubCore.route("GET", "/api/v1/businesses", .json(200, StubBodies.page([
            ["business_id": "biz_A1b2C3d4E5f6", "display_name": NSNull()],
        ])))

        let businesses = try await repository.authorizedBusinesses()
        #expect(businesses.count == 1)
        #expect(businesses.first?.name == nil)
        #expect(businesses.first?.displayLabel == "biz_A1b2C3d4E5f6")
    }

    // MARK: - Helper

    private func signedIn() throws -> HTTPCustomerDirectoryRepository {
        let client = makeClient()
        client.sessionCredential = StubBodies.sessionCredential
        return HTTPCustomerDirectoryRepository(client: client)
    }
}
