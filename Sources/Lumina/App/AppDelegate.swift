import AppKit
import Carbon.HIToolbox
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "Lumina", category: "Lifecycle")
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private weak var mainWindow: NSWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private let hotKeyId = EventHotKeyID(signature: 0x4C4D4E41, id: 1) // "LMNA"
    private let quickPanelController = QuickTranslatePanelController()
    private var hasAppliedInitialWindowFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        logger.info("[LuminaInput] app activated with regular policy")
        setupStatusBarItem()
        setupGlobalQuickShortcut()

        DispatchQueue.main.async {
            self.bindMainWindowIfNeeded()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeMain),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickShortcutChanged),
            name: .luminaQuickShortcutChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickTranslateRequested),
            name: .luminaQuickTranslateRequested,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc private func handleWindowDidBecomeMain(_ notification: Notification) {
        bindMainWindowIfNeeded()
    }

    @objc private func handleQuickShortcutChanged(_ notification: Notification) {
        registerGlobalHotKey()
    }

    @objc private func handleQuickTranslateRequested(_ notification: Notification) {
        quickPanelController.toggle()
    }

    private func bindMainWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        mainWindow = window
        window.delegate = self
        // Disable window restoration to avoid launch-time frame jump.
        window.isRestorable = false
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.miniaturizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if !hasAppliedInitialWindowFrame {
            applyDefaultWindowFrame(to: window)
            hasAppliedInitialWindowFrame = true
        }
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let fallbackIcon = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Lumina") ?? NSImage(size: NSSize(width: 18, height: 18))
        let baseIcon = NSApp.applicationIconImage ?? fallbackIcon
        let icon = (baseIcon.copy() as? NSImage) ?? baseIcon
        icon.size = NSSize(width: 18, height: 18)
        item.button?.image = icon
        item.button?.image?.isTemplate = false
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Mini Chat", action: #selector(handleQuickLumina), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open App", action: #selector(handleShowLumina), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lumina", action: #selector(handleQuitLumina), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusMenu = menu
        statusItem = item
    }

    @objc private func handleStatusItemClick() {
        guard
            let event = NSApp.currentEvent,
            let button = statusItem?.button
        else { return }

        if event.type == .rightMouseUp {
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        } else {
            handleQuickLumina()
        }
    }

    @objc private func handleQuickLumina() {
        NotificationCenter.default.post(name: .luminaQuickTranslateRequested, object: nil)
    }

    @objc private func handleShowLumina() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .luminaOpenAppRequested, object: nil)
        quickPanelController.hide()
        if let window = mainWindow ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        }
    }

    @objc private func handleQuitLumina() {
        NSApp.terminate(nil)
    }

    private func setupGlobalQuickShortcut() {
        installHotKeyHandlerIfNeeded()
        registerGlobalHotKey()
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else { return noErr }

            var hotKeyId = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyId
            )
            guard status == noErr else { return status }

            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyId.signature == delegate.hotKeyId.signature, hotKeyId.id == delegate.hotKeyId.id {
                Task { @MainActor in
                    delegate.handleQuickLumina()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )
    }

    private func registerGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let shortcut = AppPreferences.shared.quickShortcut
        let carbonModifiers = carbonModifiers(from: shortcut.modifiers)
        guard carbonModifiers != 0 else { return }

        var newRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        if registerStatus == noErr {
            hotKeyRef = newRef
            logger.info("[LuminaInput] global quick shortcut registered")
        } else {
            logger.error("[LuminaInput] failed to register shortcut: \(registerStatus)")
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private func applyDefaultWindowFrame(to window: NSWindow) {
        let defaultSize = NSSize(width: 1100, height: 720)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - defaultSize.width / 2,
            y: visibleFrame.midY - defaultSize.height / 2
        )
        window.contentMinSize = NSSize(width: 960, height: 640)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.setFrame(NSRect(origin: origin, size: defaultSize), display: true, animate: false)
    }
}
