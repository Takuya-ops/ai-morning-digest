import Foundation
import CryptoKit

@MainActor
final class XStore: ObservableObject {
    @Published private(set) var credentials = XCredentials()
    @Published private(set) var account: XAccount?
    @Published private(set) var posts: [XPost] = []
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var loading = false
    @Published var message: String?
    @Published private(set) var mutedAuthors: [String] = UserDefaults.standard.stringArray(forKey: "xMutedAuthors") ?? []
    @Published var query: String = UserDefaults.standard.string(forKey: "xQuery") ?? "(生成AI OR OpenAI OR Anthropic OR Gemini) -is:retweet -is:reply"
    let service: XService
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("x-posts.json") }
    private struct Cache: Codable { var posts: [XPost]; var date: Date; var query: String }
    init(service: XService = XService()) {
        self.service = service
        do { credentials = try XKeychain.load() } catch { message = error.localizedDescription }
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data), Date().timeIntervalSince(cache.date) < 86400 {
            posts = cache.posts; fetchedAt = cache.date
        }
    }
    func saveCredentials(_ value: XCredentials) throws {
        guard !loading else { return }
        try XKeychain.save(value); credentials = value.trimmed(); account = nil; clearPosts()
    }
    func disconnect() throws { guard !loading else { return }; try XKeychain.delete(); credentials = XCredentials(); account = nil; clearPosts() }
    func mute(_ username: String) { if !mutedAuthors.contains(username) { mutedAuthors.append(username); UserDefaults.standard.set(mutedAuthors, forKey: "xMutedAuthors") } }
    func unmute(_ username: String) { mutedAuthors.removeAll { $0 == username }; UserDefaults.standard.set(mutedAuthors, forKey: "xMutedAuthors") }
    private func clearPosts() { posts = []; fetchedAt = nil; try? FileManager.default.removeItem(at: cacheURL) }
    func verifyAccount() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { account = try await service.account(credentials: credentials); message = "@\(account!.username) に接続しました。" } catch { account = nil; message = error.localizedDescription }
    }
    func refresh() async {
        guard !loading else { return }
        guard credentials.canRead else { message = XError.missingKeys.localizedDescription; return }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 512 else { message = "検索条件は1〜512文字で入力してください。"; return }
        loading = true; defer { loading = false }
        let requestedQuery = query
        do {
            let result = try await service.search(query: requestedQuery, credentials: credentials)
            posts = result; fetchedAt = Date(); message = result.isEmpty ? "条件に一致する投稿はありませんでした。" : nil
            UserDefaults.standard.set(requestedQuery, forKey: "xQuery")
            try? JSONEncoder().encode(Cache(posts: result, date: Date(), query: requestedQuery)).write(to: cacheURL, options: .atomic)
        } catch { message = error.localizedDescription }
    }
}

enum DraftFactory {
    static func make(_ digest: Digest) -> [PostDraft] {
        if let generated = digest.socialDrafts, !generated.isEmpty { return generated }
        let articles = digest.briefArticles.filter { $0.sourceURL != nil }
        guard !articles.isEmpty else { return [] }
        var drafts = (0..<10).map { index in
            let article = articles[index % articles.count], variant = index / articles.count
            let labels = ["AIニュース", "今日の注目", "朝のAIメモ", "AI動向まとめ", "チェックしたい発表", "今日のAIトピック", "AIニュース備忘録", "注目ニュースの要点", "AIニュースを読む", "朝のキャッチアップ"]
            let source = article.sourceURL!.absoluteString
            let body = variant % 2 == 0 ? article.summary : (article.whyItMatters ?? article.summary)
            let text = "\(XText.fit("【\(labels[variant % labels.count])】\n\(article.title)\n\(body)"))\n\(source)\n#生成AI"
            let stableID = SHA256.hash(data: Data(article.id.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
            return PostDraft(id: "\(digest.date)-\(stableID)-\(variant)", title: "\(index + 1). \(article.title)", text: text, sourceIDs: [String(stableID)], sourceURLs: [source], aiGenerated: false)
        }
        for group in 0..<2 {
            let selected = Array(articles.dropFirst(group * 3).prefix(3))
            guard selected.count == 3 else { continue }
            let sources = selected.compactMap { $0.sourceURL?.absoluteString }
            let label = group == 0 ? "AIニュース3選" : "あわせて読みたいAIニュース"
            let lines = selected.enumerated().map { i, article in "\(XText.fit(article.title, budget: 45))\n\(sources[i])" }.joined(separator: "\n")
            let hash = SHA256.hash(data: Data(sources.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
            drafts[8 + group] = PostDraft(id: "\(digest.date)-roundup-\(hash)", title: "\(9 + group). \(label)", text: "【\(label)】\n\(lines)\n#生成AI", sourceIDs: selected.map(\.id), sourceURLs: sources, aiGenerated: false)
        }
        return drafts
    }
}
