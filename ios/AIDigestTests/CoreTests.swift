import XCTest
import UserNotifications
@testable import AIDigest

final class CoreTests: XCTestCase {
    private let legacy = #"{"date":"2026-09-12","generatedAt":"2026-09-12T00:00:00Z","since":"2026-09-11T00:00:00Z","stats":{"articleCount":1,"feedCount":1,"topicCount":1},"topics":[{"rank":1,"headline":"音声モデル","summary":"事実に基づく要約です。","sourceCount":1,"articles":[{"title":"Original","link":"https://example.com/news","feedName":"Source","date":"2026-09-12T00:00:00Z"}]}],"others":[]}"#
    func testLegacyDecodeAndStableArticleIdentity() throws {
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        XCTAssertNil(digest.topics[0].summaryStyles)
        XCTAssertEqual(digest.readerArticles[0].id, "https://example.com/news")
        XCTAssertEqual(digest.readerArticles[0].faq, [])
    }
    func testV2SummaryStylesAndFAQDecodeWithoutBreakingLegacyFields() throws {
        var object = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as! [String: Any]
        var topics = object["topics"] as! [[String: Any]]
        topics[0]["id"] = "a-stable-id"
        topics[0]["aiGenerated"] = true
        topics[0]["topics"] = ["音声"]
        topics[0]["summaryStyles"] = ["short": "短い要約", "detail": "詳細の要約", "simple": "やさしい説明"]
        topics[0]["faq"] = [["q": "日本で使えますか？", "a": "記事には記載なし"]]
        topics[0]["audio"] = ["ja-JP-NanamiNeural": "https://example.com/nanami.mp3", "ja-JP-KeitaNeural": "https://example.com/keita.mp3"]
        object["topics"] = topics
        let digest = try JSONDecoder().decode(Digest.self, from: JSONSerialization.data(withJSONObject: object))
        let article = try XCTUnwrap(digest.readerArticles.first)
        XCTAssertEqual(article.styles?.text(.detail), "詳細の要約"); XCTAssertEqual(article.styles?.text(.simple), "やさしい説明")
        XCTAssertEqual(article.faq.first?.a, "記事には記載なし"); XCTAssertTrue(article.aiGenerated)
        XCTAssertEqual(article.audio?[BriefingVoice.nanami.rawValue], "https://example.com/nanami.mp3")
        XCTAssertEqual(article.availableSummaryStyles, [.short, .detail, .simple])
        XCTAssertEqual(article.summaryText(.detail), "詳細の要約")
        XCTAssertEqual(article.summaryText(.simple), "やさしい説明")
    }
    func testMissingOrPartialStylesNeverShowEmptyContent() throws {
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        var article = digest.readerArticles[0]
        XCTAssertEqual(article.availableSummaryStyles, [])
        for style in SummaryStyle.allCases { XCTAssertEqual(article.summaryText(style), article.summary) }
        article.styles = try JSONDecoder().decode(SummaryStyles.self, from: Data(#"{"short":null,"detail":"  詳しい説明  ","simple":99}"#.utf8))
        XCTAssertEqual(article.availableSummaryStyles, [.detail])
        XCTAssertEqual(article.resolvedSummaryStyle(.simple), .detail)
        XCTAssertEqual(article.summaryText(.simple), "詳しい説明")
        article.styles = SummaryStyles(short: "\n ", detail: nil, simple: "")
        XCTAssertEqual(article.availableSummaryStyles, [])
        XCTAssertEqual(article.summaryText(.short), article.summary)
    }
    func testDuplicateLegacyStylesAreNotOfferedAsDifferentSummaries() throws {
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        var article = digest.readerArticles[0]
        article.styles = SummaryStyles(short: "一文目。\n二文目。\n三文目。", detail: "一文目。 二文目。 三文目。", simple: "用語を説明します。")
        XCTAssertEqual(article.availableSummaryStyles, [.short, .simple])
        XCTAssertEqual(article.resolvedSummaryStyle(.detail), .short)
        XCTAssertEqual(article.summaryText(.short).components(separatedBy: "\n").count, 3)
        XCTAssertEqual(article.summaryText(.simple), "用語を説明します。")
    }
    @MainActor func testDatabasePreservesReadSavedAcrossRefreshAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.sqlite")
        let db = try LocalDatabase(url: url)
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        try db.save(digest); let article = digest.readerArticles[0]
        try db.markRead(article.id); try db.setSaved(article, saved: true)
        try db.save(digest)
        let reopened = try LocalDatabase(url: url)
        XCTAssertTrue(try reopened.states().read.contains(article.id))
        XCTAssertTrue(try reopened.states().saved.contains(article.id))
        XCTAssertEqual(try reopened.savedArticles().first?.title, article.title)
        XCTAssertNotNil(reopened.fetchedAt(digest.date))
        try reopened.prune(now: DateFormat.parse("2026-11-12T00:00:00Z")!)
        XCTAssertTrue(try reopened.cachedDates().isEmpty)
        XCTAssertEqual(try reopened.savedArticles().count, 1)
        try reopened.setSaved(article, saved: false); try reopened.prune(now: DateFormat.parse("2026-11-12T00:00:00Z")!)
        XCTAssertNil(reopened.article(id: article.id))
    }
    @MainActor func testTopicOrderDoesNotDiscardUnfollowedArticles() throws {
        let db = try LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = DigestStore(database: db)
        let previousTopics = store.followedTopics
        defer { store.followedTopics = previousTopics }
        store.followedTopics = ["音声"]
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        var second = digest.readerArticles[0]; second.id = "second"; second.topics = ["開発ツール"]
        XCTAssertEqual(store.ordered([second, digest.readerArticles[0]]).map(\.id), [digest.readerArticles[0].id, "second"])
    }
    @MainActor func testNotificationWeekdaysFutureOnlyAndNoStaleHeadlines() throws {
        let suite = "NotificationTest-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7, forKey: "notifyHour"); defaults.set(0, forKey: "notifyMinute"); defaults.set(true, forKey: "notifyWeekdays"); defaults.set(true, forKey: "notifyAutoplay")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = DateFormat.parse("2026-09-11T06:00:00+09:00")!
        let requests = NotificationManager.requests(now: now, headline: "本日の見出し", calendar: calendar, defaults: defaults)
        XCTAssertTrue(requests.count <= 30)
        XCTAssertEqual(requests.first?.content.body, "本日の見出し")
        for request in requests.dropFirst() { XCTAssertNotEqual(request.content.body, "本日の見出し") }
        for request in requests {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            let date = try XCTUnwrap(calendar.date(from: trigger.dateComponents))
            XCTAssertGreaterThan(date, now); XCTAssertFalse([1, 7].contains(calendar.component(.weekday, from: date)))
            XCTAssertEqual(request.content.userInfo["url"] as? String, "aidigest://today?autoplay=1")
        }
    }
    @MainActor func testOfflineStartupImmediatelyRestoresCachedDigest() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try LocalDatabase(url: url)
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        try db.save(digest)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockNetworkProtocol.self]
        MockNetworkProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = DigestStore(database: db, session: URLSession(configuration: config))
        XCTAssertEqual(store.digest?.date, "2026-09-12")
        let success = await store.refresh()
        XCTAssertFalse(success); XCTAssertTrue(store.offline); XCTAssertEqual(store.digest?.topics.count, 1)
    }
    @MainActor func testArchivePrefetchCannotOverwriteNewerSavedContent() throws {
        let db = try LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let current = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        let old = try JSONDecoder().decode(Digest.self, from: Data(legacy.replacingOccurrences(of: "2026-09-12", with: "2026-09-11").replacingOccurrences(of: "音声モデル", with: "古い見出し").utf8))
        try db.save(current); try db.setSaved(current.readerArticles[0], saved: true); try db.save(old)
        XCTAssertEqual(try db.savedArticles().first?.title, "音声モデル")
        XCTAssertEqual(try db.cachedDates().count, 2)
    }

}

