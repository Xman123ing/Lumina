# Lumina 技术设计文档 (Design & Architecture)

## 1. 技术栈

- 语言：Swift 6.2
- UI：SwiftUI + AppKit（`NSWindow` / `NSPanel` / `NSStatusItem`）
- 数据：SQLite（内置词库 + 用户词库）
- 网络：`URLSession`（OpenAI 兼容 API）
- 语音：`AVSpeechSynthesizer`

## 2. 分层架构

### 2.1 UI 层

- `ContentView`：主窗口路由、Dictionary/Long Text 页面、Settings/History/Starred
- `QuickTranslatePanelView`：Quick Translate 迷你窗 UI
- `MacInputField`：基于 `NSTextField` 的 SwiftUI 封装，支持提交、Esc、自动聚焦

### 2.2 应用层

- `AppDelegate`：应用生命周期、菜单栏、全局快捷键注册、窗口行为协调
- `QuickTranslatePanelController`：独立 `NSPanel` 创建、展示、尺寸与失焦隐藏控制
- `AppPreferences`：偏好项读写（快捷键、朗读角色等）

### 2.3 服务层

- `TranslatorService`：本地词典检索、AI 翻译调用、使用量统计
- `SpeechService`：文本朗读与角色化声音参数

### 2.4 数据层

- `SQLiteDictionaryStore`：本地词库初始化、查询、导入
- 资源词库：`Sources/Lumina/Resources/builtin_dictionary.sqlite3`

## 3. 关键设计决策

## 3.1 Quick Translate 使用独立窗口

- 采用独立 `NSPanel`，避免主界面叠层导致的双层背景问题
- 每次隐藏后释放 panel 与 hostingView，确保下次唤起为干净状态
- 失焦自动关闭，行为对齐 Spotlight

## 3.2 主窗口与菜单栏协同

- 关闭主窗口默认不退出进程，转为菜单栏常驻
- 菜单栏提供：Quick Translate、Open App、Quit

## 3.3 结果展示策略

- 主窗口和 quick 窗口都采用“固定容器 + 可滚动内容”，避免内容挤压窗口
- 对异常字符做 Unicode 清洗，降低 AI 输出符号污染

## 3.4 配置持久化

- 关键配置双存储（`UserDefaults` + JSON）
- 目标是在升级后尽量保持用户配置不丢失

## 4. 打包与发布

- 脚本：`Scripts/package_dmg.sh`
- 步骤：Release 构建 -> 组装 `.app` -> 生成图标 -> ad-hoc 签名 -> 生成 DMG
- 输出：`release/Lumina.dmg`

## 5. 当前技术债与后续优化方向

- 将 quick 窗口尺寸策略进一步参数化（便于产品侧快速微调）
- 为 AI 翻译补充更细粒度错误分类与重试策略
- 完善 History / Starred 的数据模型与持久化落地
