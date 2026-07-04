# 쌈지 (Ssamji)

macOS 26+ 네이티브 클립보드 매니저. Paste 2의 핵심 경험을 계승하되, Tahoe의 클립보드 프라이버시 정책에 정공법으로 대응한다.

- 기획서: `~/dev/test/clipboard-app-plan.md` (v1.1)
- 스택: Swift 6 / SwiftUI + NSPanel / GRDB + FTS5 / CGEvent

## 빌드 & 실행

```sh
./scripts/bundle.sh   # swift build + .app 번들 생성 + ad-hoc 서명
open build/쌈지.app
```

## 마일스톤

- [x] M0 스켈레톤 — 메뉴바 앱, 권한 온보딩(클립보드·손쉬운 사용)
- [x] M1 수집 엔진 — pasteboard watcher, 타입 감지, dedup, DB 저장
- [x] M2 패널 UI — 중앙 팔레트(검색+리스트+프리뷰), 키보드 네비
- [x] M3 붙여넣기 — 다이렉트 페이스트, plain 변환, ⌘1–9
- [x] M4 핀보드 — 보드 관리 + 시크릿 보드(마스킹, ⌥ 피킹, 라벨) + 다이렉트 페이스트 토글
- [ ] M5 깔롱+파워 — 애니메이션, 스마트 카드, 테마, 변환 팔레트, 페이스트 스택, 제외 규칙
- [x] M6 이주·마감 — Paste.db 임포트(항목·보드·라벨·외부블롭), 로그인 시 시작
