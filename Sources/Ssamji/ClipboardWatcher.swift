import AppKit

/// NSPasteboard.changeCount 를 폴링해 변화를 감지한다.
/// macOS 26 클립보드 프라이버시: changeCount 확인은 프롬프트를 띄우지 않고,
/// 실제 내용 읽기(capture)에서만 시스템이 접근 정책을 적용한다.
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// M3 다이렉트 페이스트가 스스로 클립보드에 쓸 때 자기 수집을 방지하는 플래그
    var ignoreNextChange = false

    /// 은신 모드: 수집만 일시정지 (changeCount 추적은 계속 — 은신 중 복사한 항목이
    /// 해제 후 뒤늦게 수집되는 일이 없도록 변화를 소비하며 흘려보낸다)
    var isPaused = false

    var onCapture: ((NSPasteboard) -> Void)?

    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval = 0.3) {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = interval / 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreNextChange {
            // 은신 중에도 플래그는 소비한다 — 남겨두면 해제 후 첫 복사가 무시된다
            ignoreNextChange = false
            return
        }
        guard !isPaused else { return }
        guard !PasteboardReader.shouldSkip(pb) else { return }
        onCapture?(pb)
    }
}
