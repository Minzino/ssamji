import AppKit
import SwiftUI

/// 팔레트를 담는 비활성화(nonactivating) 패널.
/// 이전 앱의 포커스를 뺏지 않으면서 키 입력은 받는다 — M3 다이렉트 페이스트의 전제 조건.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 팔레트 창의 생성/표시/숨김과 키보드 내비게이션을 관리한다.
@MainActor
final class PaletteController {
    let viewModel: PaletteViewModel

    private var panel: PalettePanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(store: Store) {
        viewModel = PaletteViewModel(store: store)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 앱 시작 시 패널을 미리 생성 — 첫 개방 시 뷰 생성·onAppear 포커스 확립이
    /// 이미 끝나 있어 "열자마자 타이핑" 반응이 재개방과 같아진다.
    func prewarm() {
        _ = ensurePanel()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        viewModel.reset()
        center(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        applyShowMotion(to: panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    /// 퇴장은 항상 등장(140ms)보다 빠르다 (매듭 모션 원칙).
    /// - Parameter animated: false 면 애니메이션 생략, 즉시 orderOut —
    ///   다이렉트 페이스트 커밋 경로 전용 (합성 ⌘V 전에 패널이 완전히 사라져야 한다).
    func hide(animated: Bool = true) {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        guard animated else {
            panel.contentView?.layer?.removeAnimation(forKey: Self.showMotionKey)
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    // MARK: - 매듭 모션 (등장)

    private static let showMotionKey = "ssamji.show"

    /// 등장 모션: scale 0.98→1.00 + translateY 8→0 — 기존 alpha 페이드 위에 얹는다.
    /// SwiftUI 트리 무접촉(성능 헌법): CABasicAnimation 은 콘텐츠 뷰의 CALayer
    /// 프레젠테이션 트리에서만 돌고, 모델 값은 identity 그대로라
    /// body 재평가·트랜잭션이 일절 발생하지 않는다.
    private func applyShowMotion(to panel: PalettePanel) {
        guard let layer = panel.contentView?.layer else { return }
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let scale: CGFloat = 0.98
        // 아래에서 8px 솟아오름 — 레이어 지오메트리 뒤집힘 여부에 따라 부호 결정
        let dropY: CGFloat = layer.isGeometryFlipped ? 8 : -8
        // 중심 기준 스케일: 원점 스케일 후 중심이 제자리로 오도록 평행이동으로 보정
        var from = CATransform3DMakeTranslation(
            size.width * (1 - scale) / 2,
            size.height * (1 - scale) / 2 + dropY,
            0
        )
        from = CATransform3DScale(from, scale, scale, 1)
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        anim.duration = 0.14
        // easeOutExpo 계열 — 빠르게 도착해 매듭짓는 감각
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.19, 1.0, 0.22, 1.0)
        layer.removeAnimation(forKey: Self.showMotionKey)
        layer.add(anim, forKey: Self.showMotionKey)
    }

    // MARK: - Panel

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }

        let content = PaletteView()
            .environmentObject(viewModel)

        let hosting = NSHostingView(rootView: content)
        // 팔레트는 720×440 고정 — SwiftUI 내용물 크기로 제약을 재계산하지 않는다.
        // (기본값이면 키 입력마다 전체 뷰 그래프 sizeThatFits 가 돌아 레이아웃 히치 발생)
        hosting.sizingOptions = []
        // 등장 모션(CABasicAnimation)을 걸 레이어 확보 — NSHostingView 가 이미 레이어 backing
        // 이지만 명시해 둔다 (레이어가 없으면 모션만 조용히 생략되고 페이드는 유지)
        hosting.wantsLayer = true
        // 레이어 자체를 라운드 마스킹 — SwiftUI 도형 라운드에만 의존하면 잦은 재그리기
        // (검색 타이핑 등) 때 윈도우 그림자/불투명 영역이 사각 레이어 기준으로 재계산되어
        // 모서리가 직각으로 보이는 아티팩트가 생긴다 (2026-07-15 사용자 보고)
        hosting.layer?.cornerRadius = 14
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        let p = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 440)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        panel = p
        return p
    }

    private func center(_ panel: NSPanel) {
        // 마우스가 있는 화면의 중앙보다 살짝 위 (Spotlight 위치 감각)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + frame.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.type == .flagsChanged {
                self.handleFlags(event)
                return event
            }
            if event.type == .keyUp {
                // 방향키를 뗐을 때 — 보류했던 프리뷰 갱신 재개
                if event.keyCode == 125 || event.keyCode == 126 {
                    self.viewModel.endKeyRepeat()
                }
                return event
            }
            return self.handle(event) ? nil : event
        }
    }

