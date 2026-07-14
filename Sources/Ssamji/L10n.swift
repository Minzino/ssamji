import Foundation

/// 지역화 헬퍼 — 한국어 원문이 곧 키다 (Java 의 ResourceBundle 격).
/// ko 는 키 자체가 답이라 identity 테이블, en 은 Resources/en.lproj/Localizable.strings.
/// SwiftUI 에서는 Text(L("원문")) 형태로 쓴다 — LocalizedStringKey 의 암묵 조회는
/// main bundle 을 보므로 SPM 모듈에서는 동작하지 않는다.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

/// 포맷 문자열용 — L("%d개 보관", count)
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .module, comment: ""), arguments: args)
}
