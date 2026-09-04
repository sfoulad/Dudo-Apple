import Foundation

/// The one error shape every Dudo API returns, from
/// `packages/contracts/common/error-envelope.schema.json` (`urn:dudo:schema:error-envelope:1`).
///
/// ===========================================================================================
/// WHAT THIS CLIENT MAY AND MAY NOT DO WITH EACH FIELD
/// ===========================================================================================
///
///   `code`                 The closed taxonomy. This is what the interface reacts to.
///   `message`              WRITTEN FOR A DEVELOPER AND NEVER SHOWN TO A USER. The schema is
///                          explicit that it is a fixed, data-free string chosen so it cannot
///                          become a disclosure channel; it is not written to be read by a
///                          person running a business. `CustomerDirectoryError` carries this
///                          client's own wording instead.
///   `request_id`           The ONLY identifier an error carries — no tenant id, no record id.
///                          It is what makes a support conversation possible without asking a
///                          customer to share their data, so it is kept and shown in the one
///                          place a person would need it, and nowhere else.
///   `details`              Field and stable token. Never the rejected value, and this client
///                          never echoes one back into an error string either.
///   `retry_after_seconds`  PRESENT ONLY on `rate_limited` and `quota_exceeded`, absent
///                          everywhere else — enforced structurally by the schema. Derived from
///                          a fixed window boundary, so it is the same number for every caller
///                          on the platform at that instant and discloses nothing.
nonisolated struct ErrorEnvelope: Decodable, Sendable {

    struct Payload: Decodable, Sendable {
        let code: String
        let message: String
        let requestID: String
        let details: [FieldIssue]?
        let retryAfterSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case requestID = "request_id"
            case details
            case retryAfterSeconds = "retry_after_seconds"
        }
    }

    let error: Payload

    /// Maps the wire code onto this client's failure vocabulary.
    ///
    /// AN UNRECOGNISED CODE BECOMES `internal`. The taxonomy is closed, so a code outside it is
    /// a defect in the Action rather than a new case to accommodate — but a client that
    /// *crashed* on one, or that showed the raw token to a user, would turn a server defect into
    /// a worse client defect.
    func asDirectoryError() -> CustomerDirectoryError {
        switch error.code {
        case "invalid_argument": .invalidArgument(details: error.details ?? [])
        case "unauthenticated": .unauthenticated
        case "forbidden": .forbidden
        case "not_found": .notFound
        case "conflict": .conflict
        case "failed_precondition": .failedPrecondition
        case "rate_limited": .rateLimited(retryAfterSeconds: error.retryAfterSeconds)
        case "quota_exceeded": .quotaExceeded(retryAfterSeconds: error.retryAfterSeconds)
        case "not_implemented": .notImplemented
        case "unavailable": .unavailable
        case "timeout": .timeout
        default: .internalFailure
        }
    }
}

// MARK: - Falling back when there is no envelope

nonisolated enum TransportFailureMapping {

    /// The error to raise when a response could not be understood as an envelope at all.
    ///
    /// ===========================================================================================
    /// THE STATUS CODE IS A FALLBACK AND NOT THE SOURCE OF TRUTH, AND THE ORDER MATTERS
    /// ===========================================================================================
    ///
    /// Dudo's envelope is the authoritative statement of what went wrong; the status code is a
    /// derived rendering of it. This path is reached only when the body is missing, empty, or
    /// not the envelope — which in practice means something that is NOT Dudo answered: a proxy,
    /// a captive portal, a tunnel, or the wrong address entirely.
    ///
    /// Mapping the status anyway is still worth doing, because a 401 from a proxy and a 401 from
    /// Dudo should both send the user back to sign in rather than leaving them looking at a
    /// generic failure they cannot act on.
    static func fromStatusCode(_ status: Int, retryAfterHeader: Int?) -> CustomerDirectoryError {
        switch status {
        case 400: .invalidArgument(details: [])
        case 401: .unauthenticated
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 412, 422: .failedPrecondition
        case 429: .rateLimited(retryAfterSeconds: retryAfterHeader)
        case 501: .notImplemented
        case 503: .unavailable
        case 504: .timeout
        default: .internalFailure
        }
    }

    /// Maps a `URLError` onto the same vocabulary the rest of the interface speaks.
    ///
    /// A CONNECTION THAT NEVER REACHED DUDO IS `unavailable`, NOT `internal`. The distinction is
    /// the one a person acts on: "Dudo is temporarily unavailable, try again in a moment" is
    /// true and useful when the laptop is offline or the dev server is not running, whereas
    /// "something went wrong at our end" points the blame at a server that was never contacted.
    static func fromURLError(_ error: URLError) -> CustomerDirectoryError {
        switch error.code {
        case .timedOut:
            .timeout
        case .cancelled:
            // Surfaced only if a caller fails to treat cancellation as cancellation. It is not
            // a failure and the interface should never show it.
            .unavailable
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
             .dataNotAllowed, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
            .unavailable
        default:
            .unavailable
        }
    }
}
