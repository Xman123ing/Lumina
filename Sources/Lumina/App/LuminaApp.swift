import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = AppPreferences.shared

    var body: some Scene {
        WindowGroup("Lumina Translate") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandMenu("Tools") {
                Button("Quick Translate") {
                    NotificationCenter.default.post(name: .luminaQuickTranslateRequested, object: nil)
                }
                .keyboardShortcut(
                    preferences.quickShortcutPreset.keyEquivalent,
                    modifiers: preferences.quickShortcutPreset.modifiers
                )
            }
        }
    }
}
