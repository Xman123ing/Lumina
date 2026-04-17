import Foundation

struct DictionaryEntry {
    let term: String
    let phoneticUS: String
    let phoneticUK: String
    let definitions: [String]
    let englishDefinitions: [String]
}

@MainActor
final class TranslatorService {
    static let shared = TranslatorService()

    private let store = SQLiteDictionaryStore.shared
    private let aiSettings = AISettingsStore.shared
    private let usageStore = AIUsageStore.shared

    private init() {}

    func lookupLocal(term: String) -> DictionaryEntry? {
        store.lookup(term: term)
    }

    func searchLocalCandidates(term: String, limit: Int = 8) -> [DictionaryEntry] {
        store.search(term: term, limit: limit)
    }

    func translateLocal(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Single-word lookup: return the dictionary definition directly.
        if !trimmed.contains(" "), let entry = lookupLocal(term: trimmed) {
            return entry.definitions.joined(separator: "\n")
        }

        // Multi-word fallback: word-by-word dictionary translation.
        let tokens = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return "未识别到可翻译词元。"
        }

        var lines: [String] = []
        for token in tokens {
            if let entry = lookupLocal(term: token), let primary = entry.definitions.first {
                lines.append("\(token) -> \(primary)")
            } else {
                lines.append("\(token) -> [未收录]")
            }
        }

        return lines.joined(separator: "\n")
    }

    func aiConfig() -> AIModelConfig {
        aiSettings.config
    }

    func updateAIConfig(_ config: AIModelConfig) {
        aiSettings.update(config)
    }

    func aiUsageDaily(lastDays: Int = 14) -> [AIUsageBucket] {
        usageStore.dailyBuckets(lastDays: lastDays)
    }

    func aiUsageMonthly(lastMonths: Int = 6) -> [AIUsageBucket] {
        usageStore.monthlyBuckets(lastMonths: lastMonths)
    }

    func aiUsageSummary() -> AIUsageSummary {
        usageStore.summary()
    }

    func translateAI(text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let config = aiSettings.config
        if config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先在 Settings 中配置 \(config.provider.displayName) 的 API Key。"
        }

        guard let request = buildRequest(text: trimmed, config: config) else {
            return "AI 配置无效：请检查 Base URL。"
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "AI 请求失败：无效响应。"
            }

            guard (200...299).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return "AI 请求失败(\(http.statusCode))：\(raw)"
            }

            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let translated = content?.isEmpty == false ? content! : "AI 返回为空，请稍后重试。"

            let usage = decoded.usage
            let promptTokens = usage?.prompt_tokens ?? estimateTokens(for: trimmed)
            let completionTokens = usage?.completion_tokens ?? estimateTokens(for: translated)
            let totalTokens = usage?.total_tokens ?? (promptTokens + completionTokens)

            usageStore.append(
                AIUsageRecord(
                    id: UUID(),
                    timestamp: Date(),
                    provider: config.provider,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: totalTokens
                )
            )
            return translated
        } catch {
            return "AI 翻译失败：\(error.localizedDescription)"
        }
    }

    func importCustomDictionaryTSV(fileURL: URL) throws {
        try store.importFromTSV(fileURL: fileURL)
    }

    func localEntryCount() -> Int {
        store.entryCount()
    }

    func localDatabasePath() -> String {
        store.databasePath
    }

    private func buildRequest(text: String, config: AIModelConfig) -> URLRequest? {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        let endpoint = base.hasSuffix("/chat/completions")
            ? base
            : base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIChatRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: config.systemPrompt),
                .init(role: "user", content: text)
            ],
            temperature: 0.2
        )

        request.httpBody = try? JSONEncoder().encode(payload)
        return request
    }

    private func estimateTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String
        }
        let message: Message
    }

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }

    let choices: [Choice]
    let usage: Usage?
}
