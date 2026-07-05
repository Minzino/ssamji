import SwiftUI

@main
struct SsamjiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(state)
        } label: {
            // 은신 모드면 '여며진' 복주머니 — 메뉴바만 봐도 수집 상태를 안다
            Image(nsImage: state.stealthMode ? MenuBarIcon.stealthImage : MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 전용 앱: 독 아이콘/앱 스위처에 나타나지 않음
        NSApp.setActivationPolicy(.accessory)
    }
}
