import Foundation
import Security

/// A session credential and when it stops being one.
///
/// The value is `<session_id>.<HMAC-SHA-256(session_id) truncated to 128 bits>`
/// (`docs/decisions/0015` §A). This client NEVER parses it, splits it, or reads anything out of
/// it — it is opaque, the server verifies the MAC with a secret this app does not have, and a
/// client that pulled the session id out of it would be reading a value it has no business
/// interpreting.
nonisolated struct SessionCredential: Equatable, Sendable, Codable {
    let value: String
    /// Absolute expiry. `0015` §B fixes the session at 12 hours with NO ROTATION on any
    /// request, so this instant is known at login and never moves.
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }

    /// The contract's lifetime, used when a response carries no `Max-Age` to compute from.
    static let defaultLifetime: TimeInterval = 12 * 60 * 60
}

/// Keeps the session credential in the Keychain.
///
/// ===========================================================================================
/// WHY THE KEYCHAIN AND NOT `UserDefaults`
/// ===========================================================================================
///
/// `UserDefaults` is a plist in the app container. It is readable by anything that can read the
/// container — a backup, a sync, a file-sharing entitlement, a jailbroken device, a Mac where
/// the user's home directory is on a shared volume — and it is not encrypted at rest beyond
/// whatever the file system provides. This value is a **bearer credential**: whoever holds it
/// is the user, for twelve hours, with no second factor and no way to revoke it (see the note
/// on sign-out in `SessionController`). It belongs in the Keychain.
///
/// ===========================================================================================
/// THE TWO PLATFORMS TAKE DIFFERENT PATHS, AND THAT IS DELIBERATE
/// ===========================================================================================
///
/// iOS/iPadOS use the data-protection Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
///
///   - `AfterFirstUnlock` rather than `WhenUnlocked`, because nothing here needs to be readable
///     before the first unlock and nothing needs to be readable while locked either; this is
///     the strictest class that does not break a normal app launch.
///   - `ThisDeviceOnly` is the load-bearing half: it keeps the credential out of iCloud Keychain
///     and out of encrypted backups, so restoring a backup onto a second device does not carry
///     a live session with it.
///
/// macOS uses the file-based Keychain — `kSecUseDataProtectionKeychain` is NOT set. The data
/// protection Keychain on macOS requires a `keychain-access-groups` entitlement, and adding an
/// entitlement to this target means a provisioning-profile write in the Apple Developer portal,
/// which is a user-only action and is exactly the class of change `0015` §D chose an option to
/// AVOID. The file Keychain needs no entitlement, works inside the App Sandbox, and is still
/// vastly better than a plist. The cost is stated rather than hidden: `kSecAttrAccessible` is
/// ignored there, so the macOS copy follows the login keychain's own lock state.
nonisolated enum SessionCredentialStore {

    /// A generic-password item, scoped to this app by service name.
    private static let service = "com.dudo.work.session"
    private static let account = "dudo_session"

    // MARK: - Reading

    /// The stored credential, or `nil` if there is none.
    ///
    /// AN EXPIRED CREDENTIAL IS DELETED AND REPORTED AS ABSENT. Keeping it would mean the app
    /// launches into the directory, fires a request, and bounces the user to sign-in a second
    /// later — which looks like a bug and is one.
    static func load() -> SessionCredential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let credential = try? JSONDecoder().decode(SessionCredential.self, from: data)
        else {
            return nil
        }
        guard !credential.isExpired else {
            clear()
            return nil
        }
        return credential
    }

    // MARK: - Writing

    /// Stores the credential, replacing any previous one.
    ///
    /// Delete-then-add rather than update: an update against a partially-matching query is the
    /// classic way to end up with two items and a login that works once. There is exactly one
    /// session per installation, so there is exactly one item.
    @discardableResult
    static func save(_ credential: SessionCredential) -> Bool {
        guard let data = try? JSONEncoder().encode(credential) else { return false }
        clear()

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        #if !os(macOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the credential. Called on sign-out and on any `unauthenticated` answer.
    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Query

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if !os(macOS)
        // The modern Keychain on the platforms where it needs no entitlement. See the header.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
