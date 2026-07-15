#!/bin/zsh
# 쌈지 .app 번들 빌드 스크립트
# SPM 실행 파일을 macOS 앱 번들로 감싼다. TCC(권한) 기억을 위해 ad-hoc 서명 포함.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/쌈지.app"
VERSION="1.6.0"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Ssamji" "$APP/Contents/MacOS/Ssamji"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# SPM 리소스 번들(지역화 .strings) — 없으면 Bundle.module 이 크래시한다
cp -R "$ROOT/.build/release/Ssamji_Ssamji.bundle" "$APP/Contents/Resources/"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <!-- 지원 언어 선언 — 없으면 시스템이 프로세스 언어를 영어로 잡아
         한국어 시스템에서도 영어 UI 가 뜬다 -->
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ko</string>
        <string>en</string>
    </array>
</dict>
</plist>
PLIST

# 메인 번들에도 lproj 마커 — 일부 macOS 버전은 Resources 의 lproj 존재로 언어를 판정한다
mkdir -p "$APP/Contents/Resources/ko.lproj" "$APP/Contents/Resources/en.lproj"
touch "$APP/Contents/Resources/ko.lproj/.keep" "$APP/Contents/Resources/en.lproj/.keep"

# 고정 identity 로 서명해야 TCC 권한(손쉬운 사용 등)이 재빌드 후에도 유지된다.
# "Ssamji Dev Signing" 자체 서명 인증서가 없으면 ad-hoc 으로 폴백 (이 경우 재빌드마다 권한 재부여 필요).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Ssamji Dev Signing"; then
    codesign --force --sign "Ssamji Dev Signing" "$APP"
else
    echo "⚠️  'Ssamji Dev Signing' 인증서 없음 — ad-hoc 서명으로 폴백"
    codesign --force --sign - "$APP"
fi
echo "✅ 번들 완료: $APP"

# /Applications 에 정식 설치
ditto "$APP" "/Applications/쌈지.app"
echo "✅ 설치 완료: /Applications/쌈지.app"

# 새 빌드로 재시작 — 프로세스 이름은 앱 표시명(쌈지)이 아니라 실행 파일명(Ssamji)
if pgrep -x Ssamji > /dev/null; then
    killall Ssamji
    sleep 1
fi
open "/Applications/쌈지.app"
echo "✅ 재시작 완료"
