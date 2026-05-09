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
    private let collapsedWidth: CGFloat = 380
    private let collapsedHeight: CGFloat = 60
    private let expandedHeight: CGFloat = 180

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
        updatePanelSize(height: collapsedHeight, width: collapsedWidth, animated: false)
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
        let contentRect = NSRect(x: 0, y: 0, width: collapsedWidth, height: collapsedHeight)
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

    private func updatePanelSize(height: CGFloat, width: CGFloat, animated: Bool = true) {
        guard let panel else { return }
        let target = max(collapsedHeight, height)
        let targetWidth = max(collapsedWidth, width)
        guard abs(panel.frame.height - target) > 0.5 || abs(panel.frame.width - targetWidth) > 0.5 else { return }

        var frame = panel.frame
        let maxY = frame.maxY
        let midX = frame.midX
        frame.size.width = targetWidth
        frame.size.height = target
        frame.origin.y = maxY - target
        frame.origin.x = midX - targetWidth / 2
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func makeRootView() -> QuickTranslatePanelView {
        QuickTranslatePanelView(
            onClose: { [weak self] in
                self?.hide()
            },
            onPreferredFrameChange: { [weak self] _, hasVisibleResult in
                let width = self?.collapsedWidth ?? 380
                let height = hasVisibleResult ? self?.expandedHeight ?? 180 : self?.collapsedHeight ?? 60
                self?.updatePanelSize(height: height, width: width)
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
    @State private var isModeButtonHovered = false
    @State private var isOpenButtonHovered = false
    @ObservedObject private var appPreferences = AppPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private let translator = TranslatorService.shared
    private let onClose: () -> Void
    private let onPreferredFrameChange: (CGFloat, Bool) -> Void
    private let inputAreaHeight: CGFloat = 60

    private var resolvedColorScheme: ColorScheme {
        appPreferences.themeMode.preferredColorScheme ?? systemColorScheme
    }

    private var isLightAppearance: Bool {
        resolvedColorScheme == .light
    }

    private var hasVisibleResult: Bool {
        if mode == .dictionary {
            return dictionaryEntry != nil || !dictionaryFeedback.isEmpty
        }
        return !longTextResult.isEmpty
    }

    private var preferredHeight: CGFloat {
        hasVisibleResult ? 180 : 60
    }

    init(onClose: @escaping () -> Void, onPreferredFrameChange: @escaping (CGFloat, Bool) -> Void) {
        self.onClose = onClose
        self.onPreferredFrameChange = onPreferredFrameChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .frame(height: inputAreaHeight)

            if hasVisibleResult {
                resultSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
                    .padding(.bottom, 5)
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
        .preferredColorScheme(appPreferences.themeMode.preferredColorScheme)
        .onAppear {
            resetToDefaultMode()
            onPreferredFrameChange(preferredHeight, hasVisibleResult)
        }
        .onChange(of: dictionaryEntry?.term) { _, _ in
            onPreferredFrameChange(preferredHeight, hasVisibleResult)
        }
        .onChange(of: longTextResult) { _, _ in
            onPreferredFrameChange(preferredHeight, hasVisibleResult)
        }
        .onChange(of: dictionaryFeedback) { _, _ in
            onPreferredFrameChange(preferredHeight, hasVisibleResult)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Button {
                modePickerPresented.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isLightAppearance
                            ? .black.opacity(isModeButtonHovered ? 0.28 : 0.2)
                            : .black.opacity(isModeButtonHovered ? 0.36 : 0.24)
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isLightAppearance ? .black.opacity(0.85) : .white.opacity(0.94))
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isModeButtonHovered = isHovering
                }
            }
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
                                .foregroundStyle(isLightAppearance ? .black.opacity(0.88) : .white.opacity(0.95))
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
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isLightAppearance ? .black.opacity(0.85) : .white.opacity(0.94))
                        .frame(width: 22, height: 22)
                        .background(
                            isLightAppearance
                            ? .black.opacity(isOpenButtonHovered ? 0.28 : 0.2)
                            : .black.opacity(isOpenButtonHovered ? 0.36 : 0.24),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isOpenButtonHovered = isHovering
                    }
                }
                .help("Open Lumina")
            }
        }
        .onChange(of: mode) { _, _ in
            dictionaryEntry = nil
            longTextResult = ""
            dictionaryFeedback = ""
            onPreferredFrameChange(preferredHeight, hasVisibleResult)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if mode == .dictionary {
            if let entry = dictionaryEntry {
                let shouldShowIndicator = entry.definitions.count >= 4
                ScrollView(.vertical, showsIndicators: shouldShowIndicator) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("常用释义")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        .purple.opacity(0.95),
                                        .blue.opacity(0.9)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        ForEach(entry.definitions, id: \.self) { definition in
                            Text(verbatim: definition)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.black.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 30)
                .padding(.trailing, 2)
                .padding(.top, 2)
            } else if !dictionaryFeedback.isEmpty {
                ScrollView(.vertical, showsIndicators: dictionaryFeedback.count > 100) {
                    Text(dictionaryFeedback)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.64))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 30)
                .padding(.trailing, 2)
                .padding(.top, 2)
            }
        } else if !longTextResult.isEmpty {
            let shouldShowIndicator = longTextResult.count > 120
            ScrollView(.vertical, showsIndicators: shouldShowIndicator) {
                Text(verbatim: longTextResult)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 30)
            .padding(.trailing, 2)
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
