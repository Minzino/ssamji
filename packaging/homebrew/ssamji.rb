# 쌈지 Homebrew cask — 공개 시 github.com/Minzino/homebrew-tap 리포의 Casks/ssamji.rb 로 복사.
# 새 릴리스마다 version/sha256 갱신 (scripts/release.sh 가 값을 출력해준다).
cask "ssamji" do
  version "1.5.0"
  sha256 "ef39aa1d2bc53ea33b2f8241d9dbca8ef032180293a4578bcca40c7aea05b8c5"

  url "https://github.com/Minzino/ssamji/releases/download/v#{version}/Ssamji-#{version}.zip"
  name "Ssamji"
  desc "Fast, keyboard-first clipboard manager for macOS"
  homepage "https://github.com/Minzino/ssamji"

  depends_on macos: ">= :sequoia"

  app "쌈지.app"

  caveats <<~EOS
    현재 자체 서명 빌드입니다. 설치는 --no-quarantine 플래그를 권장하며,
    아니면 첫 실행 시 우클릭 → 열기로 Gatekeeper 를 통과하세요.
      brew install --cask minzino/tap/ssamji --no-quarantine
  EOS
end
