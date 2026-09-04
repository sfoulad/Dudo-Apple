import Foundation

/// The field rules from `customer-directory-v1.schema.json`, applied in the interface so
/// that a person is told about a problem while they are typing rather than after a round
/// trip.
///
/// THIS IS PRESENTATION, NOT ENFORCEMENT. Core validates every one of these again on every
/// call and its answer is the only one that counts. Client-side validation exists to make the
/// form pleasant; it is never the reason a bad value does not reach storage. The rules are
/// mirrored exactly rather than approximated, because a client that is *stricter* than the
/// contract rejects values the web client accepts, and that divergence is a defect just as
/// surely as being laxer would be.
nonisolated enum CustomerFieldRules {

    // MARK: display_name

    static let displayNameMaxLength = 200

    /// Required. Trimmed by the server before storage and before matching; a value that is
    /// empty after trimming is `invalid_argument`.
    static func validateDisplayName(_ raw: String) -> FieldIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FieldIssue(field: "display_name", issue: "must_not_be_blank")
        }
        if trimmed.count > displayNameMaxLength {
            return FieldIssue(field: "display_name", issue: "too_long")
        }
        return nil
    }

    // MARK: email

    static let emailMinLength = 3
    static let emailMaxLength = 254

    /// Optional. The pattern is deliberately permissive: it rejects the obviously malformed
    /// and nothing else. Dudo does not validate RFC 5322, does not check that the domain
    /// resolves, and does not check deliverability — and this client must not imply that it
    /// does. Uniqueness is not enforced; two customers may legitimately share an address.
    static func validateEmail(_ raw: String) -> FieldIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count < emailMinLength || trimmed.count > emailMaxLength {
            return FieldIssue(field: "email", issue: "out_of_range")
        }
        // ^[^@\s]+@[^@\s]+\.[^@\s]+$
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let local = parts.first, let domain = parts.last,
              !local.isEmpty, !domain.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              domain.contains("."),
              !domain.hasPrefix("."), !domain.hasSuffix(".")
        else {
            return FieldIssue(field: "email", issue: "malformed")
        }
        return nil
    }

    // MARK: phone

    static let phoneMinLength = 3
    static let phoneMaxLength = 32
    /// Digits, plus, parentheses, hyphen, dot, space. Nothing else.
    private static let phoneCharacters = CharacterSet(charactersIn: "0123456789+()-. ")

    /// Optional. E.164 is NOT required, deliberately — requiring it would reject the majority
    /// of real imported directory data on the first day. The consequence is stated rather
    /// than hidden: **this field is not dial-safe**, and no part of this app may assume it
    /// parses into a callable number. That is why the detail screen offers copy rather than
    /// a `tel:` link.
    static func validatePhone(_ raw: String) -> FieldIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count < phoneMinLength || trimmed.count > phoneMaxLength {
            return FieldIssue(field: "phone", issue: "out_of_range")
        }
        if trimmed.unicodeScalars.contains(where: { !phoneCharacters.contains($0) }) {
            return FieldIssue(field: "phone", issue: "unsupported_character")
        }
        // At least three digits somewhere in the value: "()-" is well-formed against the
        // character set and is not a phone number.
        if trimmed.filter(\.isNumber).count < 3 {
            return FieldIssue(field: "phone", issue: "too_few_digits")
        }
        return nil
    }

    // MARK: country

    /// Optional. ISO 3166-1 alpha-2, uppercase. WELL-FORMEDNESS ONLY — no code list is
    /// validated against, so a well-formed but unassigned code such as `ZZ` is accepted and
    /// stored. This client therefore offers a free-text field with suggestions rather than a
    /// closed picker: a picker would reject values the web client accepts.
    static func validateCountry(_ raw: String) -> FieldIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isTwoUppercaseLetters = trimmed.count == 2
            && trimmed.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter }
        return isTwoUppercaseLetters ? nil : FieldIssue(field: "country", issue: "malformed")
    }

    /// The country name for a code, where the system knows one. Falls back to the code
    /// itself, which is the honest answer for an unassigned but well-formed value.
    static func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    // MARK: address

    static let addressMaxLength = 500

    /// Optional. A single free-text value, newlines permitted. Unstructured by decision.
    static func validateAddress(_ raw: String) -> FieldIssue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > addressMaxLength
            ? FieldIssue(field: "address", issue: "too_long")
            : nil
    }

    // MARK: notes

    static let notesMaxLength = 2_000

    /// Optional. Free text, and therefore classified at the highest class it can hold.
    /// Deliberately NOT searchable.
    static func validateNotes(_ raw: String) -> FieldIssue? {
        raw.count > notesMaxLength
            ? FieldIssue(field: "notes", issue: "too_long")
            : nil
    }

    // MARK: query

    static let queryMinLength = 2
    static let queryMaxLength = 128

    /// The search term, trimmed. A one-character query matches a large fraction of any
    /// directory and costs a scan to say so, so the contract sets a floor of two and this
    /// client does not send below it.
    static func normalisedQueryIfSendable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= queryMinLength else { return nil }
        return String(trimmed.prefix(queryMaxLength))
    }

    // MARK: helpers

    /// Turns a text field into the value that goes on the wire: trimmed, and `nil` when
    /// empty. An optional field may be omitted or supplied as null; both mean "not recorded".
    static func optionalValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Human-readable field problems

nonisolated extension FieldIssue {
    /// The message shown under a field. Keyed on the stable token, never on a server
    /// sentence, so a wording change on either side cannot desynchronise the two.
    var message: String {
        switch (field, issue) {
        case ("display_name", "must_not_be_blank"): "A name is required."
        case ("display_name", "too_long"):
            "Keep this to \(CustomerFieldRules.displayNameMaxLength) characters."
        case ("email", "malformed"): "That does not look like an email address."
        case ("email", "out_of_range"):
            "An email address can be up to \(CustomerFieldRules.emailMaxLength) characters."
        case ("phone", "unsupported_character"):
            "Use digits and + ( ) - . only."
        case ("phone", "too_few_digits"): "A phone number needs at least three digits."
        case ("phone", "out_of_range"):
            "A phone number can be up to \(CustomerFieldRules.phoneMaxLength) characters."
        case ("country", "malformed"): "Use a two-letter country code, such as BH."
        case ("address", "too_long"):
            "Keep this to \(CustomerFieldRules.addressMaxLength) characters."
        case ("notes", "too_long"):
            "Keep this to \(CustomerFieldRules.notesMaxLength) characters."
        case (_, "must_not_be_blank"): "This is required."
        default: "Check this value."
        }
    }
}
