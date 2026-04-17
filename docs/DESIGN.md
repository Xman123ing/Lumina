# Lumina 技术设计文档 (Design & Architecture)

## 1. 技术栈选择
- **开发语言**：Swift 5.x / 6.x
- **前端框架**：`SwiftUI`。SwiftUI 在处理 macOS 的 `NSVisualEffectView` 和复杂动画时表现优异，代码简洁，易于实现现代化的 UI 效果。
- **本地存储**：`SQLite` + `GRDB.swift` (或直接封装 SQLite C API)。适合处理千万级词库的极速查询。
- **网络请求**：原生 `URLSession`。利用 `URLSession.bytes(from:)` 处理 Server-Sent Events (SSE)，实现 LLM API 的流式响应。

## 2. 整体架构
Lumina 采用基于 SwiftUI 的声明式 UI 架构，结合单例服务层 (Singleton Service Layer) 的轻量级设计。这种架构在保证应用性能的同时，极大地降低了状态管理的复杂度。

### 架构分层
- **UI 层 (UI Layer)**：负责界面的渲染、用户交互及状态绑定 (`@State`, `@Namespace`)。
- **服务层 (Service Layer)**：包含业务逻辑的封装，如翻译调度 (`TranslatorService`) 和语音合成 (`SpeechService`)。
- **数据层 (Data Layer)**：负责本地数据的持久化存储与检索 (`SQLiteDictionaryStore`)。

## 3. 关键技术点与实现路径

### 3.1 毛玻璃效果与无边框窗口
- **毛玻璃效果**：在 SwiftUI 中封装 `NSVisualEffectView`，设置 `material = .popover` 或 `.hudWindow`，以及 `blendingMode = .behindWindow`，实现高度透明的亚克力效果。
- **无边框窗口**：配置 `NSWindow` 的 `styleMask`，移除标题栏，实现完全自定义的沉浸式窗口。

### 3.2 全局快捷键与划词翻译
- **快捷键监听**：使用 `HotKey` 库或原生 `Carbon` API 监听全局按键事件（如 `Option + Space`），唤醒或隐藏快捷悬浮窗。
- **划词翻译**：通过 macOS 的 Accessibility API 获取当前活动窗口中选中的文本，并自动填充到翻译输入框中。

### 3.3 AI 引擎与流式输出 (SSE)
- **API 客户端**：开发兼容 OpenAI 格式的 LLM API 客户端，支持配置 Base URL 和 API Key。
- **流式解析**：使用 `URLSession` 建立持久连接，解析 Server-Sent Events (SSE) 数据流，将 AI 翻译结果逐字渲染到 SwiftUI 视图中，实现打字机效果。

## 4. 数据层 (Data Layer)
数据层是 Lumina 极速查词的核心，主要由 `SQLiteDictionaryStore` 组成。

### `SQLiteDictionaryStore`
- **SQLite 封装**：直接调用 SQLite 的 C 语言 API（或通过 GRDB.swift），避免了重度 ORM 框架带来的性能损耗，实现了毫秒级的词典检索。
- **数据库初始化与热替换**：
  - 在应用启动时，检查 `~/Library/Application Support/Lumina/dictionaries/ecdict.sqlite3` 是否存在。
  - 如果不存在或数据量过小（< 50,000 条），则自动将内置的 `builtin_dictionary.sqlite3` 拷贝至该路径，实现内置大词库的无缝安装。
- **高性能查询**：
  - `lookup(term:)`：精确匹配单词，利用 `lower(word) = ?` 和索引实现 $O(1)$ 级别的查询。
  - `search(term:limit:)`：模糊搜索，支持前缀匹配 (`LIKE 'word%'`) 和包含匹配 (`LIKE '%word%'`)，并根据匹配类型、单词长度进行排序，提供高质量的候选词。
- **数据导入**：
  - `importFromTSV(fileURL:)`：支持解析 TSV 文件并使用 `INSERT OR REPLACE` 批量导入数据，利用事务 (`BEGIN TRANSACTION` / `COMMIT`) 提升写入性能。

## 5. 服务层 (Service Layer)
服务层充当 UI 与底层能力的桥梁，提供统一的 API。

### `TranslatorService`
- **单例模式**：`static let shared = TranslatorService()`，确保全局唯一的翻译调度中心。
- **本地查词**：封装了对 `SQLiteDictionaryStore` 的 `lookup` 和 `search` 调用。
- **长文本翻译策略**：
  - `translateLocal(text:)`：实现本地逐词回退翻译。将长文本分词后，逐个查询本地词典并拼接释义。
  - `translateAI(text:)`：异步方法 (`async`)，接入 AI 大模型 API，处理长文本的上下文感知翻译。

### `SpeechService`
- **语音合成封装**：基于 `AVFoundation` 的 `AVSpeechSynthesizer`。
- **发音控制**：`speak(_:language:)` 方法支持指定语言（如 `en-US`, `en-GB`, `zh-CN`），并在每次发音前调用 `stopSpeaking(at: .immediate)` 打断之前的发音，确保交互的流畅性。

## 6. UI 层 (UI Layer)
UI 层大量使用了 SwiftUI 的现代特性，打造了沉浸式的 macOS 桌面体验。

### `ContentView`
- **主容器**：管理侧边栏 (`sidebar`)、顶部导航 (`header`) 和内容区域 (`dictionaryView`, `textPhraseView`)。
- **状态管理**：使用 `@State` 管理路由 (`selectedSection`, `translationRoute`)、输入内容 (`dictionaryQuery`, `sourceText`) 和翻译结果 (`dictionaryEntry`, `resultText`)。
- **快捷翻译浮层 (`quickTranslateOverlay`)**：
  - 通过 `ZStack` 和 `zIndex(10)` 叠加在主界面之上。
  - 监听自定义通知 `.luminaQuickTranslateRequested` 触发显示/隐藏。
  - 结合 `MacInputField` 实现类似 Spotlight 的输入体验。

### `MacInputField`
- **原生输入框封装**：使用 `NSViewRepresentable` 封装了 macOS 的 `NSTextField`，以获得更底层的键盘事件控制。
- **事件回调**：支持 `onSubmit` (Enter), `onUp`, `onDown`, `onEscape` 等回调，完美适配快捷翻译浮层的候选词导航需求。

### 自定义修饰器与动画
- **`TabPressBounceStyle`**：自定义 `ButtonStyle`，在按钮按下时产生缩放 (`scaleEffect`) 动画，松开时产生弹簧 (`spring`) 恢复动画，提升点击手感。
- **玻璃拟物化 (Glassmorphism)**：广泛使用 `LinearGradient`、`.ultraThinMaterial`、半透明背景 (`.white.opacity(...)`) 和精细的边框阴影 (`shadow`)，营造出现代感十足的视觉效果。
