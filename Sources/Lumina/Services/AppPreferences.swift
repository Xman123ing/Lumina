import SwiftUI

enum QuickShortcutPreset: String, CaseIterable, Codable {
    case commandK
    case commandShiftK
    case optionSpace

    var title: String {
        switch self {
        case .commandK:
            return "Command + K"
        case .commandShiftK:
            return "Command + Shift + K"
        case .optionSpace:
            return "Option + Space"
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .commandK, .commandShiftK:
            return "k"
        case .optionSpace:
            return " "
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .commandK:
            return [.command]
        case .commandShiftK:
            return [.command, .shift]
        case .optionSpace:
            return [.option]
        }
    }
}

enum SpeechRolePreset: String, CaseIterable, Codable {
    case balanced
    case warmFemale
    case steadyMale
    case brightNarrator

    var title: String {
        switch self {
        case .balanced:
            return "默认平衡"
        case .warmFemale:
            return "温柔女声"
        case .steadyMale:
            return "沉稳男声"
        case .brightNarrator:
            return "明快播报"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var quickShortcutPreset: QuickShortcutPreset {
        didSet { save() }
    }
    @Published var speechRolePreset: SpeechRolePreset {
        didSet { save() }
    }

    private let storageKey = "lumina.quickShortcutPreset"
    private let speechRoleKey = "lumina.speechRolePreset"

    private init() {
        if
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let preset = QuickShortcutPreset(rawValue: raw)
        {
            quickShortcutPreset = preset
        } else {
            quickShortcutPreset = .commandK
        }

        if
            let raw = UserDefaults.standard.string(forKey: speechRoleKey),
            let preset = SpeechRolePreset(rawValue: raw)
        {
            speechRolePreset = preset
        } else {
            speechRolePreset = .balanced
        }
    }

    private func save() {
        UserDefaults.standard.set(quickShortcutPreset.rawValue, forKey: storageKey)
        UserDefaults.standard.set(speechRolePreset.rawValue, forKey: speechRoleKey)
    }
}
