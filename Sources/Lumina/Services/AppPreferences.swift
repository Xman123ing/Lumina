import SwiftUI

struct QuickShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiersRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection([.command, .shift, .option, .control])
    }

    var displayTitle: String {
        let parts = [
            modifiers.contains(.command) ? "Command" : nil,
            modifiers.contains(.shift) ? "Shift" : nil,
            modifiers.contains(.option) ? "Option" : nil,
            modifiers.contains(.control) ? "Control" : nil,
            keyDisplayName(for: keyCode)
        ].compactMap { $0 }
        return parts.joined(separator: " + ")
    }

    static let `default` = QuickShortcut(keyCode: 40, modifiersRawValue: NSEvent.ModifierFlags.command.rawValue) // Command + K

    private func keyDisplayName(for code: UInt16) -> String {
        switch code {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let scalar = keyCodeToCharacter[code] {
                return scalar
            }
            return "KeyCode \(code)"
        }
    }

    private var keyCodeToCharacter: [UInt16: String] {
        [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: "."
        ]
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
    private struct StoredPreferences: Codable {
        let quickShortcut: QuickShortcut
        let speechRolePreset: SpeechRolePreset
    }

    static let shared = AppPreferences()

    @Published var quickShortcut: QuickShortcut {
        didSet {
            save()
            NotificationCenter.default.post(name: .luminaQuickShortcutChanged, object: quickShortcut)
        }
    }
    @Published var speechRolePreset: SpeechRolePreset {
        didSet { save() }
    }

    private let storageKey = "lumina.quickShortcut.v2"
    private let speechRoleKey = "lumina.speechRolePreset"
    private let fileURL: URL

    private init() {
        fileURL = Self.makeFileURL()

        if
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(StoredPreferences.self, from: data)
        {
            quickShortcut = stored.quickShortcut
            speechRolePreset = stored.speechRolePreset
        } else {
            quickShortcut = Self.loadShortcut()
            if
                let raw = UserDefaults.standard.string(forKey: speechRoleKey),
                let preset = SpeechRolePreset(rawValue: raw)
            {
                speechRolePreset = preset
            } else {
                speechRolePreset = .balanced
            }
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(quickShortcut) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(speechRolePreset.rawValue, forKey: speechRoleKey)

        let stored = StoredPreferences(quickShortcut: quickShortcut, speechRolePreset: speechRolePreset)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    @discardableResult
    func updateQuickShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let normalized = modifiers.intersection([.command, .shift, .option, .control])
        guard !normalized.isEmpty else { return false }
        quickShortcut = QuickShortcut(keyCode: keyCode, modifiersRawValue: normalized.rawValue)
        return true
    }

    private static func loadShortcut() -> QuickShortcut {
        if
            let data = UserDefaults.standard.data(forKey: "lumina.quickShortcut.v2"),
            let shortcut = try? JSONDecoder().decode(QuickShortcut.self, from: data)
        {
            return shortcut
        }

        if let legacy = UserDefaults.standard.string(forKey: "lumina.quickShortcutPreset") {
            switch legacy {
            case "commandShiftK":
                return QuickShortcut(keyCode: 40, modifiersRawValue: (NSEvent.ModifierFlags.command.union(.shift)).rawValue)
            case "optionSpace":
                return QuickShortcut(keyCode: 49, modifiersRawValue: NSEvent.ModifierFlags.option.rawValue)
            default:
                return .default
            }
        }
        return .default
    }

    private static func makeFileURL() -> URL {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("Lumina/preferences", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app_preferences.json")
    }
}
