// KeychainStore.swift
// Conservation de la session Supabase dans le trousseau iOS.
//
// Correspondance : `src/services/authStorage.ts` côté React Native, qui utilise
// SecureStore avec `AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY` et un découpage en
// morceaux. Ici le trousseau accepte une valeur plus longue, mais on conserve
// la même politique d'accessibilité : lisible après le premier déverrouillage,
// et NON synchronisée sur iCloud — un jeton de session ne doit pas voyager.

import Foundation
import Security

public enum KeychainStore {

    public enum Failure: LocalizedError {
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Trousseau : erreur \(status)"
            }
        }
    }

    private static let service = AppConfig.bundleIdentifier

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    public static func set(_ data: Data, for key: String) throws {
        var attributes = query(key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(query(key) as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
    }

    public static func data(for key: String) -> Data? {
        var attributes = query(key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    public static func remove(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

// MARK: - Session persistée

public enum SessionStore {

    private static let key = "supabase.session"

    public static func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? KeychainStore.set(data, for: key)
    }

    public static func load() -> SupabaseSession? {
        guard let data = KeychainStore.data(for: key) else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    public static func clear() {
        KeychainStore.remove(key)
    }
}
