import Foundation

/// One field-level complaint from the error envelope's `details` array.
///
/// It names the offending field in wire form and a stable machine token — never the rejected
/// value. That restriction is a disclosure control on the server, and this client honours it
/// by never echoing a value back into an error string either.
nonisolated struct FieldIssue: Hashable, Sendable, Codable {
    /// The request field, snake_case, as it appears on the wire.
    let field: String
    /// A stable machine token, for example `must_not_be_blank`.
    let issue: String
}

/// The closed error taxonomy from `urn:dudo:schema:error-envelope:1`.
///
/// An Action declares the subset it may return; anything outside that subset is a defect in
/// the Action, not a new code. `notImplemented` is included because the taxonomy contains it
/// — DeleteCustomer and RestoreDeletedCustomer answer it — and this client must be able to
/// recognise the answer even though it never asks the question.
nonisolated enum CustomerDirectoryError: Error, Hashable, Sendable {
    case invalidArgument(details: [FieldIssue])
    case unauthenticated
    case forbidden
    case notFound
    case conflict
    case failedPrecondition
    case rateLimited(retryAfterSeconds: Int?)
    case quotaExceeded(retryAfterSeconds: Int?)
    case internalFailure
    case notImplemented
    case unavailable
    case timeout

    /// The wire code, kept so that log-free diagnostics and future tests can name the case.
    var code: String {
        switch self {
        case .invalidArgument: "invalid_argument"
        case .unauthenticated: "unauthenticated"
        case .forbidden: "forbidden"
        case .notFound: "not_found"
        case .conflict: "conflict"
        case .failedPrecondition: "failed_precondition"
        case .rateLimited: "rate_limited"
        case .quotaExceeded: "quota_exceeded"
        case .internalFailure: "internal"
        case .notImplemented: "not_implemented"
        case .unavailable: "unavailable"
        case .timeout: "timeout"
        }
    }
}

nonisolated extension CustomerDirectoryError: LocalizedError {
    /// What a person is told.
    ///
    /// The server's `message` is written for a developer and is deliberately fixed and
    /// data-free; it is not fit to show to a user. These strings are the client's own, they
    /// carry no record data, and they say what to do next rather than restating the code.
    var errorDescription: String? {
        switch self {
        case .invalidArgument:
            "Some details need correcting."
        case .unauthenticated:
            "Your session has ended. Sign in again to continue."
        case .forbidden:
            "You do not have access to this."
        case .notFound:
            "This customer is no longer available."
        case .conflict:
            "That request conflicts with one already in progress."
        case .failedPrecondition:
            "This customer is not in a state that allows that."
        case .rateLimited:
            "Too many requests. Wait a moment and try again."
        case .quotaExceeded:
            "Today's limit has been reached."
        case .internalFailure:
            "Something went wrong at our end."
        case .notImplemented:
            "That is not available yet."
        case .unavailable:
            "Dudo is temporarily unavailable."
        case .timeout:
            "That took too long to complete."
        }
    }

    /// The second line — the recovery, where there is one.
    var recoverySuggestion: String? {
        switch self {
        case .invalidArgument: "Check the highlighted fields."
        case .failedPrecondition: "Refresh the directory and try again."
        case .notFound: "It may have been removed. Refresh the directory."
        case .rateLimited(let seconds), .quotaExceeded(let seconds):
            seconds.map { "Try again in about \($0) seconds." }
        case .internalFailure, .unavailable, .timeout: "Try again in a moment."
        default: nil
        }
    }

    /// A symbol for the failure state. Neutral rather than alarming: most of these are
    /// transient and none of them are the user's fault.
    var symbolName: String {
        switch self {
        case .invalidArgument: "exclamationmark.circle"
        case .unauthenticated, .forbidden: "lock"
        case .notFound: "questionmark.folder"
        case .rateLimited, .quotaExceeded: "hourglass"
        case .timeout: "clock.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }

    /// The field issues, for a form to attach to its own fields.
    var fieldIssues: [FieldIssue] {
        if case .invalidArgument(let details) = self { return details }
        return []
    }
}

nonisolated extension Error {
    /// Presents any error as a directory error, so the UI has exactly one failure vocabulary.
    /// An unrecognised error becomes `internal` rather than leaking a framework description
    /// into the interface.
    var asCustomerDirectoryError: CustomerDirectoryError {
        (self as? CustomerDirectoryError) ?? .internalFailure
    }
}
