#!/bin/zsh
# 쌈지 릴리스 패키징: 번들 빌드 → zip → sha256 → GitHub Release 업로드
# 사용: ./scripts/release.sh            (bundle.sh 의 VERSION 사용)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(grep '^VERSION=' "$ROOT/scripts/bundle.sh" | cut -d'"' -f2)
APP="$ROOT/build/쌈지.app"
ZIP="$ROOT/build/Ssamji-${VERSION}.zip"

"$ROOT/scripts/bundle.sh"

rm -f "$ZIP"
# ditto -k: Finder 와 동일한 zip (리소스 포크·심볼릭 링크 보존)
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "✅ ${ZIP##*/} (sha256: $SHA)"

# 태그가 있으면 릴리스 생성/자산 업로드 (gh CLI)
if gh release view "v$VERSION" --repo Minzino/ssamji > /dev/null 2>&1; then
    gh release upload "v$VERSION" "$ZIP" --clobber --repo Minzino/ssamji
else
    gh release create "v$VERSION" "$ZIP" --title "쌈지 v$VERSION" --generate-notes --repo Minzino/ssamji
fi
echo "✅ GitHub Release v$VERSION 업로드 완료"
echo ""
echo "homebrew-tap 의 Casks/ssamji.rb 갱신용:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
