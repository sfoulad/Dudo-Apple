import Foundation
import CommonCrypto

// MARK: - The client-side key derivation. docs/decisions/0015 §D, Accepted 2026-09-04.
//
// THE PASSWORD NEVER LEAVES THIS DEVICE. What is posted to `identity.login.complete` is
// PBKDF2-SHA256(password, salt = normalised email, 600,000 iterations, 32 bytes), base64url
// with no padding — exactly 43 characters. The server hashes *that* again before storing it,
// so a stolen control-plane database is not a set of login credentials.
//
// ===========================================================================================
// THIS FILE MUST AGREE, BYTE FOR BYTE, WITH THE WEB CLIENT. THAT IS ITS ENTIRE POINT.
// ===========================================================================================
//
// The web client derives the same value with `crypto.subtle`; Dudo-Core's
// `platform/core/identity/credential-store.ts` normalises the identifier the same way in
// TypeScript. Three implementations, one output. A divergence does not corrupt anything — it
// fails closed, and loudly, because a user who registered on the web simply cannot sign in on
// an iPhone. That is an outage, and it is invisible until someone tries.
//
// So: every step below is written to remove a cross-language disagreement rather than to
// express a preference, and `qa-agent` binds all three with shared vectors.
//
// ===========================================================================================
// WHY THE SALT IS THE EMAIL ADDRESS, WHICH LOOKS WRONG UNTIL YOU READ WHY
// ===========================================================================================
//
// A per-user random salt would have to be fetched before the password could be hashed. There
// is no endpoint that can deliver one: `identity.login.start` is `disclosure: 'collapsed'` and
// renders one constant body for every caller, precisely so that it cannot tell an attacker
// whether an account exists. An endpoint that returned this user's salt would answer that
// question on its first response. The normalised email is therefore the salt — the
// construction Bitwarden ships — and the cost is that the salt is guessable, which matters far
// less than 600,000 iterations do.

