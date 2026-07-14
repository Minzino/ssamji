<p align="center">
  <img src="Assets/icon_1024.png" width="128" alt="Ssamji icon">
</p>

<h1 align="center">Ssamji (쌈지)</h1>

<p align="center">
  A fast, keyboard-first clipboard manager for macOS — born the day macOS 26 broke my favorite one.
  <br>
  <a href="README.ko.md"><b>한국어 README</b></a>
</p>

---

**Ssamji** (쌈지 — a traditional Korean pouch for carrying precious little things) keeps everything you copy, makes it searchable in milliseconds, and pastes it back with a single keystroke. Everything stays on your Mac: no account, no network, no telemetry.

## Why

macOS 26 (Tahoe) introduced clipboard privacy restrictions that broke long-unmaintained clipboard managers. Instead of waiting for a fix that might never come, Ssamji was built from scratch for the new rules — it asks for the right permissions and works *with* the system, not around it.

## Features

- **Central palette** (`⌘⇧V` by default, configurable) — search field, result list, and rich preview in one non-activating panel. Your current app keeps focus.
- **Direct paste** — `Enter` pastes straight into the frontmost app (via Accessibility). `Shift Enter` copies only. `⌘1–9` pastes instantly.
- **Boards** — organize clips into pinned collections. Boards are independent spaces: deleting from history never touches board items. Create (`⌘N`), assign (`⌘P`), switch (`⌘[` / `⌘]`), reorder (`⌘⇧←→`).
- **Secret boards** — masked previews, labels instead of content, hold `⌥` to peek. (At-rest encryption with Touch ID is on the roadmap.)
- **Paste stack** — collect several clips (`⌘K`), then paste them all at once (`⌘⏎`) joined by newline, space, comma, `&&`, or sequentially.
- **Transform paste** (`⌘T`) — upper/lower case, trim, kebab/snake case, JSON pretty-print, and terminal-friendly variants.
- **Real full-text search** — SQLite FTS5 with a trigram tokenizer: substring matching that works for Korean (and everything else), debounced so typing never lags.
- **Migrate from Paste** — one-click import of your entire Paste library (boards, labels, and images included).
- **Stealth mode** (`⌘⇧E`) — pause collection instantly; the menu bar icon dims while paused.
- **App exclusions** (`⌘E`) — never collect from password managers or any app you choose.
- **Retention policy** — keep history 1–90 days or forever; board items are always preserved.
- **Localized** — English and Korean, follows your system language.

Press `⌘/` inside the palette for the full shortcut reference.

## Install

Requires **macOS 15.4+**. Build from source (Xcode command line tools with the Swift 6 toolchain):

```bash
git clone https://github.com/Minzino/ssamji.git
cd ssamji
./scripts/bundle.sh   # builds, signs, installs to /Applications, and relaunches
```

On first run, grant two permissions:

1. **Clipboard access** — System Settings → Privacy & Security → set Ssamji to *Always Allow* (macOS 26).
2. **Accessibility** — required for direct paste (`⌘V` synthesis). Without it, `Enter` copies to the clipboard instead.

> The bundled script signs with a local self-signed certificate. Prebuilt, notarized releases are planned.

## Privacy

- Everything is stored locally in `~/Library/Application Support/Ssamji/`.
- No network access, no analytics, no account.
- Content marked concealed by the system (`org.nspasteboard.ConcealedType`, e.g. password managers) is never collected.

## Performance

Ssamji is built around a strict "no jank" contract: precomputed previews, memoized rows, CJK font-fallback pre-resolution, and key-repeat-aware preview deferral. Scrolling hundreds of items or switching boards stays within a single frame budget on Apple silicon.

## Roadmap

- Secret board vault — AES-GCM encryption at rest + Touch ID to reveal
- iCloud sync (CloudKit)
- Notarized binary releases / Homebrew cask
- Frecency-based ranking

## License

[MIT](LICENSE)
