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

        migrator.registerMigration("v4-trigram") { db in
            // 부분 문자열 검색: unicode61 은 '토큰 접두어'만 매칭해 단어 중간·URL 조각·
            // 한글 어절 중간이 안 잡힌다 → trigram 토크나이저로 재생성 (substring 매칭).
            // synchronize 가 만든 트리거를 반드시 먼저 지워야 재생성 시 이름 충돌이 없다 (v3 전례)
            try db.dropFTS5SynchronizationTriggers(forTable: "items_fts")
            try db.drop(table: "items_fts")
            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "items") // 기존 행 자동 백필 (무손실)
                t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
                t.column("title")
                t.column("text")
                t.column("customTitle")
            }
        }

        migrator.registerMigration("v5-vault") { db in
            try db.alter(table: "items") { t in
                t.add(column: "isEncrypted", .boolean).notNull().defaults(to: false)
                t.add(column: "vaultPayload", .blob)
            }
        }

        try migrator.migrate(dbQueue)
        // 업데이트 전부터 시크릿 보드에 있던 평문 항목들을 봉인 (1회성·멱등)
        try encryptLegacySecretItems()
    }

    // MARK: - 시크릿 금고 (Vault)
    // 시크릿 보드 항목은 내용 컬럼을 비우고 AES-GCM 페이로드로 봉인한다.
    // checksum 은 dedup 을 위해 평문 유지(해시라 내용 복원 불가). customTitle(라벨)은
    // 마스킹 상태의 표시·검색 수단이므로 설계상 평문이다. FTS 는 synchronize 트리거가
    // UPDATE 를 따라가므로 봉인 순간 인덱스에서도 내용이 사라진다.

    private struct VaultPayload: Codable {
        var title: String
        var text: String?
        var url: String?
        var colorHex: String?
        var fileURLs: String?
    }

    /// 항목 봉인 — 내용 컬럼 → vaultPayload. 이미지는 블롭 파일 자체를 암호화.
    private static func sealFields(_ item: inout ClipItem) throws {
        guard !item.isEncrypted else { return }
        let payload = VaultPayload(
            title: item.title, text: item.text, url: item.url,
            colorHex: item.colorHex, fileURLs: item.fileURLs)
        item.vaultPayload = try Vault.shared.encrypt(JSONEncoder().encode(payload))
        item.title = ""
        item.text = nil
        item.url = nil
        item.colorHex = nil
        item.fileURLs = nil
        item.isEncrypted = true
        if let path = item.imagePath {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            try Vault.shared.encrypt(data).write(to: url, options: .atomic)
        }
    }

    /// 항목 개봉 — vaultPayload → 내용 컬럼 복원. 이미지 블롭 파일 복호화.
    private static func openFields(_ item: inout ClipItem) throws {
        guard item.isEncrypted, let sealed = item.vaultPayload else { return }
        let payload = try JSONDecoder().decode(VaultPayload.self, from: Vault.shared.decrypt(sealed))
        item.title = payload.title
        item.text = payload.text
        item.url = payload.url
        item.colorHex = payload.colorHex
        item.fileURLs = payload.fileURLs
        item.vaultPayload = nil
        item.isEncrypted = false
        if let path = item.imagePath {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            try Vault.shared.decrypt(data).write(to: url, options: .atomic)
        }
    }

    /// 붙여넣기/프리뷰용 메모리 복호본 — DB 는 건드리지 않는다.
    /// 이미지는 파일을 복호화하지 않고 데이터만 돌려준다 (디스크는 봉인 유지).
    func decryptedCopy(of item: ClipItem) throws -> (item: ClipItem, imageData: Data?) {
        guard item.isEncrypted, let sealed = item.vaultPayload else { return (item, nil) }
        var copy = item
        let payload = try JSONDecoder().decode(VaultPayload.self, from: Vault.shared.decrypt(sealed))
        copy.title = payload.title
        copy.text = payload.text
        copy.url = payload.url
        copy.colorHex = payload.colorHex
        copy.fileURLs = payload.fileURLs
        var imageData: Data?
        if let path = copy.imagePath {
            imageData = try Vault.shared.decrypt(Data(contentsOf: URL(fileURLWithPath: path)))
        }
        return (copy, imageData)
    }

    /// 봉인된 항목 전체 — 자가 검증(--vault-selftest)용
    func allEncryptedItems() throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem.filter(Column("isEncrypted") == true).fetchAll(db)
        }
    }

    /// 마이그레이션: 이미 시크릿 보드에 들어있는 평문 항목 봉인 (실패 항목은 건너뛰고 계속)
    private func encryptLegacySecretItems() throws {
        try dbQueue.write { db in
            let secretIDs = try Int64.fetchAll(
                db, sql: "SELECT id FROM boards WHERE isSecret = 1")
            guard !secretIDs.isEmpty else { return }
            let doomed = try ClipItem
                .filter(secretIDs.contains(Column("boardId")))
                .filter(Column("isEncrypted") == false)
                .fetchAll(db)
            for var item in doomed {
                do {
                    try Self.sealFields(&item)
                    try item.update(db)
                } catch {
                    // 하나가 실패해도 나머지는 봉인한다 — 실패 항목은 다음 실행에서 재시도
                    NSLog("[Vault] 레거시 봉인 실패 id=%@: %@",
                          String(describing: item.id), error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 검색 쿼리 빌더

    /// trigram 은 3 유니코드 스칼라 미만의 쿼리에서 토큰이 0개라 무조건 0건 —
    /// 그런 term 이 하나라도 있으면 items 원본 테이블 LIKE 로 폴백한다
    /// (FTS 테이블 경유 LIKE 는 풀스캔으로 오히려 느림 — 실측 77ms vs 4ms).
    private struct SearchQuery {
        let joinFTS: Bool
        let whereSQL: String
        let arguments: [DatabaseValueConvertible?]
    }

    /// 공백으로 term 분리 (AND 결합)
    private static func searchTerms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// 모든 term 이 trigram 최소 길이(3 스칼라) 이상인가
    private static func isFTSEligible(_ terms: [String]) -> Bool {
        terms.allSatisfy { $0.unicodeScalars.count >= 3 }
    }

    /// trigram FTS5 패턴: 각 term 을 쌍따옴표 phrase 로 (phrase 자체가 substring 의미 —
    /// 접두어 * 불필요). 내부 쌍따옴표는 "" 로 이스케이프해 문법 오류 방지.
    private static func ftsPattern(for terms: [String]) -> String {
        terms
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: " AND ")
    }

    /// LIKE 패턴: \, %, _ 를 \ 이스케이프 (ESCAPE '\' 와 짝)
    private static func likePattern(for term: String) -> String {
        var escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "%", with: "\\%")
        escaped = escaped.replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped + "%"
    }

    private static func buildSearchQuery(_ query: String, boardID: Int64?) -> SearchQuery {
        let terms = searchTerms(query)
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible?] = []
        var joinFTS = false
        if !terms.isEmpty {
            if isFTSEligible(terms) {
                joinFTS = true
                clauses.append("items_fts MATCH ?")
                arguments.append(ftsPattern(for: terms))
            } else {
                for term in terms {
                    let pattern = likePattern(for: term)
                    clauses.append("""
                        (items.title LIKE ? ESCAPE '\\' \
                        OR items.text LIKE ? ESCAPE '\\' \
                        OR items.customTitle LIKE ? ESCAPE '\\')
                        """)
                    arguments.append(contentsOf: [pattern, pattern, pattern])
                }
            }
        }
        // 보드는 독립 공간 — 보드 탭에서는 히스토리 숨김(deletedAt)과 무관하게 소속 항목을 보여준다
        if let boardID {
            clauses.append("items.boardId = ?")
            arguments.append(boardID)
        } else {
            clauses.append("items.deletedAt IS NULL")
        }
        return SearchQuery(
            joinFTS: joinFTS,
            whereSQL: clauses.joined(separator: " AND "),
            arguments: arguments
        )
    }

    private static func fetchItems(_ db: Database, _ q: SearchQuery, limit: Int) throws -> [ClipItem] {
        let from = q.joinFTS
            ? "FROM items JOIN items_fts ON items_fts.rowid = items.id"
            : "FROM items"
        var arguments = q.arguments
        arguments.append(limit)
        return try ClipItem.fetchAll(
            db,
            sql: "SELECT items.* \(from) WHERE \(q.whereSQL) ORDER BY items.updatedAt DESC LIMIT ?",
            arguments: StatementArguments(arguments)
        )
    }

    private static func countMatches(_ db: Database, _ q: SearchQuery) throws -> Int {
        let from = q.joinFTS
            ? "FROM items JOIN items_fts ON items_fts.rowid = items.id"
            : "FROM items"
        return try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) \(from) WHERE \(q.whereSQL)",
            arguments: StatementArguments(q.arguments)
        ) ?? 0
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

    /// 동기화 임포트: 같은 checksum 이 없을 때만 삽입 — save() 와 달리 기존 항목의 updatedAt 을
    /// 끌어올리지 않는다 (다른 Mac 에서 온 항목이 로컬 히스토리 순서를 흔들지 않게).
    @discardableResult
    func importIfAbsent(_ item: ClipItem) throws -> Bool {
        try dbQueue.write { db in
            let exists = try ClipItem
                .filter(Column("checksum") == item.checksum)
                .fetchCount(db) > 0
            if exists { return false }
            var new = item
            try new.insert(db)
            return true
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

    /// 목록 조회: 쿼리가 비면 최근순, 전 term ≥3자면 trigram FTS5 substring 검색,
    /// 그 외(짧은 한글 등)는 items 테이블 LIKE 폴백 — searchPage 와 동일한 빌더로 결과 일관성 보장.
    func items(matching query: String, boardID: Int64?, limit: Int = 50) throws -> [ClipItem] {
        try dbQueue.read { db in
            try Self.fetchItems(db, Self.buildSearchQuery(query, boardID: boardID), limit: limit)
        }
    }

    /// 팔레트 검색 페이지: 단일 read 블록에서 fetch + count 를 함께 실행 —
    /// 락 1회 + 동일 스냅샷이라 "50 / 197개" 카운터와 결과가 어긋나지 않는다.
    func searchPage(matching query: String, boardID: Int64?, limit: Int = 50) throws -> (items: [ClipItem], total: Int) {
        try dbQueue.read { db in
            let q = Self.buildSearchQuery(query, boardID: boardID)
            return (try Self.fetchItems(db, q, limit: limit), try Self.countMatches(db, q))
        }
    }

    /// 타이핑 핫패스용 비동기판 — 메인스레드를 막지 않는다 (디바운스된 검색 전용)
    func searchPage(matching query: String, boardID: Int64?, limit: Int = 50) async throws -> (items: [ClipItem], total: Int) {
        try await dbQueue.read { db in
            let q = Self.buildSearchQuery(query, boardID: boardID)
            return (try Self.fetchItems(db, q, limit: limit), try Self.countMatches(db, q))
        }
    }

    // MARK: - 동기화 지원 (백필·보드 매핑)

    /// 동기화 대상 후보 — 봉인(시크릿)되지 않은 항목 전부. export() 가 종류/보드로 다시 거른다.
    /// (백필용 — 동기화 처음 켤 때 기존 항목을 폴더로 내보내기 위함)
    func exportableItems() throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem.filter(Column("isEncrypted") == false).fetchAll(db)
        }
    }

    /// boardId → Board (동기화 레코드에 보드 UUID·시크릿 여부를 싣기 위함)
    func board(id: Int64) throws -> Board? {
        try dbQueue.read { db in try Board.fetchOne(db, key: id) }
    }

    /// 동기화 대상 보드(비시크릿만) — 시크릿 보드 구조는 동기화하지 않는다
    func nonSecretBoards() throws -> [Board] {
        try dbQueue.read { db in
            try Board.filter(Column("isSecret") == false)
                .order(Column("displayOrder"), Column("id")).fetchAll(db)
        }
    }

    /// UUID 로 로컬 보드 id 조회 (임포트 시 보드 소속 매핑)
    func localBoardId(uuid: String) throws -> Int64? {
        try dbQueue.read { db in
            try Board.filter(Column("uuid") == uuid).fetchOne(db)?.id
        }
    }

    /// 동기화 임포트: UUID 기준으로 보드 upsert (없으면 생성, 있으면 이름·색·순서 갱신).
    /// 시크릿 상태는 로컬 우선(시크릿 보드는 동기화 안 되므로 여기 오는 건 비시크릿).
    @discardableResult
    func upsertBoard(uuid: String, name: String, colorHex: String, displayOrder: Int) throws -> Int64 {
        try dbQueue.write { db in
            if var existing = try Board.filter(Column("uuid") == uuid).fetchOne(db) {
                existing.name = name
                existing.colorHex = colorHex
                existing.displayOrder = displayOrder
                try existing.update(db)
                return existing.id!
            }
            var board = Board(
                id: nil, uuid: uuid, name: name, colorHex: colorHex,
                isSecret: false, displayOrder: displayOrder, createdAt: Date())
            try board.insert(db)
            return board.id!
        }
    }

    /// 히스토리에서만 숨김 (보드 공간에는 유지). 같은 내용을 다시 복사하면 히스토리로 복귀한다.
    func hideFromHistory(_ item: ClipItem) throws {
        try dbQueue.write { db in
            var updated = item
            updated.deletedAt = Date()
            try updated.update(db)
        }
    }

    /// 현재 쿼리/탭 조건의 전체 매칭 수 — 팔레트 카운터("50 / 197개")와 페이지네이션 판단용.
    /// 팔레트 핫패스는 searchPage (fetch+count 단일 read) 를 쓴다 — 이 API 는 단발 조회용.
    func countItems(matching query: String, boardID: Int64?) throws -> Int {
        try dbQueue.read { db in
            try Self.countMatches(db, Self.buildSearchQuery(query, boardID: boardID))
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

    /// 보드 순서 변경 — 현재 순서(displayOrder, id)에서 delta 만큼 이동.
    /// 전체를 배열 인덱스로 재기록하므로 삭제로 생긴 구멍/중복도 함께 자가 치유된다.
    func moveBoard(_ board: Board, by delta: Int) throws {
        try dbQueue.write { db in
            var boards = try Board.order(Column("displayOrder"), Column("id")).fetchAll(db)
            guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
            let target = index + delta
            guard boards.indices.contains(target), target != index else { return }
            boards.swapAt(index, target)
            for (order, b) in boards.enumerated() where b.displayOrder != order {
                var updated = b
                updated.displayOrder = order
                try updated.update(db)
            }
        }
    }

    /// 보드 삭제 — 소속 항목들은 FK onDelete(.setNull) 로 히스토리에 남는다.
    /// 시크릿 보드였다면 항목을 먼저 개봉한다 (히스토리에 암호문 고아가 남지 않게).
    func deleteBoard(_ board: Board) throws {
        _ = try dbQueue.write { db in
            if board.isSecret, let boardID = board.id {
                let items = try ClipItem.filter(Column("boardId") == boardID).fetchAll(db)
                for var item in items {
                    try Self.openFields(&item)
                    try item.update(db)
                }
            }
            return try board.delete(db)
        }
    }

    func setBoard(_ boardID: Int64?, for item: ClipItem) throws {
        try dbQueue.write { db in
            var updated = item
            updated.boardId = boardID
            // 시크릿 경계를 넘는 순간 봉인/개봉 — 시크릿 보드 안 내용은 항상 암호문
            let targetSecret = try boardID
                .flatMap { try Board.fetchOne(db, key: $0)?.isSecret } ?? false
            if targetSecret {
                try Self.sealFields(&updated)
            } else {
                try Self.openFields(&updated)
            }
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
            // 보드의 시크릿 상태와 소속 항목의 봉인 상태를 함께 맞춘다
            guard let boardID = board.id else { return }
            let items = try ClipItem.filter(Column("boardId") == boardID).fetchAll(db)
            for var item in items {
                if isSecret { try Self.sealFields(&item) } else { try Self.openFields(&item) }
                try item.update(db)
            }
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
