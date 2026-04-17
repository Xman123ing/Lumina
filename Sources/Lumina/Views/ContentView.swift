import AppKit
import Charts
import os
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private let logger = Logger(subsystem: "Lumina", category: "UI")
    @Namespace private var tabSliderNamespace
    @StateObject private var appPreferences = AppPreferences.shared

    @State private var selectedSection: AppSection = .dictionary
    @State private var selectedSidebarPanel: SidebarPanel = .translate
    @State private var sidebarCollapsed = true

    @State private var dictionaryQuery = ""
    @State private var dictionaryEntry: DictionaryEntry?
    @State private var dictionaryCandidates: [DictionaryEntry] = []
    @State private var dictionaryResultVisible = false
    @State private var dictionaryCommonVisible = false
    @State private var dictionaryEnglishVisible = false
    @State private var dictionaryFormsVisible = false

    @State private var sourceText = ""
    @State private var resultText = ""
    @State private var isAIWorking = false
    @State private var longTextCardsVisible = false
    @FocusState private var longTextSourceFocused: Bool
    @State private var lastTranslationSucceeded = false
    @State private var translatingStageIndex = 0
    @State private var sourceCharCount = 0
    @State private var quickTranslateVisible = false
    @State private var quickTranslateMode: QuickTranslateMode = .word
    @State private var quickTranslateText = ""
    @State private var quickTranslateEntry: DictionaryEntry?
    @State private var quickCandidates: [DictionaryEntry] = []
    @State private var quickSelectedIndex: Int = 0
    @State private var quickLongResult = ""
    @State private var quickLongIsAIWorking = false
    @State private var showSettingsSheet = false
    @State private var showImporter = false
    @State private var localEntryCount = 0
    @State private var importStatusMessage = ""
    @State private var aiConfigStatusMessage = ""
    @State private var showAISaveToast = false
    @State private var aiProvider: AIProvider = .deepSeek
    @State private var aiAPIKey = ""
    @State private var aiBaseURL = ""
    @State private var aiModel = ""
    @State private var aiSystemPrompt = ""
    @State private var dailyUsage: [AIUsageBucket] = []
    @State private var monthlyUsage: [AIUsageBucket] = []

    private let translator = TranslatorService.shared
    private let speech = SpeechService.shared

    private enum LayoutToken {
        static let sectionGap: CGFloat = 12
        static let cardPadding: CGFloat = 12
        static let cardRadius: CGFloat = 10
        static let chipPaddingH: CGFloat = 10
        static let chipPaddingV: CGFloat = 8
    }

    private let translatingStages = [
        "正在准备请求参数...",
        "正在调用 AI 大模型...",
        "正在整理翻译结果..."
    ]

    private enum SidebarPanel: Hashable {
        case translate
        case history
        case starred
    }

    private enum QuickTranslateMode: Hashable {
        case word
        case longText
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.11),
                    Color(red: 0.16, green: 0.13, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarCollapsed ? 0 : 220)
                    .opacity(sidebarCollapsed ? 0 : 1)
                    .clipped()
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: sidebarCollapsed)

                VStack(spacing: 0) {
                    header

                    Group {
                        switch selectedSidebarPanel {
                        case .translate:
                            switch selectedSection {
                            case .dictionary:
                                dictionaryView
                            case .textPhrase:
                                textPhraseView
                            }
                        case .history:
                            usageHistoryView
                        case .starred:
                            starredView
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
            .padding(24)
            .overlay(alignment: .topLeading) {
                windowControlDots
                    .padding(.leading, 40)
                    .padding(.top, 40)
            }

            if quickTranslateVisible {
                quickTranslateOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.22), value: quickTranslateVisible)
        .onChange(of: sourceText) { _, newValue in
            sourceCharCount = newValue.count
        }
        .onChange(of: selectedSection) { _, newValue in
            if newValue == .textPhrase {
                longTextCardsVisible = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        longTextCardsVisible = true
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    longTextSourceFocused = true
                }
            } else {
                longTextCardsVisible = false
                longTextSourceFocused = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaQuickTranslateRequested)) { _ in
            logger.info("[LuminaInput] received quick translate notification")
            toggleQuickTranslate()
        }
        .onAppear {
            localEntryCount = translator.localEntryCount()
            reloadAISettings()
            reloadUsageMetrics()
            longTextCardsVisible = selectedSection == .textPhrase
            if selectedSection == .textPhrase {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    longTextSourceFocused = true
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            settingsSheet
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try translator.importCustomDictionaryTSV(fileURL: url)
                    localEntryCount = translator.localEntryCount()
                    importStatusMessage = "导入成功，当前词条数：\(localEntryCount)"
                } catch {
                    importStatusMessage = "导入失败：\(error.localizedDescription)"
                }
            case .failure(let error):
                importStatusMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            HStack {
                Spacer()
                if selectedSidebarPanel == .translate {
                    modeTabs
                } else {
                    Text(selectedSidebarPanel == .history ? "Usage History" : "Starred")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 80)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.64))
                        .frame(minWidth: 168, minHeight: 40)
                        .contentShape(Rectangle())
                        .background {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.28), .white.opacity(0.16)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(.white.opacity(0.22), lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "modeSlider", in: tabSliderNamespace)
                            }
                        }
                        .shadow(color: selectedSection == section ? .black.opacity(0.24) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(TabPressBounceStyle())
            }
        }
        .padding(5)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.12), .black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .purple.opacity(0.2), radius: 16, y: 2)
        .overlay(alignment: .top) {
            Capsule()
                .fill(.purple.opacity(0.35))
                .blur(radius: 14)
                .frame(width: 118, height: 12)
                .offset(y: -12)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LUMINA TRANSLATE")
                .font(.system(size: 13, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(.white.opacity(0.56))
                .padding(.leading, 12)
                .padding(.top, 60)
                .padding(.bottom, 14)

            Button {
                selectedSidebarPanel = .translate
            } label: {
                sidebarItem(title: "Translate", icon: "line.3.horizontal", isActive: selectedSidebarPanel == .translate)
            }
            .buttonStyle(.plain)

            Button {
                selectedSidebarPanel = .history
                reloadUsageMetrics()
            } label: {
                sidebarItem(title: "History", icon: "clock", isActive: selectedSidebarPanel == .history)
            }
            .buttonStyle(.plain)

            Button {
                selectedSidebarPanel = .starred
            } label: {
                sidebarItem(title: "Starred", icon: "star", isActive: selectedSidebarPanel == .starred)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                openQuickTranslate()
            } label: {
                sidebarItem(title: "Quick Translate", icon: "magnifyingglass", isActive: false)
            }
            .buttonStyle(.plain)
            Button {
                showSettingsSheet = true
            } label: {
                sidebarItem(title: "Settings", icon: "gearshape", isActive: false)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .background(.black.opacity(0.22))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func sidebarItem(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 14))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isActive ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(isActive ? .white : .white.opacity(0.62))
    }

    private var dictionaryView: some View {
        VStack(spacing: 16) {
            dictionarySearchBar
                .padding(.top, 6)

            if let entry = dictionaryEntry {
                    VStack(alignment: .leading, spacing: LayoutToken.sectionGap) {
                        HStack {
                            Text(entry.term)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Button {
                                    speech.speak(entry.term, language: "en-US")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.82))

                                Text("美 \(displayPhonetic(entry.phoneticUS))")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                            .padding(.horizontal, LayoutToken.chipPaddingH)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule())

                            HStack(spacing: 6) {
                                Button {
                                    speech.speak(entry.term, language: "en-GB")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.82))

                                Text("英 \(displayPhonetic(entry.phoneticUK))")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                            .padding(.horizontal, LayoutToken.chipPaddingH)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule())
                        }

                        Divider().overlay(.white.opacity(0.14))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("常用释义")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.cyan.opacity(0.92))
                            ForEach(Array(entry.definitions.prefix(3)), id: \.self) { definition in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.cyan.opacity(0.75))
                                    Text(definition)
                                        .foregroundStyle(.white.opacity(0.92))
                                        .font(.system(size: 15))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if entry.definitions.count > 3 {
                                Text("更多释义已省略，优先展示常用含义")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LayoutToken.cardPadding)
                        .background(
                            LinearGradient(
                                colors: [.cyan.opacity(0.12), .blue.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                                .stroke(.cyan.opacity(0.24), lineWidth: 1)
                        }
                        .offset(y: dictionaryCommonVisible ? 0 : 18)
                        .opacity(dictionaryCommonVisible ? 1 : 0.02)
                        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: dictionaryCommonVisible)

                        if !entry.englishDefinitions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("English Definition")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.mint.opacity(0.9))
                                ForEach(Array(entry.englishDefinitions.prefix(2)), id: \.self) { english in
                                    Text(english)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(LayoutToken.cardPadding)
                            .background(
                                LinearGradient(
                                    colors: [.mint.opacity(0.12), .teal.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                                    .stroke(.mint.opacity(0.24), lineWidth: 1)
                            }
                            .offset(y: dictionaryEnglishVisible ? 0 : 18)
                            .opacity(dictionaryEnglishVisible ? 1 : 0.02)
                            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: dictionaryEnglishVisible)
                        }

                        let forms = inferredWordForms(for: entry.term)
                        if !forms.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("其他形态")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.orange.opacity(0.9))
                                HStack(spacing: 8) {
                                    ForEach(forms, id: \.label) { form in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(form.label)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.58))
                                            Text(form.value)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.92))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, LayoutToken.chipPaddingH)
                                        .padding(.vertical, LayoutToken.chipPaddingV)
                                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(LayoutToken.cardPadding)
                            .background(
                                LinearGradient(
                                    colors: [.orange.opacity(0.12), .yellow.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: LayoutToken.cardRadius)
                                    .stroke(.orange.opacity(0.22), lineWidth: 1)
                            }
                            .offset(y: dictionaryFormsVisible ? 0 : 18)
                            .opacity(dictionaryFormsVisible ? 1 : 0.02)
                            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: dictionaryFormsVisible)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .offset(y: dictionaryResultVisible ? 0 : 24)
                    .opacity(dictionaryResultVisible ? 1 : 0.02)
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: dictionaryResultVisible)
            } else if !dictionaryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No exact match in local dictionary")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)

                        if !dictionaryCandidates.isEmpty {
                            Text("Similar candidates:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))

                            ForEach(dictionaryCandidates.prefix(8), id: \.term) { candidate in
                                Button {
                                    dictionaryQuery = candidate.term
                                    dictionaryEntry = candidate
                                    triggerDictionaryResultAnimation(for: candidate)
                                } label: {
                                    HStack {
                                        Text(candidate.term)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(candidate.definitions.first ?? "")
                                            .lineLimit(1)
                                            .foregroundStyle(.white.opacity(0.56))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Text("This word is not found in current local database.")
                                .foregroundStyle(.white.opacity(0.8))
                            Text("Tip: import ECDICT for large vocabulary coverage:")
                                .foregroundStyle(.white.opacity(0.7))
                            Text("python Scripts/import_ecdict_csv.py /path/to/ecdict.csv")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.76))
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .offset(y: dictionaryResultVisible ? 0 : 24)
                    .opacity(dictionaryResultVisible ? 1 : 0.02)
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: dictionaryResultVisible)
            }
            Spacer(minLength: 0)
        }
    }

    private var dictionarySearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            MacInputField(
                text: $dictionaryQuery,
                placeholder: "Search word or phrase in local dictionary...",
                fontSize: 18,
                autoFocus: selectedSidebarPanel == .translate && selectedSection == .dictionary,
                onSubmit: { runDictionaryLookup() }
            )
            .frame(height: 28)
            if !dictionaryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    dictionaryQuery = ""
                    dictionaryEntry = nil
                    dictionaryCandidates = []
                    dictionaryResultVisible = false
                    dictionaryCommonVisible = false
                    dictionaryEnglishVisible = false
                    dictionaryFormsVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .buttonStyle(.plain)
                .help("清空输入")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: 560)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onChange(of: dictionaryQuery) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                dictionaryEntry = nil
                dictionaryCandidates = []
                dictionaryResultVisible = false
                dictionaryCommonVisible = false
                dictionaryEnglishVisible = false
                dictionaryFormsVisible = false
            } else {
                // Dictionary lookup is explicitly triggered by Enter.
                dictionaryEntry = nil
                dictionaryCandidates = []
                dictionaryResultVisible = false
                dictionaryCommonVisible = false
                dictionaryEnglishVisible = false
                dictionaryFormsVisible = false
            }
        }
    }

    private var textPhraseView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Source Text", systemImage: "text.alignleft")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        sourceText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .opacity(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
                    .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("清空源内容")
                    Text("\(sourceCharCount) / 5000")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $sourceText)
                        .focused($longTextSourceFocused)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .foregroundStyle(.white.opacity(0.9))
                    if sourceText.isEmpty {
                        Text("Enter phrase or long text to translate...")
                            .foregroundStyle(.white.opacity(0.32))
                            .padding(.top, 2)
                            .padding(.leading, 6)
                    }
                }
                .frame(minHeight: 170)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        speech.speak(sourceText, language: "en-US")
                    } label: {
                        Image(systemName: "speaker.wave.2.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1.0)
                    .help("朗读源文本")
                }
            }
            .padding(16)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1)
            }
            .offset(y: longTextCardsVisible ? 0 : 26)
            .opacity(longTextCardsVisible ? 1 : 0.02)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: longTextCardsVisible)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI Translation Result", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.95))
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                    } label: {
                        Image(systemName: "square.on.square.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIWorking)
                    .opacity((resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIWorking) ? 0.45 : 1.0)
                    .help("复制翻译结果")
                }
                ScrollView {
                    if isAIWorking {
                        translatingInProgressView
                    } else {
                        Text(resultText.isEmpty ? "结果将在这里显示..." : resultText)
                            .font(.system(size: 18, weight: .medium))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(resultText.isEmpty ? .white.opacity(0.45) : .white.opacity(0.96))
                            .padding(.trailing, 4)
                    }
                }
                .frame(minHeight: 170)
            }
            .padding(16)
            .background(resultPanelBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(resultPanelBorder, lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    speech.speak(resultText, language: "zh-CN")
                } label: {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
                .disabled(resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIWorking)
                .opacity((resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIWorking) ? 0.45 : 1.0)
                .help("朗读翻译结果")
            }
            .shadow(color: lastTranslationSucceeded ? .purple.opacity(0.16) : .clear, radius: 14, y: 4)
            .offset(y: longTextCardsVisible ? 0 : 36)
            .opacity(longTextCardsVisible ? 1 : 0.02)
            .animation(.spring(response: 0.5, dampingFraction: 0.84).delay(0.06), value: longTextCardsVisible)

            aiTranslateToolbar(action: runTextTranslation)
        }
    }

    private var usageHistoryView: some View {
        let summary = translator.aiUsageSummary()
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    metricCard(title: "总调用次数", value: "\(summary.totalCalls)")
                    metricCard(title: "总 Token", value: "\(summary.totalTokens)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("最近 14 天调用次数")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Chart(dailyUsage) { item in
                        BarMark(
                            x: .value("Date", item.label),
                            y: .value("Calls", item.calls)
                        )
                        .foregroundStyle(.cyan.gradient)
                    }
                    .frame(height: 190)
                }
                .padding(14)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("最近 6 个月 Token 用量")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Chart(monthlyUsage) { item in
                        BarMark(
                            x: .value("Month", item.label),
                            y: .value("Tokens", item.tokens)
                        )
                        .foregroundStyle(.purple.gradient)
                    }
                    .frame(height: 210)
                }
                .padding(14)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var starredView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starred")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("生词本功能正在完善中。你可以先使用 History 查看 AI 调用统计。")
                .foregroundStyle(.white.opacity(0.76))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func aiTranslateToolbar(action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                action()
            } label: {
                Label("Ask AI", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .shadow(color: .purple.opacity(0.32), radius: 12, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isAIWorking)
            .help(currentAIModelHoverText)
        }
    }

    private var currentAIModelHoverText: String {
        let config = translator.aiConfig()
        return "Provider: \(config.provider.displayName)\nModel: \(config.model)"
    }

    private func runDictionaryLookup() {
        let exact = translator.lookupLocal(term: dictionaryQuery)
        dictionaryCandidates = translator.searchLocalCandidates(term: dictionaryQuery, limit: 10)
        dictionaryEntry = exact ?? dictionaryCandidates.first
        if let entry = dictionaryEntry, !dictionaryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            triggerDictionaryResultAnimation(for: entry)
        } else {
            dictionaryResultVisible = !dictionaryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            dictionaryCommonVisible = false
            dictionaryEnglishVisible = false
            dictionaryFormsVisible = false
        }
        logger.info("[LuminaDict] query=\(self.dictionaryQuery, privacy: .public) exact=\(exact != nil) candidates=\(self.dictionaryCandidates.count)")
    }

    private func triggerDictionaryResultAnimation(for entry: DictionaryEntry) {
        dictionaryResultVisible = false
        dictionaryCommonVisible = false
        dictionaryEnglishVisible = false
        dictionaryFormsVisible = false

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                dictionaryResultVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    dictionaryCommonVisible = true
                }
            }

            if !entry.englishDefinitions.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        dictionaryEnglishVisible = true
                    }
                }
            }

            let forms = inferredWordForms(for: entry.term)
            if !forms.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        dictionaryFormsVisible = true
                    }
                }
            }
        }
    }

    private func runDictionaryAIEnhance() {
        guard var entry = translator.lookupLocal(term: dictionaryQuery) else { return }
        entry = DictionaryEntry(
            term: entry.term,
            phoneticUS: entry.phoneticUS,
            phoneticUK: entry.phoneticUK,
            definitions: entry.definitions + ["AI 补充：在产品语境中，该术语强调半透明图层、模糊背景与分层对比。"],
            englishDefinitions: entry.englishDefinitions
        )
        dictionaryEntry = entry
    }

    private func runTextTranslation() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            isAIWorking = true
            lastTranslationSucceeded = false
            translatingStageIndex = 0
            let stageTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(800))
                    translatingStageIndex = (translatingStageIndex + 1) % translatingStages.count
                }
            }

            let translated = await translator.translateAI(text: text)
            stageTask.cancel()

            resultText = translated
            lastTranslationSucceeded = isLikelySuccessfulAIResponse(translated)
            isAIWorking = false
            reloadUsageMetrics()
        }
    }

    private func isLikelySuccessfulAIResponse(_ text: String) -> Bool {
        let failures = ["AI 翻译失败", "AI 请求失败", "请先在 Settings", "AI 配置无效"]
        return !failures.contains { text.contains($0) }
    }

    private var resultPanelBackground: LinearGradient {
        if lastTranslationSucceeded {
            return LinearGradient(
                colors: [.purple.opacity(0.2), .pink.opacity(0.12), .black.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [.black.opacity(0.18), .black.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var resultPanelBorder: Color {
        lastTranslationSucceeded ? .purple.opacity(0.36) : .white.opacity(0.1)
    }

    private var translatingInProgressView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("AI 正在翻译中...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(translatingStages[translatingStageIndex])
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                stageRow(index: 0, label: translatingStages[0])
                stageRow(index: 1, label: translatingStages[1])
                stageRow(index: 2, label: translatingStages[2])
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func stageRow(index: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: index <= translatingStageIndex ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(index <= translatingStageIndex ? .purple.opacity(0.9) : .white.opacity(0.35))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(index <= translatingStageIndex ? .white.opacity(0.82) : .white.opacity(0.45))
        }
    }

    private func reloadUsageMetrics() {
        dailyUsage = translator.aiUsageDaily(lastDays: 14)
        monthlyUsage = translator.aiUsageMonthly(lastMonths: 6)
    }

    private func reloadAISettings() {
        let config = translator.aiConfig()
        aiProvider = config.provider
        aiAPIKey = config.apiKey
        aiBaseURL = config.baseURL
        aiModel = config.model
        aiSystemPrompt = config.systemPrompt
    }

    private func saveAISettings() {
        let config = AIModelConfig(
            provider: aiProvider,
            apiKey: aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: aiModel.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: aiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        translator.updateAIConfig(config)
        aiConfigStatusMessage = "AI 配置已保存 (\(aiProvider.displayName))"
        withAnimation(.easeOut(duration: 0.2)) {
            showAISaveToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.45)) {
                showAISaveToast = false
            }
        }
    }

    private var windowControlDots: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
        }
    }

    private var quickTranslateOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.45))
                .ignoresSafeArea()
                .onTapGesture {
                    closeQuickTranslate()
                }

            VStack(spacing: 0) {
                Picker("Mode", selection: $quickTranslateMode) {
                    Text("Dictionary").tag(QuickTranslateMode.word)
                    Text("Long Text").tag(QuickTranslateMode.longText)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)

                if quickTranslateMode == .word {
                    MacInputField(
                        text: $quickTranslateText,
                        placeholder: "Quick translate (Word)...",
                        fontSize: 24,
                        autoFocus: quickTranslateVisible,
                        onSubmit: {
                            applyQuickResultToDictionary()
                        },
                        onUp: {
                            guard !quickCandidates.isEmpty else { return }
                            quickSelectedIndex = max(quickSelectedIndex - 1, 0)
                            quickTranslateEntry = quickCandidates[quickSelectedIndex]
                        },
                        onDown: {
                            guard !quickCandidates.isEmpty else { return }
                            quickSelectedIndex = min(quickSelectedIndex + 1, quickCandidates.count - 1)
                            quickTranslateEntry = quickCandidates[quickSelectedIndex]
                        },
                        onEscape: {
                            closeQuickTranslate()
                        }
                    )
                    .frame(height: 64)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .onChange(of: quickTranslateText) { _, newValue in
                        refreshQuickCandidates(with: newValue)
                    }

                    if !quickCandidates.isEmpty {
                        Divider().overlay(.white.opacity(0.1))
                        VStack(spacing: 0) {
                            ForEach(Array(quickCandidates.enumerated()), id: \.element.term) { index, item in
                                Button {
                                    quickSelectedIndex = index
                                    quickTranslateEntry = item
                                } label: {
                                    HStack {
                                        Text(item.term)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(item.definitions.first ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.58))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(index == quickSelectedIndex ? .white.opacity(0.12) : .clear)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }

                    if let entry = quickTranslateEntry {
                        VStack(alignment: .leading, spacing: 8) {
                            if quickCandidates.isEmpty {
                                Divider().overlay(.white.opacity(0.1))
                            }
                            HStack {
                                Text(entry.term)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Button {
                                    speech.speak(entry.term, language: "en-US")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 12)

                            HStack(spacing: 10) {
                                Text("US \(entry.phoneticUS)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.08), in: Capsule())
                                Text("UK \(entry.phoneticUK)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.08), in: Capsule())
                            }
                            Text(entry.definitions.first ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                } else {
                    quickTranslateLongTextPanel
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .frame(width: 600)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: 20)),
                    removal: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(y: 10))
                )
            )
        }
    }

    private func applyQuickResultToDictionary() {
        guard let entry = selectedQuickEntry() else { return }
        selectedSection = .dictionary
        dictionaryQuery = entry.term
        dictionaryEntry = entry
        closeQuickTranslate()
    }

    private func closeQuickTranslate() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            logger.info("[LuminaInput] closeQuickTranslate")
            quickTranslateVisible = false
            quickTranslateMode = .word
            quickTranslateText = ""
            quickTranslateEntry = nil
            quickCandidates = []
            quickSelectedIndex = 0
            quickLongResult = ""
            quickLongIsAIWorking = false
        }
    }

    private func openQuickTranslate() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            logger.info("[LuminaInput] openQuickTranslate")
            quickTranslateVisible = true
            quickTranslateMode = .word
            quickTranslateEntry = nil
            quickCandidates = []
            quickSelectedIndex = 0
            quickLongResult = ""
            quickLongIsAIWorking = false
        }
    }

    private func toggleQuickTranslate() {
        if quickTranslateVisible {
            closeQuickTranslate()
        } else {
            openQuickTranslate()
        }
    }

    private func refreshQuickCandidates(with query: String) {
        quickCandidates = translator.searchLocalCandidates(term: query, limit: 6)
        if quickCandidates.isEmpty {
            quickTranslateEntry = nil
            quickSelectedIndex = 0
        } else {
            quickSelectedIndex = min(quickSelectedIndex, quickCandidates.count - 1)
            quickTranslateEntry = quickCandidates[quickSelectedIndex]
        }
    }

    private func selectedQuickEntry() -> DictionaryEntry? {
        if !quickCandidates.isEmpty, quickSelectedIndex < quickCandidates.count {
            return quickCandidates[quickSelectedIndex]
        }
        return quickTranslateEntry
    }

    private var quickTranslateLongTextPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Long Text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text("\(quickTranslateText.count) / 1500")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.56))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $quickTranslateText)
                    .font(.system(size: 14))
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white.opacity(0.9))
                if quickTranslateText.isEmpty {
                    Text("输入长文本，点击 Ask AI 进行快速翻译...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 7)
                        .padding(.leading, 5)
                }
            }
            .padding(8)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Spacer()
                Button {
                    runQuickTranslateLongText()
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
                .disabled(quickLongIsAIWorking || quickTranslateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(quickLongIsAIWorking ? 0.6 : 1.0)
                .help(currentAIModelHoverText)
            }

            if quickLongIsAIWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在翻译中...")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else if !quickLongResult.isEmpty {
                Text(quickLongResult)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 6)
    }

    private func runQuickTranslateLongText() {
        let text = quickTranslateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            quickLongIsAIWorking = true
            quickLongResult = await translator.translateAI(text: text)
            quickLongIsAIWorking = false
            reloadUsageMetrics()
        }
    }

    private struct WordForm: Hashable {
        let label: String
        let value: String
    }

    private func inferredWordForms(for word: String) -> [WordForm] {
        let base = word.lowercased()
        guard base.range(of: "^[a-z]+$", options: .regularExpression) != nil else { return [] }

        let plural = pluralize(base)
        let third = thirdPerson(base)
        let past = pastTense(base)
        let ing = presentParticiple(base)

        return [
            WordForm(label: "Plural", value: plural),
            WordForm(label: "3rd", value: third),
            WordForm(label: "Past", value: past),
            WordForm(label: "Ing", value: ing)
        ]
    }

    private func displayPhonetic(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/-/" }
        let noBrackets = trimmed
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return "/\(noBrackets)/"
    }

    private func pluralize(_ word: String) -> String {
        if word.hasSuffix("y"), let prev = word.dropLast().last, !"aeiou".contains(prev) {
            return String(word.dropLast()) + "ies"
        }
        if word.hasSuffix("s") || word.hasSuffix("x") || word.hasSuffix("z") || word.hasSuffix("ch") || word.hasSuffix("sh") {
            return word + "es"
        }
        return word + "s"
    }

    private func thirdPerson(_ word: String) -> String {
        pluralize(word)
    }

    private func pastTense(_ word: String) -> String {
        if word.hasSuffix("e") {
            return word + "d"
        }
        if word.hasSuffix("y"), let prev = word.dropLast().last, !"aeiou".contains(prev) {
            return String(word.dropLast()) + "ied"
        }
        return word + "ed"
    }

    private func presentParticiple(_ word: String) -> String {
        if word.hasSuffix("ie") {
            return String(word.dropLast(2)) + "ying"
        }
        if word.hasSuffix("e"), !word.hasSuffix("ee") {
            return String(word.dropLast()) + "ing"
        }
        return word + "ing"
    }

    private var settingsSheet: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    macWindowButton(color: Color(red: 1.0, green: 0.37, blue: 0.34)) {
                        showSettingsSheet = false
                    }
                    .help("关闭")
                    macWindowButton(color: Color(red: 1.0, green: 0.74, blue: 0.18)) {
                        reloadAISettings()
                        aiConfigStatusMessage = "已恢复当前保存配置"
                    }
                    .help("恢复已保存配置")
                    macWindowButton(color: Color(red: 0.15, green: 0.79, blue: 0.25)) {
                        saveAISettings()
                    }
                    .help("保存配置")

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("词典设置")
                                .font(.system(size: 16, weight: .semibold))
                            Text("应用已内置字典，首次启动自动初始化，无需手动导入。")
                                .foregroundStyle(.secondary)

                            Text("当前词条数：\(localEntryCount)")
                                .font(.system(size: 14, weight: .semibold))

                            Text("数据库路径：\(translator.localDatabasePath())")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Divider()

                            Text("切换/导入其他词典（备选）")
                                .font(.system(size: 14, weight: .semibold))

                            Button("导入自定义 TSV/CSV 词典") {
                                showSettingsSheet = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showImporter = true
                                }
                            }

                            Text("推荐大词库：ECDICT（通用、词汇量大）")
                                .foregroundStyle(.secondary)
                            Text("命令行导入：python Scripts/import_ecdict_csv.py /path/to/ecdict.csv")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if !importStatusMessage.isEmpty {
                                Text(importStatusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.green)
                            }

                        Divider()

                        Text("Quick Translate 快捷键")
                            .font(.system(size: 14, weight: .semibold))
                        Picker("快捷键", selection: $appPreferences.quickShortcutPreset) {
                            ForEach(QuickShortcutPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        Text("当前快捷键：\(appPreferences.quickShortcutPreset.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("朗读角色")
                            .font(.system(size: 14, weight: .semibold))
                        Picker("朗读角色", selection: $appPreferences.speechRolePreset) {
                            ForEach(SpeechRolePreset.allCases, id: \.self) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        Text("当前角色：\(appPreferences.speechRolePreset.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("AI 翻译配置")
                                .font(.system(size: 16, weight: .semibold))

                            Picker("Provider", selection: $aiProvider) {
                                ForEach(AIProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .onChange(of: aiProvider) { _, newValue in
                                aiBaseURL = newValue.defaultBaseURL
                                aiModel = newValue.defaultModel
                            }

                            HStack {
                                Text("Base URL")
                                    .frame(width: 90, alignment: .leading)
                                TextField("https://...", text: $aiBaseURL)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Model")
                                    .frame(width: 90, alignment: .leading)
                                TextField("model name", text: $aiModel)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("API Key")
                                    .frame(width: 90, alignment: .leading)
                                SecureField("sk-...", text: $aiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("System Prompt")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $aiSystemPrompt)
                                    .font(.system(size: 12))
                                    .scrollContentBackground(.hidden)
                                    .frame(height: 88)
                                    .padding(8)
                                    .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            }

                            HStack {
                                Button("应用 Provider 默认值") {
                                    aiBaseURL = aiProvider.defaultBaseURL
                                    aiModel = aiProvider.defaultModel
                                }
                                Button("保存 AI 配置") {
                                    saveAISettings()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(14)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
            }

            if showAISaveToast {
                VStack(spacing: 8) {
                    Text("保存成功")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(aiConfigStatusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: 700, height: 640)
    }

    private func macWindowButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.15), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TabPressBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                configuration.isPressed
                ? .easeOut(duration: 0.08)
                : .spring(response: 0.32, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}
