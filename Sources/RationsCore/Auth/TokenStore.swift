import Foundation
import Security

/// Every account's tokens in a single login keychain item, so adding an
/// account never adds another keychain prompt.
enum TokenStore {
    private static let service = "no.enso.rations"
    /// Names the app ran under before, newest first: Range Anxiety (2.1) and
    /// headroom (up to 2.0). Their items are only read by the migration, then
    /// deleted.
    static let previousServices = ["no.enso.range-anxiety", "no.enso.headroom"]
    /// 1.x only ever ran as headroom.
    static let legacyService = "no.enso.headroom"
    private static let vaultAccount = "accounts"
    private static let hubAccount = "hub"

    /// The stored JSON. `version` is there so a later format change can tell
    /// what it is reading; the keys are account ids.
    struct Vault: Codable, Equatable {
        var version = 1
        var tokens: [String: OAuthTokens]

        init(_ tokens: [UUID: OAuthTokens]) {
            self.tokens = Dictionary(uniqueKeysWithValues: tokens.map { ($0.key.uuidString, $0.value) })
        }

        /// Entries whose key is not an id belong to no account; drop them.
        var byAccount: [UUID: OAuthTokens] {
            Dictionary(uniqueKeysWithValues: tokens.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
    }

    /// Throws when the item exists but could not be read (locked keychain, a
    /// denied prompt): an empty vault there would be written back over every
    /// account's tokens on the next save.
    static func load() throws -> [UUID: OAuthTokens] {
        guard let data = try read(vaultAccount),
              let vault = try? JSONDecoder().decode(Vault.self, from: data) else { return [:] }
        return vault.byAccount
    }

    static func save(_ tokens: [UUID: OAuthTokens]) throws {
        try write(try JSONEncoder().encode(Vault(tokens)), to: vaultAccount)
    }

    /// The usage hub's management key, an item of its own so turning the hub
    /// on or off never rewrites the account vault. nil when none is stored.
    static func loadHubKey() throws -> String? {
        try read(hubAccount).map { String(decoding: $0, as: UTF8.self) }
    }

    static func saveHubKey(_ key: String) throws {
        try write(Data(key.utf8), to: hubAccount)
    }

    /// The vault written under a previous name; nil when there is none.
    static func loadPrevious(service: String) throws -> [UUID: OAuthTokens]? {
        guard let data = try read(vaultAccount, service: service) else { return nil }
        return (try? JSONDecoder().decode(Vault.self, from: data))?.byAccount ?? [:]
    }

    static func deletePrevious(service: String) {
        SecItemDelete(baseQuery(vaultAccount, service: service) as CFDictionary)
    }

    /// Pre-vault items, one per provider, under the 1.x name; only the
    /// migration reads these.
    static func loadLegacy(_ provider: Provider) throws -> OAuthTokens? {
        guard let data = try read(provider.rawValue, service: legacyService) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    static func deleteLegacy(_ provider: Provider) {
        SecItemDelete(baseQuery(provider.rawValue, service: legacyService) as CFDictionary)
    }

    /// nil means the item is absent; any other failure throws, so callers can
    /// tell "nothing stored" from "could not look".
    private static func read(_ account: String, service: String = service) throws -> Data? {
        var query = baseQuery(account, service: service)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return item as? Data
    }

    private static func write(_ data: Data, to account: String) throws {
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            try check(SecItemAdd(add as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    private static func baseQuery(_ account: String, service: String = service) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw ServiceError.keychain(message)
        }
    }
}
