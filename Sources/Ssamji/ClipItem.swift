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

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
