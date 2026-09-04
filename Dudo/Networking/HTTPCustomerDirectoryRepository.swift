import Foundation

/// The Customer Directory over HTTP. The second conformer to `CustomerDirectoryRepository`,
/// beside the fixture, and NO VIEW CHANGES BECAUSE IT EXISTS — which was the point of putting a
/// protocol there before there was anything to put behind it.
///
/// ===========================================================================================
/// EVERY ROUTE HERE IS TRANSCRIBED FROM THE CONTRACT'S `httpBinding`, WHICH IS THE AUTHORED
/// SOURCE
/// ===========================================================================================
///
/// `packages/contracts/apps/customers/customer-directory-v1.contract.yaml`, base path
/// `/api/v1/apps/customers`:
///
///   POST   /customers                              CreateCustomer          201
///   GET    /customers                              ListCustomers           200
///   GET    /customers/search                       SearchCustomers         200
///   GET    /customers/{customer_id}                GetCustomer             200
///   PATCH  /customers/{customer_id}                UpdateCustomer          200
///   POST   /customers/{customer_id}/archive        ArchiveCustomer         200
///   POST   /customers/{customer_id}/restore        RestoreCustomer         200
///   POST   /customers/{customer_id}/move           MoveCustomerToBusiness  200
///
/// TWO CONTRACTED ROUTES ARE ABSENT AND THAT IS DELIBERATE. `DELETE /customers/{customer_id}`
/// and `POST /customers/{customer_id}/cancel-deletion` exist in the contract and are ruled out
/// of the MVP (§11.1) because the platform confirmation mechanism a `critical` Action requires
/// does not exist. There is no method for them on the protocol, so there is nothing here to
/// call — their absence is structural rather than a line someone remembered not to write.
///
/// ===========================================================================================
/// WHAT THIS TYPE DOES NOT DO, AND MUST NEVER START DOING
/// ===========================================================================================
///
/// It performs NO authorization, applies NO business rule, and re-implements NO validation. It
/// builds a request, sends it, and decodes the answer. Every decision — which records the caller
/// may see, whether an archive is allowed, whether a `business_id` is in scope, the
/// `not_found`/`forbidden` distinction — is Core's, and this client's job is to render whatever
/// Core says. `CustomerFieldRules` runs in the FORM as a courtesy to the person typing; it is
/// not a gate and the server validates everything again regardless.
@MainActor
final class HTTPCustomerDirectoryRepository: CustomerDirectoryRepository, BusinessReferenceProviding {

    private let client: DudoHTTPClient

    init(client: DudoHTTPClient) {
        self.client = client
    }

    // MARK: - customers.CreateCustomer

    func createCustomer(_ input: CreateCustomerInput) async throws -> Customer {
        // NO `Idempotency-Key`. The contract declares `idempotent: false`, meaning a key is
        // ACCEPTED and honoured but not REQUIRED, and it states the cost of omitting one: a
        // retried create after a network failure produces a second customer, because this
        // contract deliberately does not deduplicate on display_name or email. Minting keys is
        // its own slice of work — the key has to survive the retry to be worth anything, which
        // means persisting it — and it is not in this one. Recorded as owed. Open question CD-4.
        try await client.send(
            .init(
                method: "POST",
                path: path("/customers"),
                body: .object([
                    "business_id": .string(input.businessID),
                    "display_name": .string(input.displayName),
                    "customer_type": .string(input.customerType.rawValue),
                    "email": .optionalString(input.email),
                    "phone": .optionalString(input.phone),
                    "country": .optionalString(input.country),
                    "address": .optionalString(input.address),
                    "notes": .optionalString(input.notes),
                ]),
                authorization: .sessionCredential
            ),
            as: Customer.self
        )
    }

    // MARK: - customers.GetCustomer

    func getCustomer(customerID: String) async throws -> Customer {
        try await client.send(
            .init(
                method: "GET",
                path: path("/customers/\(customerID)"),
                authorization: .sessionCredential
            ),
            as: Customer.self
        )
    }

    // MARK: - customers.ListCustomers

    func listCustomers(_ input: ListCustomersInput) async throws -> CustomerPage {
        var query = [
            URLQueryItem(name: "status", value: input.status.rawValue),
            URLQueryItem(name: "page_size", value: String(input.pageSize)),
        ]
        if let businessID = input.businessID {
            query.append(URLQueryItem(name: "business_id", value: businessID))
        }
        if let cursor = input.cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await client.send(
            .init(
                method: "GET",
                path: path("/customers"),
                query: query,
                authorization: .sessionCredential
            ),
            as: CustomerPage.self
        )
    }

    // MARK: - customers.SearchCustomers

    func searchCustomers(_ input: SearchCustomersInput) async throws -> CustomerPage {
        // The searched fields are display_name, email and phone, fixed by the contract and NOT
        // selectable by the caller — there is no parameter here to name a field with, and that
        // is what stops a caller probing `notes`.
        var query = [
            URLQueryItem(name: "query", value: input.query),
            URLQueryItem(name: "status", value: input.status.rawValue),
            URLQueryItem(name: "page_size", value: String(input.pageSize)),
        ]
        if let businessID = input.businessID {
            query.append(URLQueryItem(name: "business_id", value: businessID))
        }
        if let cursor = input.cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await client.send(
            .init(
                method: "GET",
                path: path("/customers/search"),
                query: query,
                authorization: .sessionCredential
            ),
            as: CustomerPage.self
        )
    }

