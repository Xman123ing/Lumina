import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Lumina Translate") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandMenu("Tools") {
                Button("Quick Translate") {
                    NotificationCenter.default.post(name: .luminaQuickTranslateRequested, object: nil)
                }
            }
        }
    }
}
