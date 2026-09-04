import Foundation
import Testing
@testable import Dudo

/// The client-side KDF, `docs/decisions/0015` §D and its 2026-09-04 NFC amendment.
///
/// ===========================================================================================
/// THESE ARE CROSS-CLIENT TESTS, WHICH IS WHY THE EXPECTED VALUES ARE LITERALS
/// ===========================================================================================
///
/// Every expected string below was produced by FOUR independent implementations — this client,
/// the web client's shipped `src/api/kdf.ts`, Apple's `CCKeyDerivationPBKDF`, and Python's
/// `hashlib.pbkdf2_hmac` — and they agreed byte for byte. They are hard-coded rather than
/// recomputed because a test that recomputes the expectation with the code under test cannot
/// fail. These constants ARE the contract between the two clients.
///
/// A failure here means a user who enrolled on the web cannot sign in on an iPhone. It is not a
/// unit-test failure; it is a cross-client contract defect.
@Suite("Login secret derivation")
struct LoginSecretDerivationTests {

    // MARK: - The shared vectors

    @Test("The ASCII cross-client vector")
    func asciiVector() {
        let derived = LoginSecretDerivation.deriveLoginSecret(
            email: "Test@Example.COM",
            password: "correct horse battery staple"
        )
        #expect(derived == "vDKY7nW_Ay6C6JtXqe0QC9cBRmBfrTgqxOmnxr72Kqw")
        #expect(derived.count == LoginSecretDerivation.encodedLength)
    }

    /// The non-ASCII vector, and the reason it exists.
    ///
    /// THE STRINGS ARE BUILT FROM `\u{...}` ESCAPES AND ARE NEVER TYPED LITERALLY. A literal is
    /// normalised by whatever wrote the source file, so a test written with two literals may be
    /// comparing a string to itself and passing for no reason at all. The first expectation is a
    /// GUARD asserting the two forms really are different byte sequences — if it ever fails,
    /// every assertion after it is meaningless rather than merely wrong.
    @Test("The non-ASCII cross-client vector, composed and decomposed")
    func nonASCIIVector() {
        let composed = "p\u{00E4}ssw\u{00F6}rd"
        let decomposed = "pa\u{0308}sswo\u{0308}rd"

        #expect(
            Array(composed.utf8) != Array(decomposed.utf8),
            "GUARD: the two spellings must be different bytes or this test proves nothing"
        )
        #expect(hex(composed) == "70c3a4737377c3b67264")
        #expect(hex(decomposed) == "7061cc887373776fcc887264")

        let expected = "ikIunD3491AfgeVOMPonp2D_bYFaLhDBzi1kIWMX004"
        let fromComposed = LoginSecretDerivation.deriveLoginSecret(
            email: "Test@Example.COM", password: composed)
        let fromDecomposed = LoginSecretDerivation.deriveLoginSecret(
            email: "Test@Example.COM", password: decomposed)

