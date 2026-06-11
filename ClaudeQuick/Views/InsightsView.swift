import SwiftUI

struct InsightsView: View {
    @State private var usageEntries: [UsageEntry] = []
    @State private var totalCost: Double = 0
    @State private var totalInputTokens: Int = 0
    @State private var totalOutputTokens: Int = 0
    @State private var conversationCount: Int = 0
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section: Summary Cards
                Text("Overview")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                HStack(spacing: 10) {
                    SummaryCard(value: String(format: "$%.4f", totalCost), label: "Total Cost")
                    SummaryCard(value: formatNumber(totalInputTokens), label: "Input Tokens")
                    SummaryCard(value: formatNumber(totalOutputTokens), label: "Output Tokens")
                    SummaryCard(value: "\(conversationCount)", label: "Conversations")
                }
                .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Section: Daily Token Usage Chart
                Text("Last 7 Days")
                    .font(.headline)
                    .padding(.horizontal, 16)

                DailyTokenChart(entries: usageEntries)
                    .frame(height: 160)
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Section: Cost by Model
                Text("Cost by Model")
                    .font(.headline)
                    .padding(.horizontal, 16)

                CostByModelView(entries: usageEntries)
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Section: Recent Activity
                Text("Recent Activity")
                    .font(.headline)
                    .padding(.horizontal, 16)

                RecentActivityView(entries: Array(usageEntries.sorted { $0.date > $1.date }.prefix(10)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("Insights")
        .onAppear { loadData() }
    }

    private func loadData() {
        do {
            let entries = try CostTracker.shared.fetchAllUsage()
            usageEntries = entries
            totalCost = (try? CostTracker.shared.totalCost()) ?? 0
            let tokens = (try? CostTracker.shared.totalTokens())
            totalInputTokens = tokens?.input ?? 0
            totalOutputTokens = tokens?.output ?? 0
            let conversations = (try? StorageService.shared.fetchAllConversations()) ?? []
            conversationCount = conversations.count
        } catch {
            // leave defaults
        }
        isLoading = false
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Daily Token Chart (Canvas, macOS 12+)

private struct DailyTokenChart: View {
    let entries: [UsageEntry]

    private var days: [(date: Date, label: String, input: Int, output: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let label = formatter.string(from: day)
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let input = dayEntries.reduce(0) { $0 + $1.inputTokens }
            let output = dayEntries.reduce(0) { $0 + $1.outputTokens }
            return (date: day, label: label, input: input, output: output)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let chartData = days
            let maxVal = chartData.map { max($0.input, $0.output) }.max() ?? 1
            let safeMax = maxVal == 0 ? 1 : maxVal
            let chartWidth = geo.size.width
            let chartHeight = geo.size.height
            let bottomPad: CGFloat = 20
            let availableHeight = chartHeight - bottomPad
            let colWidth = chartWidth / CGFloat(chartData.count)
            let barWidth = colWidth * 0.28
            let gap: CGFloat = 3

            Canvas { context, size in
                // Draw gridlines
                for i in 0...4 {
                    let y = availableHeight - availableHeight * CGFloat(i) / 4
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color(.separatorColor).opacity(0.4)), lineWidth: 0.5)
                }

                for (i, day) in chartData.enumerated() {
                    let x = CGFloat(i) * colWidth + colWidth / 2

                    // Input bar (blue)
                    let inputH = CGFloat(day.input) / CGFloat(safeMax) * availableHeight
                    let inputRect = CGRect(
                        x: x - barWidth - gap / 2,
                        y: availableHeight - inputH,
                        width: barWidth,
                        height: max(inputH, 1)
                    )
                    var inputPath = Path()
                    inputPath.addRoundedRect(in: inputRect, cornerSize: CGSize(width: 2, height: 2))
                    context.fill(inputPath, with: .color(Color.blue.opacity(0.7)))

                    // Output bar (purple)
                    let outputH = CGFloat(day.output) / CGFloat(safeMax) * availableHeight
                    let outputRect = CGRect(
                        x: x + gap / 2,
                        y: availableHeight - outputH,
                        width: barWidth,
                        height: max(outputH, 1)
                    )
                    var outputPath = Path()
                    outputPath.addRoundedRect(in: outputRect, cornerSize: CGSize(width: 2, height: 2))
                    context.fill(outputPath, with: .color(Color.purple.opacity(0.7)))

                    // Day label
                    context.draw(
                        Text(day.label).font(.system(size: 9)).foregroundColor(.secondary),
                        at: CGPoint(x: x, y: availableHeight + 10),
                        anchor: .center
                    )
                }
            }

            // Legend overlay
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Input").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Output").font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Cost by Model

private struct CostByModelView: View {
    let entries: [UsageEntry]

    private static let displayNames: [String: String] = [
        "claude-haiku-4-5": "Haiku 4.5",
        "claude-sonnet-4-5": "Sonnet 4.5",
        "claude-sonnet-4-6": "Sonnet 4.6",
        "claude-opus-4-5": "Opus 4.5",
        "claude-opus-4-8": "Opus 4.8",
        "claude-3-5-sonnet-20241022": "Sonnet 4.6",
        "claude-3-opus-20250219": "Opus 4.8",
        "claude-3-haiku-20250307": "Haiku 4.5",
    ]

    private var modelCosts: [(model: String, cost: Double)] {
        var dict: [String: Double] = [:]
        for entry in entries {
            dict[entry.model, default: 0] += entry.cost
        }
        return dict.map { (model: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
    }

    private var maxCost: Double {
        modelCosts.map(\.cost).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 8) {
            if modelCosts.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(modelCosts, id: \.model) { item in
                    HStack(spacing: 10) {
                        Text(Self.displayNames[item.model] ?? item.model)
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.separatorColor).opacity(0.3))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(item.cost / max(maxCost, 0.000001)), height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text(String(format: "$%.4f", item.cost))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 65, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
            }
        }
    }
}

// MARK: - Recent Activity

private struct RecentActivityView: View {
    let entries: [UsageEntry]

    private static let displayNames: [String: String] = [
        "claude-haiku-4-5": "Haiku 4.5",
        "claude-sonnet-4-5": "Sonnet 4.5",
        "claude-sonnet-4-6": "Sonnet 4.6",
        "claude-opus-4-5": "Opus 4.5",
        "claude-opus-4-8": "Opus 4.8",
        "claude-3-5-sonnet-20241022": "Sonnet 4.6",
        "claude-3-opus-20250219": "Opus 4.8",
        "claude-3-haiku-20250307": "Haiku 4.5",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("No activity yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            Text(Self.displayNames[entry.model] ?? entry.model)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(entry.totalTokens) tokens")
                                .font(.caption)
                            Text(String(format: "$%.5f", entry.cost))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    if entry.date != entries.last?.date {
                        Divider()
                    }
                }
            }
        }
    }
}

#Preview {
    InsightsView()
}
