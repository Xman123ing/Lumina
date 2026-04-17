import Foundation

enum AIProvider: String, CaseIterable, Codable {
    case deepSeek = "deepseek"
    case siliconFlow = "siliconflow"

    var displayName: String {
        switch self {
        case .deepSeek:
            return "DeepSeek"
        case .siliconFlow:
            return "硅基流动"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek:
            return "https://api.deepseek.com"
        case .siliconFlow:
            return "https://api.siliconflow.cn/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek:
            return "deepseek-chat"
        case .siliconFlow:
            return "Qwen/Qwen2.5-7B-Instruct"
        }
    }
}

struct AIModelConfig: Codable {
    var provider: AIProvider
    var apiKey: String
    var baseURL: String
    var model: String
    var systemPrompt: String

    static let `default` = AIModelConfig(
        provider: .deepSeek,
        apiKey: "",
        baseURL: AIProvider.deepSeek.defaultBaseURL,
        model: AIProvider.deepSeek.defaultModel,
        systemPrompt: "你是一名专业中英翻译助手。请在保留专业术语准确性的前提下，输出自然、简洁、忠实原文的译文。"
    )
}

struct AIUsageRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let provider: AIProvider
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

struct AIUsageBucket: Identifiable {
    let id = UUID()
    let label: String
    let calls: Int
    let tokens: Int
}

struct AIUsageSummary {
    let totalCalls: Int
    let totalTokens: Int
}

@MainActor
final class AISettingsStore {
    static let shared = AISettingsStore()

    private let fileURL: URL
    private var configValue: AIModelConfig

    private init() {
        fileURL = AISettingsStore.makeFileURL(fileName: "ai_config.json")
        configValue = AIModelConfig.default
        load()
    }

    var config: AIModelConfig {
        configValue
    }

    func update(_ newConfig: AIModelConfig) {
        configValue = newConfig
        save()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let loaded = try? JSONDecoder().decode(AIModelConfig.self, from: data)
        else {
            save()
            return
        }
        configValue = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configValue) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func makeFileURL(fileName: String) -> URL {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("Lumina/metrics", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}

@MainActor
final class AIUsageStore {
    static let shared = AIUsageStore()

    private let fileURL: URL
    private var records: [AIUsageRecord]

    private init() {
        fileURL = AISettingsStore.makeFileURL(fileName: "ai_usage_records.json")
        records = []
        load()
    }

    func append(_ record: AIUsageRecord) {
        records.append(record)
        save()
    }

    func dailyBuckets(lastDays: Int) -> [AIUsageBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<lastDays).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let start = day
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let dayRecords = records.filter { $0.timestamp >= start && $0.timestamp < end }
            return AIUsageBucket(
                label: dayLabel(for: day),
                calls: dayRecords.count,
                tokens: dayRecords.reduce(0) { $0 + $1.totalTokens }
            )
        }
    }

    func monthlyBuckets(lastMonths: Int) -> [AIUsageBucket] {
        let calendar = Calendar.current
        let now = Date()

        return (0..<lastMonths).reversed().map { offset in
            let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            let start = calendar.date(from: comps) ?? monthDate
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let monthRecords = records.filter { $0.timestamp >= start && $0.timestamp < end }
            return AIUsageBucket(
                label: monthLabel(for: start),
                calls: monthRecords.count,
                tokens: monthRecords.reduce(0) { $0 + $1.totalTokens }
            )
        }
    }

    func summary() -> AIUsageSummary {
        AIUsageSummary(
            totalCalls: records.count,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens }
        )
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let loaded = try? JSONDecoder().decode([AIUsageRecord].self, from: data)
        else {
            save()
            return
        }
        records = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