final class MockNetworkProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        do { let (status, data) = try Self.handler(request); client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MicrosoftAudioTests: XCTestCase {
    @MainActor
    func testExistingVoiceMigratesOnlyWhenAllGeminiAudioExistsAndRespectsLaterChoice() {
        let defaults = UserDefaults.standard
        let keys = ["briefingVoice", "geminiVoicePreferenceV1"]
        let original = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, original) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set("device", forKey: "briefingVoice")
        defaults.removeObject(forKey: "geminiVoicePreferenceV1")
        let player = BriefingPlayer()
        var article = ReaderArticle(article: Article(title: "ニュース", link: "https://example.com/news", feedName: "test", date: "2026-10-04"), digestDate: "2026-10-04")
        player.adoptGeminiDefaultIfAvailable([article])
        XCTAssertEqual(player.voice, .device)
        article.audio = [BriefingVoice.gemini.rawValue: "https://example.com/gemini.wav"]
        player.adoptGeminiDefaultIfAvailable([article])
        XCTAssertEqual(player.voice, .gemini)
        player.voice = .nanami
        player.adoptGeminiDefaultIfAvailable([article])
        XCTAssertEqual(player.voice, .nanami)
    }
    func testGeminiIsFirstAndLegacyVoicesRemainAvailable() {
        XCTAssertEqual(BriefingVoice.allCases.first, .gemini)
        XCTAssertEqual(BriefingVoice.gemini.rawValue, "gemini-3.8-flash-tts-Kore")
    }
    func testGeminiWAVIsCachedWithCorrectExtensionAndWorksOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockNetworkProtocol.self]
        var bytes = Data(repeating: 0, count: 1004)
        bytes.replaceSubrange(0..<4, with: Data("RIFF".utf8))
        bytes.replaceSubrange(8..<12, with: Data("WAVE".utf8))
        MockNetworkProtocol.requests = []; MockNetworkProtocol.handler = { _ in (200, bytes) }
        let session = URLSession(configuration: config)
        let cache = AudioCache(directory: directory, session: session)
        let url = URL(string: "https://github.com/owner/repo/releases/download/day/gemini.wav")!
        let local = try await cache.file(for: url)
        XCTAssertEqual(local.pathExtension, "wav")
        XCTAssertEqual(try Data(contentsOf: local), bytes)
        MockNetworkProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let reopened = AudioCache(directory: directory, session: session)
        let offline = try await reopened.file(for: url)
        XCTAssertEqual(local, offline)
        XCTAssertEqual(MockNetworkProtocol.requests.count, 1)
        await cache.invalidate(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
    }
    func testNanamiAndKeitaAvailableInPicker() {
        XCTAssertEqual(BriefingVoice.nanami.rawValue, "ja-JP-NanamiNeural")
        XCTAssertTrue(BriefingVoice.allCases.contains(.nanami)); XCTAssertTrue(BriefingVoice.allCases.contains(.keita))
    }
    func testDownloadedAudioIsReusedAfterRestartWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockNetworkProtocol.self]
        let session = URLSession(configuration: config)
        let bytes = Data([0x49, 0x44, 0x33] + Array(repeating: UInt8(0), count: 600))
        MockNetworkProtocol.requests = []; MockNetworkProtocol.handler = { _ in (200, bytes) }
        let url = URL(string: "https://github.com/owner/repo/releases/download/date/nanami.mp3")!
        let cache = AudioCache(directory: directory, session: session)
        let local = try await cache.file(for: url)
        XCTAssertEqual(try Data(contentsOf: local), bytes)
        MockNetworkProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let reopened = AudioCache(directory: directory, session: session)
        let offline = try await reopened.file(for: url)
        XCTAssertEqual(local, offline); XCTAssertEqual(MockNetworkProtocol.requests.count, 1)
    }
    func testErrorPageIsNotCachedAsAudio() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockNetworkProtocol.self]
        MockNetworkProtocol.handler = { _ in (200, Data(String(repeating: "<html>error</html>", count: 50).utf8)) }
        let cache = AudioCache(directory: directory, session: URLSession(configuration: config))
        do { _ = try await cache.file(for: URL(string: "https://example.com/audio.mp3")!); XCTFail("HTML must not be cached") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

final class ExperienceTests: XCTestCase {
    private func article(_ id: String = "one", day: String = "2026-10-04") -> ReaderArticle {
        var article = ReaderArticle(article: Article(title: "ＧＰＴ 音声モデル", link: "https://example.com/\(id)", feedName: "Source", date: day, excerpt: "要約の検索テストです。"), digestDate: day)
        article.narrationLanguage = "ja"; article.topics = ["音声"]
        article.audio = [BriefingVoice.gemini.rawValue: "https://example.com/a.wav"]
        article.audioMetadata = [BriefingVoice.gemini.rawValue: AudioMetadata(durationSeconds: 100, byteLength: 1000, mimeType: "audio/wav", assetSHA256: "hash", scriptHash: "script")]
        return article
    }
    func testPlannerHonorsBudgetRateLanguageAndListenedPriority() {
        let a = article(), b = article("two"); var unknown = article("three"); unknown.narrationLanguage = nil
        let plan = BriefingPlan.make([a, b, unknown], minutes: 3, voice: .gemini, rate: 1, listened: [a.editionID], mutes: MuteRules())
        XCTAssertEqual(plan.articles.map(\.id), [b.id]); XCTAssertLessThanOrEqual(plan.seconds, 180)
        let fast = BriefingPlan.make([a, b, unknown], minutes: 3, voice: .gemini, rate: 1.5, listened: [], mutes: MuteRules())
        XCTAssertEqual(fast.articles.count, 2); XCTAssertEqual(fast.seconds, 200 / 1.5 + 0.4, accuracy: 0.001)
    }
    func testSearchNormalizesWidthAndCaseAndKeepsEditionsSeparate() {
        let a = article(), b = article(day: "2026-10-03"), index = SearchIndex([a, b])
        XCTAssertEqual(index.find("gpt 音声").count, 2)
        XCTAssertEqual(index.find("gpt", date: "2026-10-03").map(\.editionID), [b.editionID])
        XCTAssertTrue(index.find("gpt 不一致").isEmpty)
        XCTAssertTrue(index.find("", unread: [a.id]).isEmpty)
        XCTAssertEqual(index.find("", saved: [a.id]).count, 2)
    }
    func testMutesCoverKeywordCategoryAndFeed() {
        let a = article()
        XCTAssertTrue(MuteRules(keywords: ["gpt"]).contains(a))
        XCTAssertTrue(MuteRules(categories: ["音声"]).contains(a))
        XCTAssertTrue(MuteRules(feeds: ["Source"]).contains(a))
        XCTAssertFalse(MuteRules(keywords: ["別の話題"]).contains(a))
        XCTAssertTrue(BriefingPlan.make([a], minutes: 0, voice: .gemini, rate: 1, listened: [], mutes: MuteRules(feeds: ["Source"])).articles.isEmpty)
    }
    func testRepositoryPersistsNotesCollectionsAndRejectsOlderWrites() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        let repository = LibraryRepository(url: url), a = article()
        var state = LibraryState(); state.articles[a.editionID] = a; state.notes[a.editionID] = "秘密のメモ"; state.collections = [ArticleCollection(name: "研究", editions: [a.editionID])]; state.listened = [a.editionID]
        try await repository.save(state, revision: 2); try await repository.save(LibraryState(), revision: 1)
        let reopened = try await LibraryRepository(url: url).load()
        XCTAssertEqual(reopened.notes[a.editionID], "秘密のメモ"); XCTAssertEqual(reopened.collections.first?.editions, [a.editionID]); XCTAssertEqual(reopened.listened, [a.editionID])
    }
    func testTenThousandArticleSearchBudget() {
        let articles = (0..<10000).map { article(String($0)) }, index = SearchIndex(articles)
        let start = Date(); XCTAssertEqual(index.find("gpt 音声").count, 10000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
    }
    @MainActor func testCollectionsDoNotDeleteNotesAndSnapshotSurvivesRetention() async throws {
        let repository = LibraryRepository(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), library = ExperienceStore(repository: repository)
        await library.load(); let a = article(day: "2020-01-01")
        library.addCollection("保存箱"); let id = try XCTUnwrap(library.state.collections.first?.id)
        library.toggleCollection(id, article: a); library.note("残す", for: a); library.deleteCollection(id); library.ingest([], saved: [])
        XCTAssertEqual(library.state.notes[a.editionID], "残す"); XCTAssertNotNil(library.state.articles[a.editionID]); XCTAssertTrue(library.state.collections.isEmpty)
    }
    @MainActor func testPlayerRestoresPausedQueueWithoutAutoplay() {
        let defaults = UserDefaults.standard, key = "playbackCheckpointV1", previous = defaults.data(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: key)
        let player = BriefingPlayer(); player.start([article()]); player.pause(); player.checkpoint()
        let restored = BriefingPlayer(); XCTAssertEqual(restored.current?.id, article().id); XCTAssertFalse(restored.playing); XCTAssertFalse(restored.preparing)
        player.stop(); restored.stop()
    }
}

final class DownloadPackTests: XCTestCase {
    @MainActor func testPackIdentityKeepsAContentRevisionAndDeletionKeepsNotes() async throws {
        let library = ExperienceStore(repository: LibraryRepository(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        await library.load()
        var article = ReaderArticle(article: Article(title: "保存する記事", link: "https://example.com/item", feedName: "Source", date: ""), digestDate: "2026-10-04")
        article.audio = [BriefingVoice.gemini.rawValue: "https://example.com/original.wav"]
        let first = library.beginPack([article], voice: .gemini); library.pinDownload(article, packID: first); library.note("残すメモ", for: article)
        XCTAssertEqual(library.beginPack([article], voice: .gemini), first)
        article.title = "更新された記事"; article.audio?[BriefingVoice.gemini.rawValue] = "https://example.com/new.wav"
        let second = library.beginPack([article], voice: .gemini); library.pinDownload(article, packID: second)
        XCTAssertNotEqual(first, second); XCTAssertEqual(library.state.downloadPacks?.first?.articles.first?.title, "保存する記事")
        await library.deletePack(first)
        XCTAssertEqual(library.state.downloadPacks?.count, 1); XCTAssertEqual(library.state.notes[article.editionID], "残すメモ"); XCTAssertTrue(library.state.downloadedEditions?.contains(article.editionID) == true)
    }
}
