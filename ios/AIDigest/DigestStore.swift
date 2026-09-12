import Foundation
import UIKit

@MainActor
final class DigestStore: ObservableObject {
    @Published var digest: Digest?
    @Published var isLoading = false
    @Published var notice: String?
    @Published var availableDates: [String] = []
    @Published var cachedDates: [String] = []
    @Published var readIDs = Set<String>()
    @Published var savedIDs = Set<String>()
    @Published var savedArticles: [ReaderArticle] = []
    @Published var completedDays = Set<String>()
    @Published var offline = false
    @Published var lastUpdated: Date?
    @Published var followedTopics: [String] { didSet { UserDefaults.standard.set(followedTopics, forKey: "followedTopics") } }
    private(set) var database: LocalDatabase?
    static let baseURL = URL(string: "https://takuya-ops.github.io/ai-morning-digest/data/")!
    private var refreshing = false
    private let session: URLSession

    init(database: LocalDatabase? = nil, session: URLSession = .shared) {
        self.session = session
        followedTopics = UserDefaults.standard.stringArray(forKey: "followedTopics") ?? []
        do {
            let db = try database ?? LocalDatabase(); self.database = db
            if try db.cachedDates().isEmpty, let data = UserDefaults.standard.data(forKey: "cachedDigestJSON"), let old = try? JSONDecoder().decode(Digest.self, from: data) {
                try db.save(old); UserDefaults.standard.removeObject(forKey: "cachedDigestJSON")
            }
            try db.prune(); digest = try db.digest()
            if let digest { lastUpdated = db.fetchedAt(digest.date) }
            reloadLocalState(); availableDates = cachedDates
        } catch { notice = error.localizedDescription }
    }
    var orderedBrief: [ReaderArticle] { ordered(digest?.briefArticles ?? []) }
    func ordered(_ articles: [ReaderArticle]) -> [ReaderArticle] {
        let followed = followedTopics
        return articles.enumerated().sorted { a, b in
            func priority(_ article: ReaderArticle) -> Int { article.topics.compactMap { followed.firstIndex(of: $0) }.min() ?? Int.max }
            let x = priority(a.element), y = priority(b.element)
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }
    var streak: Int {
        var day = Date(), count = 0
        if !completedDays.contains(DateFormat.day(day)) { day = day.addingTimeInterval(-86400) }
        while completedDays.contains(DateFormat.day(day)) { count += 1; day = day.addingTimeInterval(-86400) }
        return count
    }
    func follow(_ topic: String) {
        if followedTopics.contains(topic) { followedTopics.removeAll { $0 == topic } } else { followedTopics.append(topic) }
        Task { await updateSystemContent() }
    }
    func markRead(_ article: ReaderArticle) {
        guard let database else { return }
        do { try database.markRead(article.id); reloadLocalState() } catch { notice = error.localizedDescription }
    }
    func toggleSave(_ article: ReaderArticle) {
        guard let database else { return }
        do { try database.setSaved(article, saved: !savedIDs.contains(article.id)); reloadLocalState(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        catch { notice = error.localizedDescription }
    }
    func completeBriefing(date: String) {
        guard date == DateFormat.day(), let database else { return }
        do { try database.complete(date); reloadLocalState(); UINotificationFeedbackGenerator().notificationOccurred(.success) } catch { notice = error.localizedDescription }
    }
    func reloadLocalState() {
        guard let database else { return }
        do {
            cachedDates = try database.cachedDates(); let states = try database.states()
            readIDs = states.read; savedIDs = states.saved; savedArticles = try database.savedArticles(); completedDays = try database.completedDays()
        } catch { notice = error.localizedDescription }
    }
    func cachedDigest(_ date: String) -> Digest? { try? database?.digest(date: date) }
    @discardableResult
    func refresh() async -> Bool {
        guard !refreshing else { return false }; refreshing = true; isLoading = true
        defer { refreshing = false; isLoading = false }
        do {
            let current = try await fetch("latest.json")
            guard !Task.isCancelled else { return false }
            try database?.save(current)
            digest = current; offline = false; notice = nil; lastUpdated = Date()
            let index = try? await request("index.json")
            let dates = index.flatMap { try? JSONDecoder().decode(DigestIndex.self, from: $0).dates } ?? []
            availableDates = Array(Set(dates.filter(Self.validDay) + [current.date] + cachedDates)).sorted(by: >)
            reloadLocalState(); await updateSystemContent()
            let cutoff = DateFormat.day(Date().addingTimeInterval(-7 * 86400))
            for day in availableDates.filter({ $0 >= cutoff && $0 != current.date }) {
                guard !Task.isCancelled else { return false }
                if !cachedDates.contains(day), let old = try? await fetch("\(day).json") {
                    try database?.save(old); reloadLocalState()
                    await ImageCache.shared.prefetch(old.readerArticles.compactMap(\.thumbnailURL))
                }
            }
            await ImageCache.shared.prefetch(current.readerArticles.compactMap(\.thumbnailURL))
            let preferred = UserDefaults.standard.string(forKey: "briefingVoice") ?? BriefingVoice.nanami.rawValue
            if preferred != "device" { await AudioCache.shared.prefetch(current.briefArticles.compactMap { $0.audio?[preferred].flatMap(WebURL.parse) }) }
            await AudioCache.shared.prune()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            offline = true; notice = digest == nil ? "取得できませんでした。接続を確認して再読み込みしてください。" : "オフライン表示中 · 保存済みの内容を表示しています"
            return false
        }
    }
    func archive(_ day: String) async -> Digest? {
        guard Self.validDay(day) else { return nil }
        if let cached = cachedDigest(day) { return cached }
        do { let value = try await fetch("\(day).json"); try database?.save(value); reloadLocalState(); return value }
        catch { notice = "この日のデータは端末にありません。接続して再試行してください。"; return nil }
    }
    static func validDay(_ day: String) -> Bool { day.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil }
    private func request(_ file: String) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(file)); request.timeoutInterval = 12; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
    private func fetch(_ file: String) async throws -> Digest {
        let value = try JSONDecoder().decode(Digest.self, from: await request(file))
        guard Self.validDay(value.date) else { throw URLError(.cannotParseResponse) }
        if file != "latest.json", file != "\(value.date).json" { throw URLError(.cannotParseResponse) }
        return value
    }
    func updateSystemContent() async {
        if let digest { WidgetBridge.update(digest: digest, articles: orderedBrief) }
        _ = await NotificationManager.reschedule(headline: digest?.date == DateFormat.day() ? orderedBrief.first?.title : nil, requestPermission: false)
    }
}
