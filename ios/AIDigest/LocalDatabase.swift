import Foundation
import SQLite3

// One connection, used on the main actor. No keys are stored in this database.
@MainActor
final class LocalDatabase {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    struct Failure: LocalizedError { var errorDescription: String? { "端末への保存に失敗しました。空き容量を確認してください。" } }

    init(url: URL? = nil) throws {
        let location = try url ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("digest.sqlite")
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(location.path, &db) == SQLITE_OK else { throw Failure() }
        _ = try rows("PRAGMA journal_mode=WAL")
        try execute("CREATE TABLE IF NOT EXISTS digests (date TEXT PRIMARY KEY, payload TEXT NOT NULL, fetched_at REAL NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS articles (id TEXT PRIMARY KEY, payload TEXT NOT NULL, read_at REAL, saved_at REAL)")
        try execute("CREATE TABLE IF NOT EXISTS completed (day TEXT PRIMARY KEY)")
        try execute("CREATE TABLE IF NOT EXISTS drafts (id TEXT PRIMARY KEY, text TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft', post_url TEXT, updated_at REAL NOT NULL)")
    }
    deinit { sqlite3_close(db) }

    private func statement(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw Failure() }
        for (i, value) in values.enumerated() {
            if let value { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) } else { sqlite3_bind_null(stmt, Int32(i + 1)) }
        }
        return stmt
    }
    private func execute(_ sql: String, _ values: [String?] = []) throws {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw Failure() }
    }
    private func rows(_ sql: String, _ values: [String?] = []) throws -> [[String?]] {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        var result: [[String?]] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw Failure() }
            result.append((0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt, i).map { String(cString: $0) } })
        }
    }
    func save(_ digest: Digest, fetchedAt: Date = Date()) throws {
        let json = String(decoding: try JSONEncoder().encode(digest), as: UTF8.self)
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("INSERT INTO digests VALUES(?,?,?) ON CONFLICT(date) DO UPDATE SET payload=excluded.payload,fetched_at=excluded.fetched_at", [digest.date, json, String(fetchedAt.timeIntervalSince1970)])
            for article in digest.readerArticles {
                if let existing = self.article(id: article.id), existing.digestDate > article.digestDate { continue }
                try execute("INSERT INTO articles(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [article.id, String(decoding: try JSONEncoder().encode(article), as: UTF8.self)])
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func digest(date: String? = nil) throws -> Digest? {
        let row = try date.map { try rows("SELECT payload FROM digests WHERE date=?", [$0]) } ?? rows("SELECT payload FROM digests ORDER BY date DESC LIMIT 1")
        guard let text = row.first?.first ?? nil else { return nil }
        return try JSONDecoder().decode(Digest.self, from: Data(text.utf8))
    }
    func cachedDates() throws -> [String] { try rows("SELECT date FROM digests ORDER BY date DESC").compactMap { $0[0] } }
    func fetchedAt(_ date: String) -> Date? { (try? rows("SELECT fetched_at FROM digests WHERE date=?", [date]).first?[0]).flatMap { $0 }.flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
    func article(id: String) -> ReaderArticle? {
        guard let text = try? rows("SELECT payload FROM articles WHERE id=?", [id]).first?[0], let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReaderArticle.self, from: data)
    }
    func states() throws -> (read: Set<String>, saved: Set<String>) {
        let values = try rows("SELECT id,read_at,saved_at FROM articles")
        return (Set(values.filter { $0[1] != nil }.compactMap { $0[0] }), Set(values.filter { $0[2] != nil }.compactMap { $0[0] }))
    }
    func savedArticles() throws -> [ReaderArticle] { try rows("SELECT payload FROM articles WHERE saved_at IS NOT NULL ORDER BY saved_at DESC").compactMap { row in row[0].flatMap { try? JSONDecoder().decode(ReaderArticle.self, from: Data($0.utf8)) } } }
    func markRead(_ id: String) throws { try execute("UPDATE articles SET read_at=COALESCE(read_at,?) WHERE id=?", [String(Date().timeIntervalSince1970), id]) }
    func setSaved(_ article: ReaderArticle, saved: Bool) throws {
        try execute("INSERT INTO articles(id,payload,saved_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET saved_at=excluded.saved_at", [article.id, String(decoding: try JSONEncoder().encode(article), as: UTF8.self), saved ? String(Date().timeIntervalSince1970) : nil])
    }
    func complete(_ day: String) throws { try execute("INSERT OR IGNORE INTO completed VALUES(?)", [day]) }
    func completedDays() throws -> Set<String> { Set(try rows("SELECT day FROM completed").compactMap { $0[0] }) }
    func prune(now: Date = Date()) throws {
        let cutoff = DateFormat.day(now.addingTimeInterval(-30 * 86400))
        try execute("DELETE FROM digests WHERE date < ?", [cutoff])
        // Keep saved content indefinitely; remove other article snapshots older than retention.
        let oldIDs = try rows("SELECT id,payload FROM articles WHERE saved_at IS NULL").compactMap { row -> String? in
            guard let json = row[1], let a = try? JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8)), a.digestDate < cutoff else { return nil }; return row[0]
        }
        for id in oldIDs { try execute("DELETE FROM articles WHERE id=?", [id]) }
    }
    func draftState(_ id: String) -> (text: String, status: String, url: String?)? {
        guard let row = try? rows("SELECT text,status,post_url FROM drafts WHERE id=?", [id]).first, let text = row[0], let status = row[1] else { return nil }
        return (text, status, row[2])
    }
    func saveDraft(_ id: String, text: String, status: String = "draft", url: String? = nil) throws {
        try execute("INSERT INTO drafts VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET text=excluded.text,status=excluded.status,post_url=excluded.post_url,updated_at=excluded.updated_at", [id, text, status, url, String(Date().timeIntervalSince1970)])
    }
}
