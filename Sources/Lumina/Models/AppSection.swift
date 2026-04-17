enum AppSection: String, CaseIterable {
    case dictionary
    case textPhrase

    var title: String {
        switch self {
        case .dictionary: return "Dictionary"
        case .textPhrase: return "Long Text"
        }
    }
}
