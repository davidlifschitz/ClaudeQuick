import Foundation

class CostTracker {
    static let shared = CostTracker()

    private let storageService = StorageService.shared

    // Token pricing per 1M tokens (as of 2024)
    private let modelPricing: [String: (input: Double, output: Double)] = [
        "claude-3-5-sonnet-20241022": (input: 3.0, output: 15.0),
        "claude-3-opus-20250219": (input: 15.0, output: 75.0),
        "claude-3-haiku-20250307": (input: 0.80, output: 4.0),
    ]

    // MARK: - Public Methods

    func trackUsage(model: String, inputTokens: Int, outputTokens: Int) throws {
        let usage = UsageEntry(
            date: Date(),
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cost: calculateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
        )

        var entries = try fetchAllUsage()
        entries.append(usage)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try storageService.saveData(key: "token_usage", data: data)
    }

    func fetchUsageForModel(_ model: String) throws -> [UsageEntry] {
        let allUsage = try fetchAllUsage()
        return allUsage.filter { $0.model == model }
    }

    func fetchAllUsage() throws -> [UsageEntry] {
        guard let data = try storageService.loadData(key: "token_usage") else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([UsageEntry].self, from: data)
    }

    func totalCostForModel(_ model: String) throws -> Double {
        let usage = try fetchUsageForModel(model)
        return usage.reduce(0) { $0 + $1.cost }
    }

    func totalCost() throws -> Double {
        let usage = try fetchAllUsage()
        return usage.reduce(0) { $0 + $1.cost }
    }

    func totalTokensForModel(_ model: String) throws -> (input: Int, output: Int) {
        let usage = try fetchUsageForModel(model)
        let inputTotal = usage.reduce(0) { $0 + $1.inputTokens }
        let outputTotal = usage.reduce(0) { $0 + $1.outputTokens }
        return (input: inputTotal, output: outputTotal)
    }

    func totalTokens() throws -> (input: Int, output: Int) {
        let usage = try fetchAllUsage()
        let inputTotal = usage.reduce(0) { $0 + $1.inputTokens }
        let outputTotal = usage.reduce(0) { $0 + $1.outputTokens }
        return (input: inputTotal, output: outputTotal)
    }

    func clearUsage() throws {
        try storageService.delete(key: "token_usage")
    }

    // MARK: - Private Methods

    private func calculateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        guard let pricing = modelPricing[model] else {
            return 0.0
        }

        let inputCost = Double(inputTokens) * (pricing.input / 1_000_000.0)
        let outputCost = Double(outputTokens) * (pricing.output / 1_000_000.0)

        return inputCost + outputCost
    }
}

// MARK: - Models

struct UsageEntry: Codable {
    let date: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double

    var totalTokens: Int {
        return inputTokens + outputTokens
    }
}
