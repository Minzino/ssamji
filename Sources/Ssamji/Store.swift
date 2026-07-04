import Foundation
import GRDB

/// SQLite(GRDB) 저장소. FTS5 전문검색 인덱스는 items 테이블과 자동 동기화된다.
final class Store {
    let dbQueue: DatabaseQueue
    let blobsDirectory: URL

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Ssamji", isDirectory: true)

        blobsDirectory = appSupport.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)

        dbQueue = try DatabaseQueue(path: appSupport.appendingPathComponent("ssamji.db").path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("kind", .text).notNull()
                t.column("checksum", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("text", .text)
                t.column("url", .text)
                t.column("colorHex", .text)
                t.column("imagePath", .text)
                t.column("fileURLs", .text)
                t.column("sourceAppBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("byteSize", .integer).notNull()
            }
            try db.create(index: "idx_items_updatedAt", on: "items", columns: ["updatedAt"])

            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "items")
                t.column("title")
                t.column("text")
            }
        }

        try migrator.migrate(dbQueue)
    }

    /// 저장. 같은 checksum 이 이미 있으면 새로 만들지 않고 updatedAt 만 끌어올린다(최근 항목으로 부상).
    @discardableResult
    func save(_ item: ClipItem) throws -> ClipItem {
        try dbQueue.write { db in
            if var existing = try ClipItem
                .filter(Column("checksum") == item.checksum)
                .fetchOne(db) {
                existing.updatedAt = Date()
                existing.deletedAt = nil
                try existing.update(db)
                return existing
            }
            var new = item
            try new.insert(db)
            return new
        }
    }

    func recent(limit: Int = 20) throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem
                .filter(Column("deletedAt") == nil)
                .order(Column("updatedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try ClipItem.filter(Column("deletedAt") == nil).fetchCount(db)
        }
    }

    /// FTS5 전문검색 (M2 팔레트에서 사용, M1에서는 검증용)
    func search(_ query: String, limit: Int = 50) throws -> [ClipItem] {
        try dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            let sql = """
                SELECT items.* FROM items
                JOIN items_fts ON items_fts.rowid = items.id
                WHERE items_fts MATCH ? AND items.deletedAt IS NULL
                ORDER BY items.updatedAt DESC LIMIT ?
                """
            return try ClipItem.fetchAll(db, sql: sql, arguments: [pattern, limit])
        }
    }
}
