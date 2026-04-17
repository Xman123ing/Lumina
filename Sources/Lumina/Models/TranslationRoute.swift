enum TranslationRoute: String, CaseIterable {
    case local
    case ai

    var title: String {
        switch self {
        case .local: return "Local Translate"
        case .ai: return "Ask AI"
        }
    }
}