        #expect(fromComposed == expected)
        #expect(fromDecomposed == expected)
        #expect(fromComposed == fromDecomposed)
    }

    // MARK: - The swap guards

    /// Fails if `precomposedStringWithCanonicalMapping` (NFC, password) and
    /// `precomposedStringWithCompatibilityMapping` (NFKC, identifier) are exchanged.
    ///
    /// ===========================================================================================
    /// THE SHARED VECTORS ABOVE CANNOT CATCH THIS, WHICH IS THE WHOLE REASON THIS TEST EXISTS
    /// ===========================================================================================
    ///
    /// `ä` and `ö` have no compatibility decomposition, so NFKC equals NFC over `pässwörd` and
    /// the non-ASCII vector passes with the two calls swapped. It was verified by swapping them
    /// in a throwaway copy and watching only these two expectations go red.
    ///
    /// The two mistakes have different symptoms and are pinned separately: NFKC on a password
    /// silently destroys entropy the user believes they have, and NFC on an identifier splits
    /// one account into two.
    /// The shared cross-client swap detector, in the exact form the web client uses.
    ///
    /// `ﬁnance` (U+FB01 LATIN SMALL LIGATURE FI) and `finance` must derive DIFFERENT keys. Under
    /// NFC they are two passwords; under NFKC they collapse into one, and a character the user
    /// deliberately chose is silently merged away along with the entropy they believe it carries.
    ///
    /// It is written in the same form as web's so that a divergence between the clients is a
    /// single diff rather than a comparison of two differently-shaped tests.
    @Test("The shared swap detector: ﬁnance and finance are different passwords")
    func sharedSwapDetectorVector() {
        let ligature = "\u{FB01}nance"
        let spelledOut = "finance"

        #expect(
            ligature.precomposedStringWithCompatibilityMapping == spelledOut,
            "GUARD: NFKC must actually collapse these, or the vector cannot detect the swap"
        )
        #expect(Array(ligature.utf8) != Array(spelledOut.utf8))
        #expect(
            LoginSecretDerivation.deriveLoginSecret(
                email: "Test@Example.COM", password: ligature)
                != LoginSecretDerivation.deriveLoginSecret(
                    email: "Test@Example.COM", password: spelledOut)
        )
    }

    @Test("A password keeps compatibility variants distinct — fails if NFKC is used on it")
    func passwordUsesCanonicalMappingOnly() {
        let ligature = "pa\u{FB01}x"
        let expansion = "pafix"

        #expect(
            ligature.precomposedStringWithCompatibilityMapping == expansion,
            "GUARD: NFKC must actually collapse this, or the test cannot detect the swap"
        )
        #expect(
            LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: ligature)
                != LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: expansion)
        )
    }

    /// The other direction. Such an identifier is refused by `refusalReason` long before it
    /// could reach normalisation, so this asserts the function's behaviour directly — which is
    /// the point. It pins WHICH call is used, rather than a consequence that ASCII input can
    /// never reveal.
    @Test("An identifier collapses compatibility variants — fails if NFC is used on it")
    func identifierUsesCompatibilityMapping() {
        #expect(LoginSecretDerivation.normalizeIdentifier("\u{FB01}@x.co") == "fi@x.co")
    }

    // MARK: - The password is not touched in any other way

    @Test("Password case is preserved")
    func passwordCaseIsPreserved() {
        #expect(
            LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: "Secret")
                != LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: "secret")
        )
    }

    @Test("A leading space is part of the password")
    func passwordIsNotTrimmed() {
        #expect(
            LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: " s")
                != LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: "s")
        )
    }

    // MARK: - Identifier normalisation

    @Test("ASCII-only case folding, not Unicode case mapping")
    func identifierFoldsASCIIOnly() {
        #expect(LoginSecretDerivation.normalizeIdentifier("Test@Example.COM") == "test@example.com")
        // U+0130 is where Swift's `lowercased()` and JavaScript's `toLowerCase()` diverge. The
        // ASCII-only fold must leave it alone; `lowercased()` would not.
        let turkish = "\u{0130}@x.co"
        #expect(LoginSecretDerivation.normalizeIdentifier(turkish) == turkish)
        #expect(turkish.lowercased() != turkish, "GUARD: lowercased() must differ here")
    }

    @Test("The salt is the normalised identifier's UTF-8 bytes")
    func saltIsTheNormalisedIdentifier() {
        let salt = LoginSecretDerivation.normalizeIdentifier("Test@Example.COM")
        #expect(hex(salt) == "74657374406578616d706c652e636f6d")
    }

    // MARK: - What is refused, and what refusal means

    /// Whitespace and non-ASCII are REFUSED, never trimmed or mapped.
    ///
    /// Core refuses them instead of trimming because JavaScript's `trim()` and Swift's
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` cover different character sets, so a
    /// value that needs trimming is a value the implementations can disagree about. Removing the
    /// disagreement beats arbitrating it.
    @Test(
        "Identifiers outside printable ASCII are refused",
        arguments: [
            " test@example.com",
            "test@example.com ",
            "t\u{00EB}st@example.com",
            "test@exam\u{00A0}ple.com",
        ]
    )
    func refusesNonPrintableASCII(_ candidate: String) {
        #expect(
            LoginSecretDerivation.refusalReason(forSubmittedIdentifier: candidate)
                == .containsUnsupportedCharacter
        )
    }

    @Test("Length and shape are refused at the documented bounds")
    func refusesOnLengthAndShape() {
        #expect(LoginSecretDerivation.refusalReason(forSubmittedIdentifier: "ab") == .tooShort)
        #expect(LoginSecretDerivation.refusalReason(forSubmittedIdentifier: "a@b") == nil)
        #expect(
            LoginSecretDerivation.refusalReason(forSubmittedIdentifier: "noatsign") == .missingAtSign
        )
        let tooLong = String(repeating: "a", count: 250) + "@example.com"
        #expect(LoginSecretDerivation.refusalReason(forSubmittedIdentifier: tooLong) == .tooLong)
    }

    // MARK: - The implementation agrees with the system one

    /// `0015` §D names `CCKeyDerivationPBKDF` as the Apple-side implementation. The shipped
    /// derivation is hand-written so that progress can be reported honestly, so the equivalence
    /// has to be executed rather than asserted in a comment.
    @Test("The hand-written PBKDF2 equals CCKeyDerivationPBKDF")
    func agreesWithCommonCrypto() {
        #expect(LoginSecretDerivationCheck.agrees(
            email: "Test@Example.COM", password: "correct horse battery staple"))
        #expect(LoginSecretDerivationCheck.agrees(
            email: "Test@Example.COM", password: "p\u{00E4}ssw\u{00F6}rd"))
    }

    @Test("Progress is monotonic and reaches exactly 1")
    func progressIsReal() {
        // `nonisolated` because the progress callback is invoked from whatever executor the
        // derivation is running on, which is deliberately not the main actor.
        nonisolated final class Samples: @unchecked Sendable {
            let lock = NSLock()
            var values: [Double] = []
            func append(_ value: Double) {
                lock.lock(); defer { lock.unlock() }
                values.append(value)
            }
        }
        let samples = Samples()
        _ = LoginSecretDerivation.deriveLoginSecret(email: "u@x.co", password: "x") {
            samples.append($0)
        }
        let values = samples.values
        #expect(values.count > 1)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("The parameters 0015 §D fixes are the parameters in the code")
    func parametersAreNormative() {
        #expect(LoginSecretDerivation.iterations == 600_000)
        #expect(LoginSecretDerivation.derivedKeyLength == 32)
        #expect(LoginSecretDerivation.encodedLength == 43)
    }

    @Test("base64url is unpadded and uses no + or /")
    func encodingIsBase64URL() {
        let encoded = LoginSecretDerivation.base64URLUnpadded(Data([251, 255, 190, 0]))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(encoded == "-_--AA")
    }

    private func hex(_ value: String) -> String {
        Data(value.utf8).map { String(format: "%02x", $0) }.joined()
    }
}
