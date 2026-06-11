import SwiftUI

class AppState: ObservableObject {
    @Published var isAPIKeySet: Bool = false
    @Published var showSettingsSheet: Bool = false

    init() {
        checkAPIKey()
    }

    func checkAPIKey() {
        isAPIKeySet = KeychainService.shared.retrieve(key: "anthropic_api_key") != nil
    }

    func setAPIKey(_ key: String) throws {
        try KeychainService.shared.save(key: "anthropic_api_key", value: key)
        isAPIKeySet = true
    }

    func clearAPIKey() throws {
        try KeychainService.shared.delete(key: "anthropic_api_key")
        isAPIKeySet = false
    }
}
