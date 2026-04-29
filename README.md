# Lumina

Lumina 是一个面向 macOS 的原生翻译应用，支持：

- 本地离线词典（SQLite / ECDICT）
- Quick Translate 迷你浮窗（Spotlight 风格）
- 长文本 AI 翻译（OpenAI 兼容接口）
- 原生 TTS 朗读（含朗读角色配置）
- 菜单栏驻留与全局快捷键唤起

## 环境要求

- macOS 14+
- Xcode 16+
- Swift 6.2（见 `Package.swift`）

## 本地运行（Debug）

```bash
cd /Users/pinli/Workshop/Lumina
xcodebuild -scheme Lumina -configuration Debug -destination "platform=macOS" -derivedDataPath build build
```

可执行文件输出在：

- `build/Build/Products/Debug/Lumina`

## 生成 DMG（Release）

项目已提供一键脚本：`Scripts/package_dmg.sh`。

```bash
cd /Users/pinli/Workshop/Lumina
chmod +x Scripts/package_dmg.sh
./Scripts/package_dmg.sh
```

脚本会自动完成：

- Release 构建
- 组装 `.app` 包
- 生成应用图标（`AppIcon.icns`）
- `codesign`（ad-hoc）
- 生成标准拖拽安装 DMG（左侧 App、右侧 `Applications`）

生成产物：

- `release/Lumina.dmg`

## 内置词库与导入

- 内置词库文件：`Sources/Lumina/Resources/builtin_dictionary.sqlite3`
- 首次启动会自动安装到用户目录：
  - `~/Library/Application Support/Lumina/dictionaries/ecdict.sqlite3`
- 支持两种导入方式：
  - Settings 页面导入 TSV/CSV
  - 命令行导入 ECDICT CSV：

```bash
python Scripts/import_ecdict_csv.py /path/to/ecdict.csv
```