    /// ⌥ 를 누르고 있는 동안 시크릿 내용 피킹 (떼면 자동으로 다시 가림)
    private func handleFlags(_ event: NSEvent) {
        let optionHeld = event.modifierFlags.contains(.option)
        if optionHeld,
           let item = viewModel.selectedItem,
           viewModel.isMasked(item) {
            viewModel.secretRevealed = true
        } else if !optionHeld, viewModel.secretRevealed {
            viewModel.secretRevealed = false
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// true 를 반환하면 이벤트를 소비한다.
    /// 수정자 매칭은 contains 로 느슨하게 — capsLock/한글 입력 등 부가 플래그가 붙어도 동작해야 한다.
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        let opt = mods.contains(.option)

        // 라벨 입력 중: esc 만 가로채고 나머지는 TextField 로 (⏎ 은 onSubmit)
        if viewModel.renameVisible {
            if event.keyCode == 53 {
                viewModel.closeRename()
                return true
            }
            return false
        }

        // 보드 픽커(⌘P)가 열려 있으면 픽커가 키를 독점
        if viewModel.pickerVisible {
            // 새 보드 이름 입력 중 ⌘S: 시크릿 토글 (마우스 없이)
            if viewModel.creatingBoard, cmd, event.keyCode == 1 {
                viewModel.newBoardSecret.toggle()
                return true
            }
            return handlePicker(event)
        }

        // 보드 삭제 확인 (⌘⇧⌫)
        if viewModel.confirmingBoardDelete {
            switch event.keyCode {
            case 36, 76:
                viewModel.confirmDeleteCurrentBoard()
                return true
            case 53:
                viewModel.cancelBoardDelete()
                return true
            default:
                return true
            }
        }

        // 스택 커밋 픽커(⌘⏎) — 구분자/순차 선택
        if viewModel.stackPickerVisible {
            switch event.keyCode {
            case 53:
                viewModel.closeStackPicker()
                return true
            case 125:
                viewModel.stackPickerMove(by: 1)
                return true
            case 126:
                viewModel.stackPickerMove(by: -1)
                return true
            case 36, 76:
                viewModel.stackPickerCommit(action: shift ? .copyOnly : .paste)
                return true
            case 40 where cmd && shift: // 픽커 안에서도 ⌘⇧K 비우기 허용
                viewModel.clearStack()
                viewModel.closeStackPicker()
                return true
            default:
                return true
            }
        }

        // 단축키 도움말 (⌘/) — 아무 키나 닫는다 (읽고 바로 이어서 작업)
        if viewModel.helpVisible {
            viewModel.helpVisible = false
            // esc/⌘/ 는 소비, 그 외는 통과시켜 곧바로 원래 동작 수행
            return event.keyCode == 53 || (cmd && event.keyCode == 44)
        }

        // 변환 픽커(⌘T)
        if viewModel.transformVisible {
            switch event.keyCode {
            case 53:
                viewModel.closeTransform()
                return true
            case 125:
                viewModel.transformMove(by: 1)
                return true
            case 126:
                viewModel.transformMove(by: -1)
                return true
            case 36, 76:
                viewModel.transformCommit(action: shift ? .copyOnly : .paste)
                return true
            default:
                return true
            }
        }

        switch event.keyCode {
        case 53: // esc
            hide()
            return true
        case 44 where cmd: // ⌘/: 단축키 도움말
            viewModel.helpVisible = true
            return true
        case 125, 126: // down / up
            // 주의: 여기서 NSApp.nextEvent 로 큐를 코얼레싱하면 안 된다 — nextEvent 는
            // 런루프를 펌핑해 핸들러 안에서 SwiftUI 플러시를 반복 실행시킨다 (1초급 블로킹, 프로파일 확인).
            // 키당 비용이 반복 간격보다 낮아진 지금은 코얼레싱 자체가 불필요하다.
            // 자동반복 중에는 프리뷰 갱신 보류 (keyUp 에서 재개) — 이동 중 대형 조판 개입 차단
            viewModel.keyRepeatActive = event.isARepeat
            viewModel.moveSelection(by: event.keyCode == 125 ? 1 : -1)
            return true
        case 36 where cmd, 76 where cmd: // ⌘⏎: 스택 커밋 픽커 (구분자/순차 선택 후 ⏎)
            viewModel.openStackPicker()
            return true
        case 36, 76: // return, keypad enter — ⇧⏎ 는 복사만, ⏎ 는 다이렉트 페이스트
            let action: PaletteViewModel.CommitAction = shift ? .copyOnly : .paste
            viewModel.commitSelection(action: action)
            return true
        case 35 where cmd: // ⌘P: 보드에 넣기
            viewModel.openPicker()
            return true
        case 15 where cmd: // ⌘R: 라벨 지정
            viewModel.openRename()
            return true
        case 17 where cmd: // ⌘T: 변환 붙여넣기
            viewModel.openTransform()
            return true
        case 40 where cmd && shift: // ⌘⇧K: 페이스트 스택 비우기 (명시적 비움)
            viewModel.clearStack()
            return true
        case 40 where cmd: // ⌘K: 페이스트 스택에 담기/빼기
            viewModel.toggleStack()
            return true
        case 14 where cmd && shift: // ⌘⇧E: 은신 모드 토글 (수집 일시정지)
            viewModel.toggleStealthMode()
            return true
        case 14 where cmd: // ⌘E: 이 항목의 출처 앱을 수집 제외
            viewModel.excludeSelectedItemApp()
            return true
        case 1 where cmd && shift: // ⌘⇧S: 현재 보드 시크릿 전환 (보드 탭에서만 — 우클릭 메뉴와 동일 동작)
            guard let board = viewModel.selectedBoard else { return false }
            viewModel.toggleBoardSecret(board)
            return true
        case 51 where cmd && shift: // ⌘⇧⌫: 현재 보드 삭제 (확인 후)
            viewModel.requestDeleteCurrentBoard()
            return true
        case 51 where cmd: // ⌘⌫: 항목 삭제 (전체 탭에선 보드 항목은 숨김만)
            viewModel.deleteSelection()
            return true
        // ⌘⇧←/→: 현재 보드 탭 이동 (1차 단축키, 힌트 바 노출)
        // 키코드 123/124 는 이 switch 최초 사용 (기존 화살표는 125/126 상하뿐),
        // 보드 '전환' ⌘[/⌘] 는 키코드 33/30 브래킷 키라 무관 — 충돌 없음.
        // 전체 탭(selectedBoard == nil)에서는 return false 로 이벤트를 통과시켜
        // 검색 TextField 의 macOS 표준 편집 단축키(⌘⇧←/→ = 줄 시작/끝까지 선택)를 보존한다.
        case 123 where cmd && shift: // ⌘⇧←: 현재 보드 탭을 왼쪽으로
            guard viewModel.selectedBoard != nil else { return false }
            viewModel.moveSelectedBoard(by: -1)
            return true
        case 124 where cmd && shift: // ⌘⇧→: 오른쪽으로
            guard viewModel.selectedBoard != nil else { return false }
            viewModel.moveSelectedBoard(by: 1)
            return true
        // ⌘⌥[/] 는 반드시 아래의 ⌘[/] case 보다 앞에 — switch 는 첫 매칭만 실행하므로
        // 뒤에 두면 'where cmd' 가 option 포함 이벤트도 삼켜 보드 순환으로 오동작한다
        case 33 where cmd && opt: // ⌘⌥[: 현재 보드를 왼쪽으로 이동 (⌘⇧← 의 브래킷 별칭)
            viewModel.moveSelectedBoard(by: -1)
            return true
        case 30 where cmd && opt: // ⌘⌥]: 현재 보드를 오른쪽으로 이동 (⌘⇧→ 의 브래킷 별칭)
            viewModel.moveSelectedBoard(by: 1)
            return true
        case 33 where cmd: // ⌘[ (⇧ 있어도 됨): 이전 보드
            viewModel.cycleBoard(by: -1)
            return true
        case 30 where cmd: // ⌘] : 다음 보드
            viewModel.cycleBoard(by: 1)
            return true
        default:
            // ⌘1~9 퀵 선택
            if cmd, !shift,
               let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), (1...9).contains(digit) {
                viewModel.select(index: digit - 1)
                return true
            }
            return false
        }
    }

    private func handlePicker(_ event: NSEvent) -> Bool {
        // 새 보드 이름 입력 중에는 esc 만 가로채고 나머지는 TextField 에 넘긴다 (⏎ 은 onSubmit 처리)
        if viewModel.creatingBoard {
            if event.keyCode == 53 {
                viewModel.creatingBoard = false
                return true
            }
            return false
        }
        switch event.keyCode {
        case 53: // esc
            viewModel.closePicker()
            return true
        case 125:
            viewModel.pickerMove(by: 1)
            return true
        case 126:
            viewModel.pickerMove(by: -1)
            return true
        case 36, 76:
            viewModel.pickerCommit()
            return true
        default:
            return true // 픽커가 열린 동안 검색창 입력 방지
        }
    }
}
