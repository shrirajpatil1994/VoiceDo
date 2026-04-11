import Foundation
import os.log
import Security
import VoiceDoShared

// MARK: - APIKeyManager

/// Manages the user-provided Claude API key via the iOS Keychain.
///
/// Security properties:
/// - `kSecAttrAccessible = .whenUnlockedThisDeviceOnly` — encrypted at rest,
///   inaccessible when device is locked, never leaves the device.
/// - `kSecAttrSynchronizable = false` — not backed up to iCloud.
/// - Key is never logged (guarded at all call sites).
enum APIKeyManager {

    private static let logger = Logger(subsystem: AppConstants.logSubsystem, category: "APIKeyManager")

    // MARK: - Keychain Query Base

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppConstants.keychainService,
            kSecAttrAccount: AppConstants.keychainAccount,
            kSecAttrSynchronizable: false
        ]
    }

    // MARK: - Public API

    /// Save or update the API key in the Keychain.
    /// - Parameter key: The raw API key string. Never pass an empty string.
    static func save(_ key: String) throws {
        // Trim whitespace/newlines that are commonly introduced by copy-paste.
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyKey }

        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try updating first
        var updateQuery = baseQuery
        updateQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Not found — add new
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }

        logger.info("API key saved to Keychain successfully")
    }

    /// Retrieve the stored API key, or `nil` if not set.
    static func retrieve() throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.retrievalFailed(status)
        }
        guard let data = result as? Data,
              let raw = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        // Trim in case the key was stored before whitespace-trimming was added.
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        // Intentionally not logging the key value
        logger.info("API key retrieved from Keychain")
        return key
    }

    /// Delete the stored API key. Safe to call if no key is stored.
    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        logger.info("API key deleted from Keychain")
    }

    /// Returns `true` if an API key is currently stored.
    static func hasKey() -> Bool {
        (try? retrieve()) != nil
    }
}

// MARK: - KeychainError

enum KeychainError: Error, LocalizedError {
    case emptyKey
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "API key cannot be empty."
        case .encodingFailed:
            return "Failed to encode API key data."
        case .decodingFailed:
            return "Failed to decode API key from Keychain."
        case .saveFailed(let status):
            return "Keychain save failed (OSStatus: \(status))."
        case .retrievalFailed(let status):
            return "Keychain retrieval failed (OSStatus: \(status))."
        case .deleteFailed(let status):
            return "Keychain delete failed (OSStatus: \(status))."
        }
    }
}
