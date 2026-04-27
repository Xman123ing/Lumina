import AppKit
import SwiftUI

private final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class QuickTranslatePanelController: NSObject, NSWindowDelegate {
    private var panel: SpotlightPanel?
    private var hostingView: NSHostingView<QuickTranslatePanelView>?

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            buildPanel()
        }
        guard let panel else { return }
        if let hostingView {
            hostingView.rootView = makeRootView()
        }
        position(panel: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.delegate = nil
        hostingView = nil
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func buildPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 60)
        let panel = SpotlightPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let root = makeRootView()
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = contentRect
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 22
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.cornerRadius = 22
        panel.contentView?.layer?.masksToBounds = true

        self.panel = panel
        self.hostingView = hostingView
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 140
        )
        panel.setFrameOrigin(origin)
    }

    private func updatePanelHeight(_ height: CGFloat) {
        guard let panel else { return }
        let target = max(60, height)
        guard abs(panel.frame.height - target) > 0.5 else { return }

        var frame = panel.frame
        let maxY = frame.maxY
        frame.size.height = target
        frame.origin.y = maxY - target
        panel.setFrame(frame, display: true, animate: true)
    }

    private func makeRootView() -> QuickTranslatePanelView {
        QuickTranslatePanelView(
            onClose: { [weak self] in
                self?.hide()
            },
            onPreferredHeightChange: { [weak self] height in
                self?.updatePanelHeight(height)
            }
        )
    }
}

private struct QuickTranslatePanelView: View {
    private enum Mode: Hashable {
        case dictionary
        case longText
    }

    @State private var mode: Mode = .dictionary
    @State private var text = ""
    @State private var dictionaryEntry: DictionaryEntry?
    @State private var longTextResult = ""
    @State private var dictionaryFeedback = ""
    @State private var isAIWorking = false
    @State private var modePickerPresented = false

    private let translator = TranslatorService.shared
    private let onClose: () -> Void
    private let onPreferredHeightChange: (CGFloat) -> Void

    private var hasVisibleResult: Bool {
        if mode == .dictionary {
            return dictionaryEntry != nil || !dictionaryFeedback.isEmpty
        }
        return !longTextResult.isEmpty
    }

    private var preferredHeight: CGFloat {
        if mode == .dictionary, let entry = dictionaryEntry {
            let definitionsHeight = min(110, CGFloat(max(1, entry.definitions.count)) * 12)
            return 65 + definitionsHeight
        }
        if mode == .dictionary, !dictionaryFeedback.isEmpty {
            return 82
        }
        if mode == .longText, !longTextResult.isEmpty {
            return 110
        }
        return 60
    }

    init(onClose: @escaping () -> Void, onPreferredHeightChange: @escaping (CGFloat) -> Void) {
        self.onClose = onClose
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasVisibleResult {
                inputRow
                    .padding(.top, 4)

                resultSection
                    .padding(.bottom, 5)
            } else {
                inputRow
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 380, height: preferredHeight, alignment: hasVisibleResult ? .top : .center)
        .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.38), lineWidth: 0.36)
                .blendMode(.screen)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
        .onAppear {
            resetToDefaultMode()
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: dictionaryEntry?.term) { _, _ in
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: longTextResult) { _, _ in
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: dictionaryFeedback) { _, _ in
            onPreferredHeightChange(preferredHeight)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Button {
                modePickerPresented.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $modePickerPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        mode = .dictionary
                        modePickerPresented = false
                    } label: {
                        HStack {
                            Text("Dictionary")
                            Spacer()
                            if mode == .dictionary {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(width: 140)
                    }
                    .buttonStyle(.plain)

                    Button {
                        mode = .longText
                        modePickerPresented = false
                    } label: {
                        HStack {
                            Text("Long Text")
                            Spacer()
                            if mode == .longText {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(width: 140)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }

            HStack(spacing: 10) {
                MacInputField(
                    text: $text,
                    placeholder: mode == .dictionary ? "Quick translate (Word)..." : "Translate Long Text...",
                    fontSize: 21,
                    inputTextColor: .black,
                    autoFocus: true,
                    onSubmit: {
                        submit()
                    },
                    onEscape: {
                        onClose()
                    }
                )

                if !text.isEmpty {
                    Button {
                        text = ""
                        dictionaryEntry = nil
                        longTextResult = ""
                        dictionaryFeedback = ""
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.45))
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                if isAIWorking {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    openMainApp()
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Lumina")
            }
        }
        .onChange(of: mode) { _, _ in
            dictionaryEntry = nil
            longTextResult = ""
            dictionaryFeedback = ""
            onPreferredHeightChange(preferredHeight)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if mode == .dictionary {
            if let entry = dictionaryEntry {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("常用释义")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.72))
                        ForEach(entry.definitions, id: \.self) { definition in
                            Text(verbatim: definition)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.black.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 56)
                .padding(.leading, 30)
                .padding(.trailing, 12)
                .padding(.top, 2)
            } else if !dictionaryFeedback.isEmpty {
                Text(dictionaryFeedback)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black.opacity(0.64))
                    .padding(.leading, 30)
                    .padding(.top, 2)
            }
        } else if !longTextResult.isEmpty {
            ScrollView(.vertical, showsIndicators: true) {
                Text(verbatim: longTextResult)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 56)
            .padding(.leading, 30)
            .padding(.trailing, 12)
            .padding(.top, 2)
        }
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if mode == .dictionary {
            let candidates = translator.searchLocalCandidates(term: query, limit: 1)
            dictionaryEntry = candidates.first
            dictionaryFeedback = dictionaryEntry == nil ? "未找到本地词典结果" : ""
        } else {
            isAIWorking = true
            Task {
                let translated = await translator.translateAI(text: query)
                await MainActor.run {
                    longTextResult = normalizedQuickResultText(translated)
                    isAIWorking = false
                }
            }
        }
    }

    private func resetToDefaultMode() {
        mode = .dictionary
        modePickerPresented = false
        text = ""
        dictionaryEntry = nil
        longTextResult = ""
        dictionaryFeedback = ""
        isAIWorking = false
    }

    private func normalizedQuickResultText(_ raw: String) -> String {
        let cleanedScalars = raw.unicodeScalars.filter { scalar in
            let value = scalar.value

            // Keep newline/tab for readable formatting.
            if value == 0x0A || value == 0x09 {
                return true
            }

            // Remove C0/C1 controls and DEL.
            if value < 0x20 || (0x7F...0x9F).contains(value) {
                return false
            }

            // Remove zero-width and BOM-like invisibles.
            if [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0xFFFC].contains(value) {
                return false
            }

            // Remove Unicode Private Use Areas (often renders as odd icon glyphs).
            if (0xE000...0xF8FF).contains(value) ||
                (0xF0000...0xFFFFD).contains(value) ||
                (0x100000...0x10FFFD).contains(value) {
                return false
            }

            return true
        }

        return String(String.UnicodeScalarView(cleanedScalars))
            .replacingOccurrences(of: "\t", with: "    ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openMainApp() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .luminaOpenAppRequested, object: nil)
        let mainWindow = NSApp.windows.first { !($0 is NSPanel) }
        mainWindow?.makeKeyAndOrderFront(nil)
        onClose()
    }
}
