import Foundation

struct ClaudeCodeOAuthCredentials {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }
}

enum KeychainServiceError: Error {
    case itemNotFound
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.claudequick.app"

    // MARK: - Save Operations

    func saveAPIKey(_ key: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8) ?? Data(),
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.saveFailed(status)
        }
    }

    func saveToken(_ token: String, for account: String, withKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: key.data(using: .utf8) ?? Data(),
            kSecValueData as String: token.data(using: .utf8) ?? Data(),
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.saveFailed(status)
        }
    }

    // MARK: - Retrieve Operations

    func retrieveAPIKey(for account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainServiceError.itemNotFound
            }
            throw KeychainServiceError.unexpectedData
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw KeychainServiceError.unexpectedData
        }

        return key
    }

    func retrieveToken(for account: String, withKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: key.data(using: .utf8) ?? Data(),
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainServiceError.itemNotFound
            }
            throw KeychainServiceError.unexpectedData
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw KeychainServiceError.unexpectedData
        }

        return token
    }

    // MARK: - Delete Operations

    func deleteAPIKey(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.deleteFailed(status)
        }
    }

    func deleteToken(for account: String, withKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: key.data(using: .utf8) ?? Data(),
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.deleteFailed(status)
        }
    }

    func deleteAllItems() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.deleteFailed(status)
        }
    }

    // MARK: - Claude Code OAuth

    func readClaudeCodeCredentials() throws -> ClaudeCodeOAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauthDict["accessToken"] as? String, !accessToken.isEmpty,
              let refreshToken = oauthDict["refreshToken"] as? String,
              let expiresAt = oauthDict["expiresAt"] as? Double
        else {
            throw KeychainServiceError.itemNotFound
        }

        return ClaudeCodeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAt / 1000)
        )
    }

    // MARK: - Check Operations

    func hasAPIKey(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func hasToken(for account: String, withKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: key.data(using: .utf8) ?? Data(),
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