    // MARK: - customers.UpdateCustomer

    func updateCustomer(_ input: UpdateCustomerInput) async throws -> Customer {
        // THE THREE-WAY DISTINCTION IS BUILT HERE AND IT IS THE ONE PLACE IT CAN GO WRONG.
        // A key omitted means unchanged; a key with null means cleared. `jsonValueIfPresent`
        // returns nil for `.unchanged` and the loop below skips it — encoding it as a null
        // instead would clear a customer's address every time anyone edited their phone number.
        var body: [String: JSONValue] = [:]
        if let displayName = input.displayName {
            body["display_name"] = .string(displayName)
        }
        if let customerType = input.customerType {
            body["customer_type"] = .string(customerType.rawValue)
        }
        for (field, update) in [
            ("email", input.email),
            ("phone", input.phone),
            ("country", input.country),
            ("address", input.address),
            ("notes", input.notes),
        ] {
            if let value = update.jsonValueIfPresent {
                body[field] = value
            }
        }

        // `customer_id` IS NOT IN THE BODY. It arrives as a path parameter, and Core merges path,
        // query and body into one object and REJECTS the request outright if the same field
        // appears twice — `conflicting_input_sources`. Sending it in both places would fail
        // every update.
        return try await client.send(
            .init(
                method: "PATCH",
                path: path("/customers/\(input.customerID)"),
                body: .object(body),
                authorization: .sessionCredential
            ),
            as: Customer.self
        )
    }

    // MARK: - customers.ArchiveCustomer

    func archiveCustomer(customerID: String) async throws -> Customer {
        try await subResourceAction(customerID: customerID, verb: "archive", body: nil)
    }

    // MARK: - customers.RestoreCustomer

    func restoreCustomer(customerID: String) async throws -> Customer {
        try await subResourceAction(customerID: customerID, verb: "restore", body: nil)
    }

    // MARK: - customers.MoveCustomerToBusiness

    func moveCustomerToBusiness(customerID: String, businessID: String) async throws -> Customer {
        try await subResourceAction(
            customerID: customerID,
            verb: "move",
            body: .object(["business_id": .string(businessID)])
        )
    }

    /// Archive, restore and move are sub-resource actions on a record — permitted by
    /// API_STANDARD.md §5 for operations that are not CRUD-shaped — and each maps to exactly one
    /// Action. Archive and restore carry NO body: their only input is `customer_id`, which is in
    /// the path. Core reads an empty body as `{}`.
    private func subResourceAction(
        customerID: String,
        verb: String,
        body: JSONValue?
    ) async throws -> Customer {
        try await client.send(
            .init(
                method: "POST",
                path: path("/customers/\(customerID)/\(verb)"),
                body: body,
                authorization: .sessionCredential
            ),
            as: Customer.self
        )
    }

    private func path(_ suffix: String) -> String {
        DudoPath.customersBase + suffix
    }

    // MARK: - BusinessReferenceProviding

    /// `core.ListAuthorizedBusinesses` — `GET /api/v1/businesses`.
    ///
    /// THE GAP `BusinessReference.swift` WAS WRITTEN AROUND IS NOW HALF CLOSED. When that file
    /// was written no contract resolved a `business_id`; `business-read-v1` now publishes this
    /// Action, and this is the real answer to "which Businesses may this principal file a
    /// customer into". The placeholder protocol stays for the moment because replacing it is a
    /// change to shapes the views read, and that is a separate piece of work from landing a
    /// transport.
    ///
    /// `display_name` IS ALWAYS NULL TODAY and this is not a bug to chase:
    /// `migrations/0002_business.sql` defines the business table as exactly
    /// `(tenant_id, business_id)` and declined a name column, so nothing in Dudo stores a
    /// Business name until the organization-structure slice adds one. `BusinessReference`
    /// already falls back to showing the identifier, which is the honest rendering of an opaque
    /// value.
    ///
    /// `core.ResolveBusinessReferences` IS NOT CALLED. Its contracted wire form is a repeated
    /// query parameter — `?business_ids=<id>&business_ids=<id>` — and `http/api.ts` REFUSES a
    /// repeated query parameter with `invalid_argument` / `repeated_parameter`, deliberately,
    /// because a precedence rule would let a caller shadow a value a reviewer assumed was
    /// authoritative. Contract and platform disagree; that is not this client's to resolve and
    /// it has been reported. Listing gives this app what it needs meanwhile.
    func authorizedBusinesses() async throws -> [BusinessReference] {
        let page = try await client.send(
            .init(
                method: "GET",
                path: DudoPath.coreBase + "/businesses",
                query: [URLQueryItem(name: "page_size", value: String(CustomerPagination.maximumPageSize))],
                authorization: .sessionCredential
            ),
            as: BusinessPage.self
        )
        return page.data.map { BusinessReference(id: $0.businessID, name: $0.displayName) }
    }

    /// `urn:dudo:schema:business-read:1#/$defs/listAuthorizedBusinessesOutput`.
    private struct BusinessPage: Decodable {
        struct Summary: Decodable {
            let businessID: String
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case businessID = "business_id"
                case displayName = "display_name"
            }
        }

        let data: [Summary]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case data
            case nextCursor = "next_cursor"
        }
    }
}
