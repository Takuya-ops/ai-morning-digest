import Foundation
import SwiftUI
import Security
import CryptoKit

struct AudioMetadata: Codable, Hashable {
    let durationSeconds: Double
    let byteLength: Int
    let mimeType: String
    let assetSHA256: String
    let scriptHash: String
}
struct Editorial: Codable, Hashable { let method: String; let language: String; let status: String }
struct Publication: Codable {
    struct AudioState: Codable { let state: String; let expectedCount: Int; let generatedCount: Int }
    let revision: Int; let contentRevision: String; let textState: String; let updatedAt: String
    let audioByVoice: [String: AudioState]
}
enum VoicePreferences {
    static var selected: BriefingVoice { BriefingVoice(rawValue: UserDefaults.standard.string(forKey: "briefingVoice") ?? "") ?? .gemini }
}
extension ReaderArticle {
    var editionID: String { digestDate + "|" + id }
    var searchableText: String { SearchIndex.normalize(([title, summary] + topics + sources.map(\.feedName)).joined(separator: " ")) }
}
struct MuteRules: Codable {
    var keywords: [String] = []; var categories: [String] = []; var feeds: [String] = []
    func contains(_ article: ReaderArticle) -> Bool {
        keywords.contains { !$0.isEmpty && article.searchableText.contains(SearchIndex.normalize($0)) } || categories.contains { article.topics.contains($0) } || feeds.contains { name in article.sources.contains { $0.feedName == name } }
    }
}
struct ArticleCollection: Codable, Identifiable {
    var id = UUID().uuidString; var name: String; var editions: Set<String> = []
}
struct DownloadPack: Codable, Identifiable {
    var id: String; var date: String; var voice: String; var expectedCount: Int; var articles: [ReaderArticle] = []
    var urls: Set<URL> { Set(articles.compactMap { $0.audio?[voice].flatMap(WebURL.parse) }) }
}
struct LibraryState: Codable {
    var downloadPacks: [DownloadPack]?
    var articles: [String: ReaderArticle] = [:]
    var downloadedEditions: Set<String>?
    var notes: [String: String] = [:]
    var collections: [ArticleCollection] = []
    var listened: Set<String> = []
    var mutes = MuteRules()
}
// A separate atomic store keeps the legacy SQLite read/save records untouched.
// All disk I/O and indexed search execute away from the UI actor.
actor LibraryRepository {
    private let url: URL
    private var revision = 0
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("library-v1.json")
    }
    func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryState() }
        return try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: url))
    }
    func save(_ state: LibraryState, revision: Int) throws {
        guard revision >= self.revision else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.revision = revision
    }
}
struct SearchIndex: Sendable {
    struct Entry: Sendable { let article: ReaderArticle; let text: String }
    let entries: [Entry]
    init(_ articles: [ReaderArticle]) { entries = articles.map { Entry(article: $0, text: $0.searchableText) } }
    static func normalize(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.lowercased() }
    func find(_ query: String, date: String = "", category: String = "", saved: Set<String>? = nil, unread: Set<String>? = nil) -> [ReaderArticle] {
        let tokens = Self.normalize(query).split(whereSeparator: \.isWhitespace).prefix(5).map(String.init)
        return entries.filter { e in tokens.allSatisfy { e.text.contains($0) } && (date.isEmpty || e.article.digestDate == date) && (category.isEmpty || e.article.topics.contains(category)) && (saved == nil || saved!.contains(e.article.id)) && (unread == nil || !unread!.contains(e.article.id)) }.map(\.article).sorted { $0.digestDate == $1.digestDate ? $0.title < $1.title : $0.digestDate > $1.digestDate }
    }
}
struct BriefingPlan {
    let articles: [ReaderArticle]; let seconds: Double; let excluded: Int
    static func make(_ source: [ReaderArticle], minutes: Int, voice: BriefingVoice, rate: Double, listened: Set<String>, mutes: MuteRules) -> BriefingPlan {
        let eligible = source.enumerated().filter { !mutes.contains($0.element) }.sorted { a, b in
            let x = listened.contains(a.element.editionID), y = listened.contains(b.element.editionID)
            return x == y ? a.offset < b.offset : !x
        }.map(\.element)
        var selected: [ReaderArticle] = [], total = 0.0
        for article in eligible {
            if minutes == 0 { selected.append(article); total += (article.audioMetadata?[voice.rawValue]?.durationSeconds ?? Double(article.speechText.count) / 5) / max(rate, 0.1); continue }
            guard article.narrationLanguage == "ja", let metadata = article.audioMetadata?[voice.rawValue], metadata.durationSeconds > 0, article.audio?[voice.rawValue] != nil else { continue }
            let duration = metadata.durationSeconds / max(rate, 0.1) + (selected.isEmpty ? 0 : 0.4)
            if total + duration <= Double(minutes * 60) { selected.append(article); total += duration }
        }
        return BriefingPlan(articles: selected, seconds: total, excluded: source.count - selected.count)
    }
}
@MainActor final class ExperienceStore: ObservableObject {
    static let shared = ExperienceStore()
    @Published private(set) var state = LibraryState()
    @Published var error: String?
    @Published private(set) var ready = false
    private let repository: LibraryRepository
    private var revision = 0
    init(repository: LibraryRepository = LibraryRepository()) { self.repository = repository }
    func load() async {
        guard !ready else { return }
        do { state = try await repository.load(); ready = true } catch { self.error = "ライブラリの読み込みに失敗しました。既存ファイルは保持されています。" }
    }
    func ingest(_ articles: [ReaderArticle], saved: Set<String>) {
        guard ready else { return }
        for article in articles { state.articles[article.editionID] = article }
        let cutoff = DateFormat.day(Date().addingTimeInterval(-30 * 86400))
        let pinned = Set(state.collections.flatMap { $0.editions }).union(state.notes.filter { !$0.value.isEmpty }.keys).union(state.downloadedEditions ?? [])
        state.articles = state.articles.filter { $0.value.digestDate >= cutoff || saved.contains($0.value.id) || pinned.contains($0.key) }
        persist()
    }
    func note(_ value: String, for article: ReaderArticle) { state.articles[article.editionID] = article; state.notes[article.editionID] = String(value.prefix(10000)); persist() }
    func addCollection(_ name: String) { let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; state.collections.append(ArticleCollection(name: String(clean.prefix(80)))); persist() }
    func deleteCollection(_ id: String) { state.collections.removeAll { $0.id == id }; persist() }
    func toggleCollection(_ id: String, article: ReaderArticle) {
        guard let index = state.collections.firstIndex(where: { $0.id == id }) else { return }
        state.articles[article.editionID] = article
        if state.collections[index].editions.contains(article.editionID) { state.collections[index].editions.remove(article.editionID) } else { state.collections[index].editions.insert(article.editionID) }; persist()
    }
    func beginPack(_ articles: [ReaderArticle], voice: BriefingVoice) -> String {
        let manifest = articles.compactMap { $0.audio?[voice.rawValue] }.sorted().joined(separator: "\n")
        let hash = SHA256.hash(data: Data(manifest.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        let id = (articles.first?.digestDate ?? DateFormat.day()) + "|" + voice.rawValue + "|" + hash
        if !(state.downloadPacks ?? []).contains(where: { $0.id == id }) {
            var packs = state.downloadPacks ?? []; packs.append(DownloadPack(id: id, date: articles.first?.digestDate ?? DateFormat.day(), voice: voice.rawValue, expectedCount: articles.count)); state.downloadPacks = packs; persist()
        }
        return id
    }
    func pinDownload(_ article: ReaderArticle, packID: String) {
        state.articles[article.editionID] = article
        var pins = state.downloadedEditions ?? []; pins.insert(article.editionID); state.downloadedEditions = pins
        if var packs = state.downloadPacks, let index = packs.firstIndex(where: { $0.id == packID }) {
            packs[index].articles.removeAll { $0.editionID == article.editionID }; packs[index].articles.append(article); state.downloadPacks = packs
        }
        persist()
    }
    func deletePack(_ id: String) async {
        guard let pack = state.downloadPacks?.first(where: { $0.id == id }) else { return }
        state.downloadPacks?.removeAll { $0.id == id }
        let retained = Set((state.downloadPacks ?? []).flatMap { $0.urls })
        for url in pack.urls.subtracting(retained) { await AudioCache.shared.discardDownload(url) }
        state.downloadedEditions = Set((state.downloadPacks ?? []).flatMap { $0.articles.map(\.editionID) }); persist()
    }
    func clearDownloadPins() { state.downloadedEditions = []; state.downloadPacks = []; persist() }
    func markListened(_ article: ReaderArticle) { state.listened.insert(article.editionID); persist() }
    func setMutes(_ rules: MuteRules) {
        func clean(_ values: [String]) -> [String] { var seen = Set<String>(); return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted } }
        state.mutes = MuteRules(keywords: clean(rules.keywords), categories: clean(rules.categories), feeds: clean(rules.feeds)); persist()
    }
    private func persist() {
        guard ready else { return }
        revision += 1; let version = revision, snapshot = state
        Task { do { try await repository.save(snapshot, revision: version) } catch { self.error = "端末への保存に失敗しました。空き容量を確認してください。" } }
    }
    static func removeLegacyXCredentials() {
        guard !UserDefaults.standard.bool(forKey: "removedXIntegrationV1") else { return }
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "com.takuyaops.aidigest.x", kSecAttrAccount: "credentials"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        try? FileManager.default.removeItem(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("x-posts.json"))
        UserDefaults.standard.removeObject(forKey: "xQuery")
        UserDefaults.standard.removeObject(forKey: "xMutedAuthors")
        UserDefaults.standard.set(true, forKey: "removedXIntegrationV1")
    }
}
