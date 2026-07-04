import Foundation
import GRDB

/// 핀보드: 자주 쓰는 항목을 모아두는 컬렉션. isSecret 이면 목록/프리뷰에서 내용이 마스킹된다.
struct Board: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "boards"

    static let presetColors = ["#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5"]

    var id: Int64?
    var uuid: String
    var name: String
    var colorHex: String
    var isSecret: Bool
    var displayOrder: Int
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
