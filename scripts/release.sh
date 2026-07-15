#!/bin/zsh
# 쌈지 릴리스 패키징: 번들 빌드 → .dmg(+.zip) → sha256 → GitHub Release 업로드
#                    → packaging cask 갱신 → homebrew-tap 리포로 자동 푸시
# 사용: ./scripts/release.sh            (bundle.sh 의 VERSION 사용)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(grep '^VERSION=' "$ROOT/scripts/bundle.sh" | cut -d'"' -f2)
APP="$ROOT/build/쌈지.app"
DMG="$ROOT/build/Ssamji-${VERSION}.dmg"
ZIP="$ROOT/build/Ssamji-${VERSION}.zip"
CASK="$ROOT/packaging/homebrew/ssamji.rb"
TAP_REPO="Minzino/homebrew-tap"

"$ROOT/scripts/bundle.sh"

# --- .zip (호환용, ditto -k 로 Finder 동일 압축) ---
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- .dmg (드래그 설치 이미지: 앱 + Applications 심볼릭 링크) ---
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "쌈지" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

DMG_SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "✅ ${DMG##*/} (sha256: $DMG_SHA)"
echo "✅ ${ZIP##*/}"

# --- GitHub Release (dmg + zip 첨부) ---
if gh release view "v$VERSION" --repo Minzino/ssamji > /dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" "$ZIP" --clobber --repo Minzino/ssamji
else
    gh release create "v$VERSION" "$DMG" "$ZIP" \
        --title "쌈지 v$VERSION" --generate-notes --repo Minzino/ssamji
fi
echo "✅ GitHub Release v$VERSION 업로드 완료"

# --- packaging cask 갱신 (dmg 기준) ---
/usr/bin/sed -i '' -e "s/version \".*\"/version \"$VERSION\"/" \
                   -e "s/sha256 \".*\"/sha256 \"$DMG_SHA\"/" "$CASK"

# --- homebrew-tap 리포로 자동 푸시 ---
TAP="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAP" -- -q
mkdir -p "$TAP/Casks"
cp "$CASK" "$TAP/Casks/ssamji.rb"
if [ -n "$(git -C "$TAP" status --porcelain)" ]; then
    git -C "$TAP" add Casks/ssamji.rb
    git -C "$TAP" commit -q -m "ssamji $VERSION (sha $DMG_SHA)"
    git -C "$TAP" push -q
    echo "✅ homebrew-tap 갱신·푸시 완료"
else
    echo "ℹ️  homebrew-tap 변경 없음"
fi
rm -rf "$TAP"

echo ""
echo "설치 확인: brew install --cask minzino/tap/ssamji --no-quarantine"
