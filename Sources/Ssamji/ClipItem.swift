import Foundation
import GRDB

/// 클립보드에서 수집된 항목 하나.
/// uuid/updatedAt/deletedAt 은 추후 CloudKit 동기화를 위한 선반영 필드.
struct ClipItem: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "items"

    enum Kind: String, Codable {
        case text, link, image, file, color

        var symbolName: String {
            switch self {
            case .text: return "doc.text"
            case .link: return "link"
            case .image: return "photo"
            case .file: return "folder"
            case .color: return "paintpalette"
            }
        }
    }

    var id: Int64?
    var uuid: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var kind: Kind
    var checksum: String
    var title: String
    var text: String?
    var url: String?
    var colorHex: String?
    var imagePath: String?
    var fileURLs: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var byteSize: Int
    var boardId: Int64?
    /// 사용자가 붙인 라벨 (시크릿 항목 식별용, 일반 항목도 가능)
    var customTitle: String?
    /// 시크릿 금고: true 면 내용 컬럼(title/text/url/colorHex/fileURLs)이 비워지고
    /// vaultPayload(AES-GCM)에 봉인돼 있다. 이미지는 블롭 파일 자체가 암호화된다.
    var isEncrypted: Bool = false
    var vaultPayload: Data?

    /// 표시용 제목: 라벨이 있으면 라벨, 없으면 자동 생성 제목
    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return title
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
