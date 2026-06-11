import SwiftUI

enum AuthMode: String {
    case apiKey
    case claudePro
}

class AppState: ObservableObject {
    @Published var isAPIKeySet: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var authMode: AuthMode = .apiKey

    init() {
        checkAuth()
    }

    func checkAuth() {
        // Check saved auth mode preference
        let saved = UserDefaults.standard.string(forKey: "authMode") ?? ""
        if saved == AuthMode.claudePro.rawValue {
            if let creds = try? KeychainService.shared.readClaudeCodeCredentials(), !creds.isExpired {
                APIClient.shared.setOAuthToken(creds.accessToken)
                authMode = .claudePro
                isAPIKeySet = true
                return
            }
            // Token expired — fall through to re-auth
            UserDefaults.standard.removeObject(forKey: "authMode")
        }

        // Check API key
        if (try? KeychainService.shared.retrieveAPIKey(for: "anthropic")) != nil {
            authMode = .apiKey
            isAPIKeySet = true
            return
        }

        // Check if Claude Code creds available (auto-detect)
        if let creds = try? KeychainService.shared.readClaudeCodeCredentials(), !creds.isExpired {
            APIClient.shared.setOAuthToken(creds.accessToken)
            authMode = .claudePro
            isAPIKeySet = true
            UserDefaults.standard.set(AuthMode.claudePro.rawValue, forKey: "authMode")
            return
        }

        isAPIKeySet = false
    }

    func setAPIKey(_ key: String) throws {
        try KeychainService.shared.saveAPIKey(key, for: "anthropic")
        try APIClient.shared.setAPIKey(key)
        authMode = .apiKey
        UserDefaults.standard.set(AuthMode.apiKey.rawValue, forKey: "authMode")
        isAPIKeySet = true
    }

    func connectClaudePro() throws {
        let creds = try KeychainService.shared.readClaudeCodeCredentials()
        guard !creds.isExpired else {
            throw NSError(domain: "AppState", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Claude Code session expired. Run `claude` in terminal to refresh."
            ])
        }
        APIClient.shared.setOAuthToken(creds.accessToken)
        authMode = .claudePro
        UserDefaults.standard.set(AuthMode.claudePro.rawValue, forKey: "authMode")
        isAPIKeySet = true
    }

    func clearAPIKey() throws {
        try? KeychainService.shared.deleteAPIKey(for: "anthropic")
        UserDefaults.standard.removeObject(forKey: "authMode")
        isAPIKeySet = false
    }
}
