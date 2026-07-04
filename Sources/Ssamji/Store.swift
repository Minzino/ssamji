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

        migrator.registerMigration("v2-boards") { db in
            try db.create(table: "boards") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("isSecret", .boolean).notNull().defaults(to: false)
                t.column("displayOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "items") { t in
                t.add(column: "boardId", .integer).references("boards", onDelete: .setNull)
            }
            try db.create(index: "idx_items_boardId", on: "items", columns: ["boardId"])
        }

        migrator.registerMigration("v3-customTitle") { db in
            try db.alter(table: "items") { t in
                t.add(column: "customTitle", .text)
            }
            // FTS 인덱스에 라벨 포함 (라벨로 검색 가능하게 재생성)
            // synchronize 가 만든 트리거를 먼저 지워야 재생성 시 이름 충돌이 없다
            try db.dropFTS5SynchronizationTriggers(forTable: "items_fts")
            try db.drop(table: "items_fts")
            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "items")
                t.column("title")
                t.column("text")
                t.column("customTitle")
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
        try items(matching: "", boardID: nil, limit: limit)
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try ClipItem.filter(Column("deletedAt") == nil).fetchCount(db)
        }
    }

    /// 목록 조회: 쿼리가 비면 최근순, 있으면 FTS5 전문검색. boardID 로 핀보드 필터링.
    func items(matching query: String, boardID: Int64?, limit: Int = 50) throws -> [ClipItem] {
        try dbQueue.read { db in
            if query.isEmpty {
                var request = ClipItem
                    .filter(Column("deletedAt") == nil)
                    .order(Column("updatedAt").desc)
                    .limit(limit)
                if let boardID {
                    request = request.filter(Column("boardId") == boardID)
                }
                return try request.fetchAll(db)
            }

            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            var sql = """
                SELECT items.* FROM items
                JOIN items_fts ON items_fts.rowid = items.id
                WHERE items_fts MATCH ? AND items.deletedAt IS NULL
                """
            var arguments: [DatabaseValueConvertible?] = [pattern]
            if let boardID {
                sql += " AND items.boardId = ?"
                arguments.append(boardID)
            }
            sql += " ORDER BY items.updatedAt DESC LIMIT ?"
            arguments.append(limit)
            return try ClipItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    // MARK: - 핀보드

    func boards() throws -> [Board] {
        try dbQueue.read { db in
            try Board.order(Column("displayOrder"), Column("id")).fetchAll(db)
        }
    }

    func createBoard(name: String, isSecret: Bool) throws -> Board {
        try dbQueue.write { db in
            let count = try Board.fetchCount(db)
            var board = Board(
                id: nil, uuid: UUID().uuidString, name: name,
                colorHex: Board.presetColors[count % Board.presetColors.count],
                isSecret: isSecret, displayOrder: count, createdAt: Date()
            )
            try board.insert(db)
            return board
        }
    }

    /// 보드 삭제 — 소속 항목들은 FK onDelete(.setNull) 로 히스토리에 남는다.
    func deleteBoard(_ board: Board) throws {
        _ = try dbQueue.write { db in
            try board.delete(db)
        }
    }

    func setBoard(_ boardID: Int64?, for item: ClipItem) throws {
        try dbQueue.write { db in
            var updated = item
            updated.boardId = boardID
            try updated.update(db)
        }
    }

    /// 보관 기간이 지난 히스토리 항목 정리. 보드에 넣어둔 항목(boardId != nil)은 영구 보존.
    /// checksum 이 UNIQUE 라 이미지 블롭 파일은 항목과 1:1 — 항목 삭제 시 파일도 지운다.
    @discardableResult
    func cleanup(olderThanDays days: Int) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return try dbQueue.write { db in
            let doomed = try ClipItem
                .filter(Column("boardId") == nil)
                .filter(Column("updatedAt") < cutoff)
                .fetchAll(db)
            for item in doomed {
                if let path = item.imagePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            try ClipItem
                .filter(Column("boardId") == nil)
                .filter(Column("updatedAt") < cutoff)
                .deleteAll(db)
            return doomed.count
        }
    }

    func setBoardSecret(_ board: Board, isSecret: Bool) throws {
        try dbQueue.write { db in
            var updated = board
            updated.isSecret = isSecret
            try updated.update(db)
        }
    }

    /// 항목 삭제 (이미지 블롭 파일 동반 삭제 — checksum UNIQUE 라 1:1)
    func delete(_ item: ClipItem) throws {
        _ = try dbQueue.write { db -> Bool in
            if let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            return try item.delete(db)
        }
    }

    func setCustomTitle(_ title: String?, for item: ClipItem) throws {
        try dbQueue.write { db in
            var updated = item
            updated.customTitle = title
            try updated.update(db)
        }
    }
}
