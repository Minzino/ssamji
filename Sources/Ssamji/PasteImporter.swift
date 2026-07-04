import AppKit
import GRDB

/// Paste 2 의 로컬 데이터(Paste.db)를 쌈지로 이주한다.
///
/// 형식 (리버스 엔지니어링):
/// - ZSNIPPETDATA.ZPASTEBOARDITEMS: 1바이트 프리픽스 + 페이로드
///   - 0x01: NSKeyedArchiver 바이너리 plist 인라인
///   - 0x02: UUID 문자열 — .Paste_SUPPORT/_EXTERNAL_DATA/<UUID> 파일에 아카이브 저장
/// - 아카이브 루트: [PasteCore.PasteboardItem], 각각 types([String]) + data({타입: Data})
/// - ZSNIPPETLIST = 핀보드, Z_6LISTS = 항목↔보드 매핑, ZAPPLICATION = 출처 앱
enum PasteImporter {

    struct Result {
        var imported = 0
        var merged = 0      // 이미 있던 항목에 보드/라벨만 병합
        var failed = 0
        var boardsCreated = 0

        var summary: String {
            "가져옴 \(imported) · 병합 \(merged) · 실패 \(failed) · 보드 \(boardsCreated)개 생성"
        }
    }

    private static let container = NSString(
        string: "~/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste"
    ).expandingTildeInPath

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: container + "/Paste.db")
    }

    /// Core Data 의 NSDate 기준(2001-01-01)을 Date 로
    private static func date(_ coreDataTimestamp: Double?) -> Date {
        guard let t = coreDataTimestamp else { return Date() }
        return Date(timeIntervalSinceReferenceDate: t)
    }

    static func run(into store: Store) throws -> Result {
        // 원본을 잠그지 않도록 임시 사본에서 읽는다 (Paste 가 실행 중일 수 있음)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ssamji-paste-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for suffix in ["", "-wal", "-shm"] {
            let src = container + "/Paste.db" + suffix
            if FileManager.default.fileExists(atPath: src) {
                try FileManager.default.copyItem(atPath: src, toPath: tmp.appendingPathComponent("Paste.db" + suffix).path)
            }
        }

        let source = try DatabaseQueue(path: tmp.appendingPathComponent("Paste.db").path)
        var result = Result()

        // 1) 보드: 이름이 같은 기존 보드는 재사용
        var boardIDByListPK: [Int64: Int64] = [:]
        let existingBoards = try store.boards()
        let lists = try source.read { db in
            try Row.fetchAll(db, sql: "SELECT Z_PK, ZNAME FROM ZSNIPPETLIST ORDER BY ZDISPLAYORDER, Z_PK")
        }
        var boardsByName: [String: Int64] = [:]
        for b in existingBoards {
            if let id = b.id { boardsByName[b.name] = id }
        }
        for list in lists {
            let pk: Int64 = list["Z_PK"]
            let name: String = list["ZNAME"] ?? "가져온 보드"
            if let existing = boardsByName[name] {
                boardIDByListPK[pk] = existing
            } else {
                let board = try store.createBoard(name: name, isSecret: false)
                if let id = board.id {
                    boardsByName[name] = id
                    boardIDByListPK[pk] = id
                    result.boardsCreated += 1
                }
            }
        }

        // 2) 항목 ↔ 보드 매핑 (여러 보드에 속하면 첫 번째만)
        var listPKBySnippetPK: [Int64: Int64] = [:]
        let mappings = try source.read { db in
            try Row.fetchAll(db, sql: "SELECT Z_6SNIPPETS, Z_13LISTS FROM Z_6LISTS")
        }
        for m in mappings {
            let snippet: Int64 = m["Z_6SNIPPETS"]
            if listPKBySnippetPK[snippet] == nil {
                listPKBySnippetPK[snippet] = m["Z_13LISTS"]
            }
        }

        // 3) 출처 앱
        var appByPK: [Int64: (name: String?, bundleID: String?)] = [:]
        let apps = try source.read { db in
            try Row.fetchAll(db, sql: "SELECT Z_PK, ZNAME, ZBUNDLEIDENTIFIER FROM ZAPPLICATION")
        }
        for a in apps {
            appByPK[a["Z_PK"]] = (a["ZNAME"], a["ZBUNDLEIDENTIFIER"])
        }

        // 4) 스니펫 본문
        let snippets = try source.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.Z_PK AS pk, s.ZTITLE AS title, s.ZCREATEDAT AS createdAt,
                       s.ZTIMESTAMP AS timestamp, s.ZSOURCEAPPLICATION AS appPK,
                       d.ZPASTEBOARDITEMS AS blob
                FROM ZSNIPPET s
                LEFT JOIN ZSNIPPETDATA d ON d.ZSNIPPET = s.Z_PK
                ORDER BY s.ZCREATEDAT
                """)
        }

        for row in snippets {
            let pk: Int64 = row["pk"]
            guard let blob: Data = row["blob"],
                  let dataByType = extractPayload(blob) else {
                result.failed += 1
                continue
            }

            guard var item = makeItem(from: dataByType, blobsDirectory: store.blobsDirectory) else {
                result.failed += 1
                continue
            }

            item.createdAt = date(row["createdAt"])
            item.updatedAt = date(row["timestamp"] ?? row["createdAt"])
            if let appPK: Int64 = row["appPK"], let app = appByPK[appPK] {
                item.sourceAppName = app.name
                item.sourceAppBundleID = app.bundleID
            }
            if let listPK = listPKBySnippetPK[pk] {
                item.boardId = boardIDByListPK[listPK]
            }
            // Paste 에서 사용자가 직접 붙인 카드 제목은 라벨로 보존 (자동 제목과 다를 때만)
            if let zTitle: String = row["title"],
               !zTitle.isEmpty, zTitle != item.title {
                item.customTitle = zTitle
            }

            do {
                let saved = try store.save(item)
                if saved.uuid == item.uuid {
                    result.imported += 1
                } else {
                    // 이미 수집돼 있던 항목 — 보드/라벨만 채워넣는다
                    var needsUpdate = false
                    var merged = saved
                    if merged.boardId == nil, let boardId = item.boardId {
                        merged.boardId = boardId
                        needsUpdate = true
                    }
                    if merged.customTitle == nil, let label = item.customTitle {
                        merged.customTitle = label
                        needsUpdate = true
                    }
                    if needsUpdate {
                        try store.setBoard(merged.boardId, for: merged)
                        try store.setCustomTitle(merged.customTitle, for: merged)
                    }
                    result.merged += 1
                }
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    // MARK: - 블롭 해석

    /// 프리픽스에 따라 인라인/외부 아카이브를 읽어 {타입: 데이터} 로 평탄화
    private static func extractPayload(_ blob: Data) -> [String: Data]? {
        guard let first = blob.first else { return nil }
        let archive: Data
        switch first {
        case 0x01:
            archive = Data(blob.dropFirst())
        case 0x02:
            guard let uuid = String(data: blob.dropFirst(), encoding: .utf8) else { return nil }
            let path = container + "/.Paste_SUPPORT/_EXTERNAL_DATA/" + uuid
            guard let external = FileManager.default.contents(atPath: path) else { return nil }
            archive = external
        default:
            return nil
        }

        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(LegacyPasteboardItem.self, forClassName: "PasteCore.PasteboardItem")
        defer { unarchiver.finishDecoding() }
        guard let items = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [LegacyPasteboardItem] else {
            return nil
        }

        var merged: [String: Data] = [:]
        for item in items {
            merged.merge(item.dataByType) { current, _ in current }
        }
        return merged.isEmpty ? nil : merged
    }

    /// 타입 우선순위(파일 > 이미지 > 텍스트)에 따라 ClipItem 생성
    private static func makeItem(from dataByType: [String: Data], blobsDirectory: URL) -> ClipItem? {
        var item = ClipItem(
            id: nil, uuid: UUID().uuidString,
            createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            kind: .text, checksum: "", title: "",
            text: nil, url: nil, colorHex: nil, imagePath: nil, fileURLs: nil,
            sourceAppBundleID: nil, sourceAppName: nil,
            byteSize: 0, boardId: nil, customTitle: nil
        )

        // 파일
        if let fileURLData = dataByType["public.file-url"],
           let urlString = String(data: fileURLData, encoding: .utf8),
           let url = URL(string: urlString) {
            let path = url.path
            item.kind = .file
            item.fileURLs = String(data: (try? JSONEncoder().encode([path])) ?? Data(), encoding: .utf8)
            item.title = url.lastPathComponent
            item.text = path
            item.checksum = PasteboardReader.sha256(Data(path.utf8))
            item.byteSize = path.utf8.count
            return item
        }

        // 이미지
        if let imageData = dataByType["public.png"] ?? dataByType["public.tiff"] {
            let checksum = PasteboardReader.sha256(imageData)
            let path = blobsDirectory.appendingPathComponent("\(checksum).png")
            if !FileManager.default.fileExists(atPath: path.path) {
                if dataByType["public.png"] != nil {
                    try? imageData.write(to: path)
                } else if let rep = NSBitmapImageRep(data: imageData),
                          let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: path)
                } else {
                    try? imageData.write(to: path)
                }
            }
            let size = NSImage(data: imageData)?.size ?? .zero
            item.kind = .image
            item.checksum = checksum
            item.imagePath = path.path
            item.title = "이미지 \(Int(size.width))×\(Int(size.height))"
            item.byteSize = imageData.count
            return item
        }

        // 텍스트 (utf8 우선, utf16 폴백, rtf 는 평문 추출)
        var string: String?
        if let utf8 = dataByType["public.utf8-plain-text"] {
            string = String(data: utf8, encoding: .utf8)
        } else if let utf16 = dataByType["public.utf16-external-plain-text"] {
            string = String(data: utf16, encoding: .utf16)
        } else if let rtf = dataByType["public.rtf"],
                  let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            string = attributed.string
        }

        guard let string, !string.isEmpty else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        item.text = string
        item.checksum = PasteboardReader.sha256(Data(string.utf8))
        item.byteSize = string.utf8.count
        item.title = String(String(trimmed.split(separator: "\n").first ?? "").prefix(80))
        if item.title.isEmpty { item.title = "(공백)" }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           trimmed.split(separator: "\n").count == 1 {
            item.kind = .link
            item.url = trimmed
        } else if PasteboardReader.isColorHex(trimmed) {
            item.kind = .color
            item.colorHex = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        }
        return item
    }
}

/// Paste 의 PasteCore.PasteboardItem 아카이브를 받아내는 최소 디코더
final class LegacyPasteboardItem: NSObject, NSCoding {
    let types: [String]
    let dataByType: [String: Data]

    required init?(coder: NSCoder) {
        types = coder.decodeObject(forKey: "types") as? [String] ?? []
        dataByType = coder.decodeObject(forKey: "data") as? [String: Data] ?? [:]
    }

    func encode(with coder: NSCoder) {}
}