nonisolated enum LoginSecretDerivation {

    /// OWASP's recommendation for PBKDF2-HMAC-SHA256, and the value `0015` §D fixes.
    ///
    /// IT IS NOT A TUNING KNOB. Changing it changes every derived value and locks out every
    /// enrolled user on this platform, on every client, permanently — the stored verifier was
    /// computed from an output this constant produced and there is no way to recompute it. A
    /// change here is a migration, not an edit.
    static let iterations = 600_000

    /// 32 bytes — one SHA-256 block, which is why the derivation below needs only one PBKDF2
    /// block and can therefore report honest progress. See `derive(password:salt:progress:)`.
    static let derivedKeyLength = 32

    /// base64url of 32 bytes, unpadded. The server requires exactly this width.
    static let encodedLength = 43

    // MARK: - Identifier normalisation

    /// Why a submitted identifier was refused before any hashing happened.
    ///
    /// REFUSAL IS NOT AN ACCOUNT-EXISTENCE SIGNAL and must never be presented as one. Every
    /// case here is decided by the *shape* of what was typed, which the person typing already
    /// knows. None of them consults a server, and none of them can distinguish a real address
    /// from an invented one.
    enum IdentifierRefusal: Equatable, Sendable {
        case tooShort
        case tooLong
        case containsUnsupportedCharacter
        case missingAtSign

        var message: String {
            switch self {
            case .tooShort, .missingAtSign:
                "Enter the email address you use for Dudo."
            case .tooLong:
                "That address is longer than \(maximumIdentifierLength) characters."
            case .containsUnsupportedCharacter:
                // Deliberately explicit. A person with an internationalised address is owed
                // the real reason rather than "incorrect email or password", because no
                // password they type will ever work.
                "Dudo can only sign you in with a plain-ASCII email address."
            }
        }
    }

    /// RFC 5321's cap on a path. Anything longer is not an email address, and every byte past
    /// it is hashing work an unauthenticated caller can compel from the server.
    static let maximumIdentifierLength = 254
    /// The shortest thing that can be an address at all: `a@b`.
    static let minimumIdentifierLength = 3

    /// Is this a value all three implementations will normalise identically?
    ///
    /// DELIBERATELY NOT AN EMAIL VALIDATOR. It does not decide whether an address is
    /// deliverable — nothing in Dudo sends mail. It decides one thing: whether TypeScript and
    /// Swift will agree about the normalised form.
    ///
    /// THE ASCII RESTRICTION IS THE LOAD-BEARING PART, and it is Core's rule, restated here
    /// rather than invented: `credential-store.ts` refuses anything with whitespace, a control
    /// character, or a character above U+007E. It refuses them instead of trimming them
    /// because JavaScript's `String.prototype.trim` and Swift's
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` trim *different character sets*, so a
    /// value that needs trimming is a value the implementations can disagree about. Removing
    /// the disagreement beats arbitrating it.
    ///
    /// THE COST IS STATED RATHER THAN HIDDEN: an RFC 6531 internationalised address cannot be
    /// used to sign in to Dudo at all. Punycode domains work, because they are ASCII.
    static func refusalReason(forSubmittedIdentifier value: String) -> IdentifierRefusal? {
        let units = Array(value.utf16)
        if units.count < minimumIdentifierLength { return .tooShort }
        if units.count > maximumIdentifierLength { return .tooLong }
        var hasAtSign = false
        for unit in units {
            // Printable ASCII only. 0x20 (space) is excluded along with the control range.
            if unit <= 0x20 || unit > 0x7e { return .containsUnsupportedCharacter }
            if unit == 0x40 { hasAtSign = true }
        }
        return hasAtSign ? nil : .missingAtSign
    }

    /// The normative normalisation: NFKC, then ASCII-ONLY case folding.
    ///
    /// CALL `refusalReason(forSubmittedIdentifier:)` FIRST. This function does not re-check,
    /// because a second place that decides what is acceptable is a second place the three
    /// implementations can drift apart.
    ///
    /// TWO CHOICES HERE ARE NOT PREFERENCES:
    ///
    ///   1. `precomposedStringWithCompatibilityMapping` is NFKC. Over the ASCII subset it is
    ///      the identity function, so today it costs nothing; it is applied anyway so that the
    ///      definition stays correct if a recorded decision ever relaxes the ASCII rule.
    ///   2. **NOT `lowercased()`.** Swift's `lowercased()` is full Unicode case mapping and it
    ///      differs from JavaScript's `toLowerCase()` for real characters — U+0130 LATIN
    ///      CAPITAL LETTER I WITH DOT ABOVE is the standard example. A login that works on the
    ///      web and fails on iPhone for exactly one user is a defect nobody would ever find.
    ///      Only `A`–`Z` are folded, and nothing else is touched.
    static func normalizeIdentifier(_ value: String) -> String {
        let composed = value.precomposedStringWithCompatibilityMapping
        var normalized = String.UnicodeScalarView()
        normalized.reserveCapacity(composed.unicodeScalars.count)
        for scalar in composed.unicodeScalars {
            if scalar.value >= 0x41 && scalar.value <= 0x5a,
               let folded = Unicode.Scalar(scalar.value + 32) {
                normalized.append(folded)
            } else {
                normalized.append(scalar)
            }
        }
        return String(normalized)
    }

    // MARK: - Password normalisation

    /// The password's bytes: **NFC, and nothing else.**
    ///
    /// ===========================================================================================
    /// THE PASSWORD AND THE IDENTIFIER USE DIFFERENT NORMALISATIONS, AND SHARING ONE IS A DEFECT
    /// ===========================================================================================
    ///
    ///   identifier  validate ASCII 0x21–0x7E, then **NFKC**, then ASCII-only case folding
    ///   password    **NFC**. No case folding, no trimming, no validation, no ASCII restriction.
    ///
    /// WHY NORMALISE AT ALL. A password containing any non-ASCII character can be typed in
    /// composed or decomposed form — `é` as U+00E9, or as `e` U+0065 followed by U+0301. Those
    /// are different byte sequences and they derive **different keys**. macOS input methods and
    /// iOS keyboards do not reliably agree on which form they produce, so the same person typing
    /// the same password on a Mac and on an iPhone can produce two different secrets. They would
    /// enrol on one and be locked out of the other, and it would present as a wrong password.
    ///
    /// WHY NFC AND NOT NFKC, WHICH IS THE ONE PLACE THE DIFFERENCE BITES. NFKC collapses
    /// compatibility variants — `ﬁ` to `fi`, `²` to `2`, full-width forms to ASCII. For an
    /// IDENTIFIER that is desirable: `ﬁ@x.com` and `fi@x.com` should be the same account. For a
    /// PASSWORD it is destructive: it silently merges characters the user chose deliberately and
    /// **removes entropy they believe they have**. NFC composes canonically equivalent sequences
    /// and changes nothing else, which is exactly the guarantee wanted here.
    ///
    /// This is RFC 8265's PRECIS `OpaqueString` profile — what SCRAM and SASL use for this same
    /// problem: normalise composition, never case-fold, never compatibility-map.
    ///
    /// WHAT IS DELIBERATELY NOT DONE: the password is not trimmed. A leading or trailing space is
    /// part of the password, and stripping one would make this client and the web client derive
    /// different values for the same typed characters — the very failure this function exists to
    /// prevent, reintroduced from the other direction.
    static func passwordBytes(_ password: String) -> Data {
        Data(password.precomposedStringWithCanonicalMapping.utf8)
    }

    // MARK: - Derivation

    /// The value posted as the login secret: 43 base64url characters, no padding.
    ///
    /// `progress` is called with a fraction in 0...1 as the work proceeds. It is invoked from
    /// whatever executor this function is running on, which is *not* the main actor — see the
    /// note on `derive` — so a caller updating the interface must hop back itself.
    static func deriveLoginSecret(
        email: String,
        password: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> String {
        let salt = Data(normalizeIdentifier(email).utf8)
        let derived = derive(password: passwordBytes(password), salt: salt, progress: progress)
        return base64URLUnpadded(derived)
    }

    /// PBKDF2-HMAC-SHA256, written out rather than delegated, so that progress is real.
    ///
    /// ===========================================================================================
    /// WHY THIS IS HAND-WRITTEN WHEN `CCKeyDerivationPBKDF` EXISTS
    /// ===========================================================================================
    ///
    /// `CCKeyDerivationPBKDF` is one opaque call. On the slowest supported iPhone 600,000
    /// iterations takes on the order of a second, and there is no way to observe it partway
    /// through — so the only progress a caller could show would be a spinner, or worse, a bar
    /// animated against a guessed duration. A progress bar that is not measuring anything is a
    /// lie told by the interface, and this is a screen where the user is waiting on real work.
    ///
    /// THE HAND-WRITTEN VERSION IS EXACT, NOT APPROXIMATE, AND THE REASON IS ARITHMETIC:
    /// the derived key is 32 bytes and SHA-256's output is 32 bytes, so dkLen == hLen and
    /// PBKDF2 reduces to **exactly one block**:
    ///
    ///     U₁ = HMAC-SHA256(password, salt ‖ 0x00000001)
    ///     Uᵢ = HMAC-SHA256(password, Uᵢ₋₁)
    ///     DK = U₁ ⊕ U₂ ⊕ … ⊕ U_c
    ///
    /// There is no block loop to get wrong, no counter to mis-encode beyond the single
    /// big-endian `1`, and no truncation. `LoginSecretDerivationCheck` verifies this against
    /// `CCKeyDerivationPBKDF` on the same inputs, so the equivalence is asserted by a
    /// comparison rather than by this comment.
    ///
    /// ===========================================================================================
    /// THIS IS A `nonisolated` SYNCHRONOUS FUNCTION AND IT MUST NEVER BE CALLED ON THE MAIN ACTOR
    /// ===========================================================================================
    ///
    /// It blocks for as long as the work takes. `SessionController` runs it inside a detached
    /// task for that reason. A frozen sign-in screen is not a slow login, it is a bug.
    static func derive(
        password: Data,
        salt: Data,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> Data {
        let hashLength = Int(CC_SHA256_DIGEST_LENGTH)

        // The HMAC key is the password and never changes, so the context is initialised once
        // and copied per iteration. `CCHmacInit` on a stack context is the documented way to
        // do this and it avoids re-keying 600,000 times.
        var keyedContext = CCHmacContext()
        password.withUnsafeBytes { key in
            CCHmacInit(&keyedContext, CCHmacAlgorithm(kCCHmacAlgSHA256), key.baseAddress, key.count)
        }

        func mac(_ message: UnsafeRawBufferPointer, into output: UnsafeMutableRawPointer) {
            var context = keyedContext
            CCHmacUpdate(&context, message.baseAddress, message.count)
            CCHmacFinal(&context, output)
        }

        // U₁ over salt ‖ INT_32_BE(1). The block index is 1 and only ever 1.
        var block = salt
        block.append(contentsOf: [0x00, 0x00, 0x00, 0x01])

        var current = [UInt8](repeating: 0, count: hashLength)
        block.withUnsafeBytes { message in
            current.withUnsafeMutableBytes { output in
                mac(message, into: output.baseAddress!)
            }
        }
        var accumulator = current

        // How often progress is reported. Frequent enough that a bar moves smoothly, rare
        // enough that the reporting is not a measurable share of the work.
        let reportEvery = max(1, iterations / 100)
        var next = [UInt8](repeating: 0, count: hashLength)

        for iteration in 2...iterations {
            current.withUnsafeBytes { message in
                next.withUnsafeMutableBytes { output in
                    mac(message, into: output.baseAddress!)
                }
            }
            swap(&current, &next)
            for index in 0..<hashLength {
                accumulator[index] ^= current[index]
            }
            if let progress, iteration % reportEvery == 0 {
                progress(Double(iteration) / Double(iterations))
            }
        }
        progress?(1)

        return Data(accumulator.prefix(derivedKeyLength))
    }

    /// base64url, no padding. RFC 4648 §5.
    ///
    /// The three substitutions are not cosmetic: `+` and `/` are not safe in the places this
    /// value travels, and `=` would push the string off the exact 43-character width the
    /// server checks.
    static func base64URLUnpadded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Equivalence check against the system implementation

/// Proves the hand-written derivation above equals `CCKeyDerivationPBKDF` on the same inputs.
///
/// IT IS NOT ON THE LOGIN PATH and is never called during sign-in — it would double the work
/// for no user-visible benefit. It exists so that the equivalence is something QA can execute
/// rather than something this file asserts about itself, and so that a future change to
/// `derive` that breaks it is caught by a test instead of by a user who cannot sign in.
///
/// `docs/decisions/0015` §D names `CCKeyDerivationPBKDF` as the Apple-side implementation, so
/// this function is also the record that the shipped code agrees with the decision.
nonisolated enum LoginSecretDerivationCheck {

    /// The same derivation, delegated to CommonCrypto in one call. No progress is possible.
    static func systemDerivation(password: Data, salt: Data) -> Data? {
        var output = [UInt8](repeating: 0, count: LoginSecretDerivation.derivedKeyLength)
        let passwordBytes = [UInt8](password)
        let saltBytes = [UInt8](salt)

        let status = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
            saltBytes.withUnsafeBufferPointer { saltBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    passwordBuffer.baseAddress!.withMemoryRebound(
                        to: CChar.self, capacity: passwordBuffer.count
                    ) { passwordChars in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            passwordChars,
                            passwordBuffer.count,
                            saltBuffer.baseAddress,
                            saltBuffer.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            UInt32(LoginSecretDerivation.iterations),
                            outputBuffer.baseAddress,
                            outputBuffer.count
                        )
                    }
                }
            }
        }
        return status == kCCSuccess ? Data(output) : nil
    }

    /// True when both implementations produce the same 32 bytes for this pair.
    ///
    /// Both sides are fed `passwordBytes`, so this checks the PBKDF2 loop rather than the
    /// normalisation — normalisation is checked by deriving the same password in composed and
    /// decomposed form and requiring one answer. See `producesOneKeyForBothUnicodeForms`.
    static func agrees(email: String, password: String) -> Bool {
        let salt = Data(LoginSecretDerivation.normalizeIdentifier(email).utf8)
        let bytes = LoginSecretDerivation.passwordBytes(password)
        let mine = LoginSecretDerivation.derive(password: bytes, salt: salt)
        guard let theirs = systemDerivation(password: bytes, salt: salt) else {
            return false
        }
        return mine == theirs
    }

    /// The property NFC exists to give: composed and decomposed spellings of one password are
    /// one key.
    ///
    /// It is stated as an executable check rather than as a comment because the failure it
    /// guards against is invisible — two byte sequences that look identical on screen, deriving
    /// two different credentials, discovered only when a user who enrolled on a Mac cannot sign
    /// in on an iPhone.
    static func producesOneKeyForBothUnicodeForms(email: String, password: String) -> Bool {
        let composed = password.precomposedStringWithCanonicalMapping
        let decomposed = password.decomposedStringWithCanonicalMapping
        return LoginSecretDerivation.deriveLoginSecret(email: email, password: composed)
            == LoginSecretDerivation.deriveLoginSecret(email: email, password: decomposed)
    }
}
