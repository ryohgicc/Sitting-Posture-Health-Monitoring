#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/坐姿搭子.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/PosturePal" "$APP_DIR/Contents/MacOS/PosturePal"
mkdir -p "$APP_DIR/Contents/Resources/Models"
cp "$PROJECT_DIR/Vendor/"{libmediapipe.dylib,pose_landmarker_lite.task,MediaPipe-LICENSE.txt,README.md} "$APP_DIR/Contents/Resources/Models/"
codesign --force --sign - "$APP_DIR/Contents/Resources/Models/libmediapipe.dylib"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.posturepal.mac</string>
<key>CFBundleName</key><string>坐姿搭子</string>
<key>CFBundleDisplayName</key><string>坐姿搭子</string>
<key>CFBundleExecutable</key><string>PosturePal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>在本机分析头部与肩部关键点，提醒持续姿态变化。画面不录制、不保存、不上传。</string>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --identifier local.posturepal.mac "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
print -r -- "$APP_DIR"
