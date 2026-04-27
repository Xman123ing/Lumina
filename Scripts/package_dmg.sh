#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
APP_NAME="Lumina"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/Build/Products/Release/Lumina_Lumina.bundle"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"
ICON_WORK_DIR="$BUILD_DIR/icon"
ICONSET_DIR="$ICON_WORK_DIR/AppIcon.iconset"
ICON_PATH="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
DMG_STAGE_DIR="$BUILD_DIR/dmg_stage"

cd "$ROOT_DIR"

echo "==> Building Release executable"
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  build

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Error: executable not found at $EXECUTABLE_PATH"
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "Error: resource bundle not found at $RESOURCE_BUNDLE_PATH"
  exit 1
fi

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE/Contents/Resources/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Generating app icon"
rm -rf "$ICON_WORK_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICON_WORK_DIR/icon_1024.png" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvasSize = CGFloat(1024)
let iconRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
let image = NSImage(size: iconRect.size)

image.lockFocus()
NSColor.clear.setFill()
iconRect.fill()

let rounded = NSBezierPath(roundedRect: iconRect.insetBy(dx: 80, dy: 80), xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.73, blue: 0.86, alpha: 1.0),
    NSColor(calibratedRed: 0.41, green: 0.45, blue: 0.96, alpha: 1.0),
    NSColor(calibratedRed: 0.74, green: 0.38, blue: 0.96, alpha: 1.0)
])!
gradient.draw(in: rounded, angle: -35)

let glossRect = NSRect(x: 150, y: 560, width: 724, height: 250)
let gloss = NSBezierPath(roundedRect: glossRect, xRadius: 120, yRadius: 120)
NSColor.white.withAlphaComponent(0.12).setFill()
gloss.fill()

let leftBubbleRect = NSRect(x: 180, y: 290, width: 360, height: 300)
let leftBubble = NSBezierPath(roundedRect: leftBubbleRect, xRadius: 110, yRadius: 110)
NSColor.white.withAlphaComponent(0.94).setFill()
leftBubble.fill()
let leftTail = NSBezierPath()
leftTail.move(to: NSPoint(x: 230, y: 295))
leftTail.line(to: NSPoint(x: 185, y: 225))
leftTail.line(to: NSPoint(x: 295, y: 290))
leftTail.close()
NSColor.white.withAlphaComponent(0.94).setFill()
leftTail.fill()

let rightBubbleRect = NSRect(x: 484, y: 360, width: 360, height: 300)
let rightBubble = NSBezierPath(roundedRect: rightBubbleRect, xRadius: 110, yRadius: 110)
NSColor(calibratedRed: 0.07, green: 0.30, blue: 0.66, alpha: 0.9).setFill()
rightBubble.fill()
let rightTail = NSBezierPath()
rightTail.move(to: NSPoint(x: 790, y: 360))
rightTail.line(to: NSPoint(x: 855, y: 300))
rightTail.line(to: NSPoint(x: 735, y: 352))
rightTail.close()
NSColor(calibratedRed: 0.07, green: 0.30, blue: 0.66, alpha: 0.9).setFill()
rightTail.fill()

if let symbol = NSImage(systemSymbolName: "arrow.left.arrow.right.circle.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 210, weight: .bold)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    let symbolRect = NSRect(x: 407, y: 395, width: 210, height: 210)
    NSColor.white.withAlphaComponent(0.96).set()
    configured.draw(in: symbolRect)
}

NSColor.white.withAlphaComponent(0.26).setStroke()
let outerRing = NSBezierPath(roundedRect: iconRect.insetBy(dx: 86, dy: 86), xRadius: 206, yRadius: 206)
outerRing.lineWidth = 8
outerRing.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to render icon PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Failed to write icon PNG: \(error)\n", stderr)
    exit(1)
}
SWIFT

sips -z 16 16 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_WORK_DIR/icon_1024.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_WORK_DIR/icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lumina</string>
  <key>CFBundleDisplayName</key><string>Lumina</string>
  <key>CFBundleIdentifier</key><string>com.pinli.lumina</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>Lumina</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Applying ad-hoc code signature"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Creating DMG"
mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo "Done: $DMG_PATH"
