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
        XCTAssertEqual(DraftFactory.make(digest).count, 10)
        XCTAssertEqual(Set(DraftFactory.make(digest).map(\.id)).count, 10)
        XCTAssertTrue(DraftFactory.make(digest).allSatisfy { XText.weight($0.text) <= 280 })
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
    @MainActor func testDatabasePreservesReadSavedAndEditedDraftAcrossRefreshAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.sqlite")
        let db = try LocalDatabase(url: url)
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        try db.save(digest); let article = digest.readerArticles[0]
        try db.markRead(article.id); try db.setSaved(article, saved: true)
        try db.saveDraft("draft-1", text: "編集中の文章", status: "unknown")
        try db.save(digest)
        let reopened = try LocalDatabase(url: url)
        XCTAssertTrue(try reopened.states().read.contains(article.id))
        XCTAssertTrue(try reopened.states().saved.contains(article.id))
        XCTAssertEqual(try reopened.savedArticles().first?.title, article.title)
        XCTAssertEqual(reopened.draftState("draft-1")?.text, "編集中の文章")
        XCTAssertEqual(reopened.draftState("draft-1")?.status, "unknown")
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
    func testWeightedTextUnicodeAndURLs() {
        XCTAssertEqual(XText.weight("日本語"), 6)
        XCTAssertEqual(XText.weight("cafe\u{301}"), 4)
        XCTAssertEqual(XText.weight("👨‍👩‍👧‍👦"), 2)
        XCTAssertEqual(XText.weight("https://example.com/long/path?query=hello"), 23)
        XCTAssertLessThanOrEqual(XText.weight(XText.fit(String(repeating: "日本語", count: 100))), 245)
        XCTAssertNil(WebURL.parse("javascript:alert(1)"))
    }
    @MainActor func testOfflineStartupImmediatelyRestoresCachedDigest() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try LocalDatabase(url: url)
        let digest = try JSONDecoder().decode(Digest.self, from: Data(legacy.utf8))
        try db.save(digest)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockXProtocol.self]
        MockXProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
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
    func testOAuthSigningGoldenVectorAndJSONBodyExcluded() {
        let credentials = XCredentials(apiKey: "key", apiSecret: "secret", accessToken: "token", accessSecret: "token-secret")
        let header = OAuth1.header(method: "POST", url: URL(string: "https://api.x.com/2/tweets")!, credentials: credentials, nonce: "fixed", timestamp: "1234567890")
        XCTAssertTrue(header.contains("oauth_signature=\"2%2Ffi6YIHgCxll7%2F28VQw7g8rd%2FY%3D\""))
        XCTAssertEqual(OAuth1.encode("a b+c/日本語"), "a%20b%2Bc%2F%E6%97%A5%E6%9C%AC%E8%AA%9E")
        let get = OAuth1.header(method: "GET", url: URL(string: "https://api.x.com/2/tweets/search/recent?query=AI%20news&max_results=10")!, credentials: credentials, nonce: "fixed", timestamp: "1234567890")
        XCTAssertNotEqual(header, get)
    }
}

final class MockXProtocol: URLProtocol {
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
final class XServiceTests: XCTestCase {
    var service: XService!
    let keys = XCredentials(apiKey: "key", apiSecret: "secret", accessToken: "token", accessSecret: "access-secret")
    override func setUp() { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockXProtocol.self]; service = XService(session: URLSession(configuration: config)); MockXProtocol.requests = [] }
    func testSuccessfulPostUsesUserOAuthAndReturnsResultURL() async throws {
        MockXProtocol.handler = { request in XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.absoluteString, "https://api.x.com/2/tweets"); XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("OAuth ") == true); return (201, Data(#"{"data":{"id":"12345"}}"#.utf8)) }
        let url = try await service.post(text: "確認済みのニュース", credentials: keys)
        XCTAssertEqual(url.absoluteString, "https://x.com/i/web/status/12345"); XCTAssertEqual(MockXProtocol.requests.count, 1)
    }
    func testTimeoutDoesNotRetryAndReportsUnknownOutcome() async {
        MockXProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await service.post(text: "ニュース", credentials: keys); XCTFail("must fail") }
        catch { guard case XError.unknownOutcome = error else { return XCTFail("wrong error: \(error)") } }
        XCTAssertEqual(MockXProtocol.requests.count, 1)
    }
    func testAppOnlyBearerCannotPostAndOverlengthDoesNotSend() async {
        do { _ = try await service.post(text: "ニュース", credentials: XCredentials(bearerToken: "read-only")); XCTFail("must reject") } catch {}
        do { _ = try await service.post(text: String(repeating: "日", count: 141), credentials: keys); XCTFail("must reject") } catch {}
        XCTAssertTrue(MockXProtocol.requests.isEmpty)
    }
    func testSearchAttributionAndBoundedQuery() async throws {
        MockXProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "max_results" }?.value, "10")
            XCTAssertEqual(query.first { $0.name == "query" }?.value, "生成AI C++")
            XCTAssertTrue(request.url!.absoluteString.contains("%2B%2B"))
            return (200, Data(#"{"data":[{"id":"1","text":"原文","author_id":"2","created_at":"2026-09-12T00:00:00Z"}],"includes":{"users":[{"id":"2","name":"Author","username":"author"}]},"meta":{"result_count":1}}"#.utf8))
        }
        let posts = try await service.search(query: "生成AI C++", credentials: keys)
        XCTAssertEqual(posts.first?.username, "author"); XCTAssertEqual(posts.first?.text, "原文"); XCTAssertEqual(posts.first?.url?.absoluteString, "https://x.com/author/status/1")
    }
}

final class MicrosoftAudioTests: XCTestCase {
    func testNanamiAndKeitaAvailableInPicker() {
        XCTAssertEqual(BriefingVoice.nanami.rawValue, "ja-JP-NanamiNeural")
        XCTAssertTrue(BriefingVoice.allCases.contains(.nanami)); XCTAssertTrue(BriefingVoice.allCases.contains(.keita))
    }
    func testDownloadedAudioIsReusedAfterRestartWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockXProtocol.self]
        let session = URLSession(configuration: config)
        let bytes = Data([0x49, 0x44, 0x33] + Array(repeating: UInt8(0), count: 600))
        MockXProtocol.requests = []; MockXProtocol.handler = { _ in (200, bytes) }
        let url = URL(string: "https://github.com/owner/repo/releases/download/date/nanami.mp3")!
        let cache = AudioCache(directory: directory, session: session)
        let local = try await cache.file(for: url)
        XCTAssertEqual(try Data(contentsOf: local), bytes)
        MockXProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let reopened = AudioCache(directory: directory, session: session)
        let offline = try await reopened.file(for: url)
        XCTAssertEqual(local, offline); XCTAssertEqual(MockXProtocol.requests.count, 1)
    }
    func testErrorPageIsNotCachedAsAudio() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockXProtocol.self]
        MockXProtocol.handler = { _ in (200, Data(String(repeating: "<html>error</html>", count: 50).utf8)) }
        let cache = AudioCache(directory: directory, session: URLSession(configuration: config))
        do { _ = try await cache.file(for: URL(string: "https://example.com/audio.mp3")!); XCTFail("HTML must not be cached") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
