import SwiftUI

class AppState: ObservableObject {
    @Published var isAPIKeySet: Bool = false
    @Published var showSettingsSheet: Bool = false

    init() {
        checkAPIKey()
    }

    func checkAPIKey() {
        do {
            _ = try KeychainService.shared.retrieveAPIKey(for: "anthropic")
            isAPIKeySet = true
        } catch {
            isAPIKeySet = false
        }
    }

    func setAPIKey(_ key: String) throws {
        try KeychainService.shared.saveAPIKey(key, for: "anthropic")
        isAPIKeySet = true
    }

    func clearAPIKey() throws {
        // No delete method, so we can just clear the local state
        isAPIKeySet = false
    }
}
