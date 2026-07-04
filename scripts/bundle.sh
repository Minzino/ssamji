#!/bin/zsh
# 쌈지 .app 번들 빌드 스크립트
# SPM 실행 파일을 macOS 앱 번들로 감싼다. TCC(권한) 기억을 위해 ad-hoc 서명 포함.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/쌈지.app"
VERSION="0.1.0"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Ssamji" "$APP/Contents/MacOS/Ssamji"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Ssamji</string>
    <key>CFBundleIdentifier</key><string>com.meenzino.ssamji</string>
    <key>CFBundleName</key><string>쌈지</string>
    <key>CFBundleDisplayName</key><string>쌈지</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.4</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✅ 번들 완료: $APP"
