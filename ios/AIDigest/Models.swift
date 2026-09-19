import Foundation

// GitHub Pagesで毎朝公開される data/latest.json に対応するモデル
struct Digest: Codable {
    let date: String
    let generatedAt: String
    let since: String
    let stats: Stats
    let topics: [Topic]
    let others: [Article]
    var audioDurationSec: Int?
    var socialDrafts: [PostDraft]?

    var readerArticles: [ReaderArticle] {
        var seen = Set<String>()
        return (topics.map { ReaderArticle(topic: $0, digestDate: date) } + others.map { ReaderArticle(article: $0, digestDate: date) }).filter { seen.insert($0.id).inserted }
    }
    var briefArticles: [ReaderArticle] { topics.map { ReaderArticle(topic: $0, digestDate: date) } }
}

// data/index.json — 閲覧可能な日付の目録(新しい順)
struct DigestIndex: Codable {
    let dates: [String]
}

struct Stats: Codable {
    let articleCount: Int
    let feedCount: Int
    let topicCount: Int
}

struct Topic: Codable, Identifiable {
    var id: Int { rank }
    let rank: Int
    let headline: String
    let summary: String
    let whyItMatters: String?
    let sourceCount: Int
    let articles: [Article]
    var topics: [String]?
    var summaryStyles: SummaryStyles?
    var ttsText: String?
    var faq: [FAQ]?
    var aiGenerated: Bool?
    var audio: [String: String]?
}

struct Article: Codable, Identifiable, Hashable {
    var id: String { link }
    let title: String
    let link: String
    let feedName: String
    let date: String
    var excerpt: String?
    var thumbnailURL: String?

    var url: URL? { WebURL.parse(link) }
}

enum WebURL {
    static func parse(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

enum SummaryStyle: String, CaseIterable, Codable, Identifiable {
    case short, detail, simple
    var id: String { rawValue }
    var label: String { switch self { case .short: return "3行"; case .detail: return "詳細"; case .simple: return "やさしく" } }
}
struct SummaryStyles: Codable, Hashable {
    var short: String?
    var detail: String?
    var simple: String?
    init(short: String? = nil, detail: String? = nil, simple: String? = nil) {
        self.short = short; self.detail = detail; self.simple = simple
    }
    private enum CodingKeys: String, CodingKey { case short, detail, simple }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        short = try? values.decode(String.self, forKey: .short)
        detail = try? values.decode(String.self, forKey: .detail)
        simple = try? values.decode(String.self, forKey: .simple)
    }
    func text(_ style: SummaryStyle) -> String? {
        let value: String? = switch style { case .short: short; case .detail: detail; case .simple: simple }
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    // Older feeds sometimes copied the same summary into all three fields.
    // Only offer styles with real, distinct content.
    var available: [SummaryStyle] {
        var seen = Set<String>()
        return SummaryStyle.allCases.filter { style in
            guard let text = text(style) else { return false }
            let normalized = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            return seen.insert(normalized).inserted
        }
    }
}
struct FAQ: Codable, Hashable, Identifiable {
    var q: String
    var a: String
    var id: String { q }
}
enum InterestTopics {
    static let all = ["モデル・API", "エージェント", "画像・動画生成", "音声", "企業導入事例", "規制・政策", "研究・論文", "開発ツール", "国内動向", "資金調達・M&A"]
    static func infer(_ title: String) -> [String] {
        let terms = [["model", "モデル", "api", "gpt", "claude", "gemini"], ["agent", "エージェント"], ["image", "video", "画像", "動画"], ["audio", "speech", "voice", "音声"], ["企業", "導入", "enterprise"], ["regulat", "policy", "規制", "法案", "政策"], ["research", "paper", "研究", "論文"], ["開発", "code", "sdk", "tool"], ["日本", "国内", "japan"], ["funding", "acquisit", "資金", "買収"]]
        let result = all.enumerated().filter { i, _ in terms[i].contains { title.lowercased().contains($0) } }.map(\.element)
        return result.isEmpty ? [all[0]] : Array(result.prefix(3))
    }
}
struct ReaderArticle: Codable, Identifiable, Hashable {
    var id: String
    var digestDate: String
    var title: String
    var summary: String
    var whyItMatters: String?
    var topics: [String]
    var styles: SummaryStyles?
    var ttsText: String?
    var faq: [FAQ]
    var sources: [Article]
    var aiGenerated: Bool
    var audio: [String: String]?
    var sourceURL: URL? { sources.first?.url }
    var thumbnailURL: URL? { sources.first?.thumbnailURL.flatMap(WebURL.parse) }
    var availableSummaryStyles: [SummaryStyle] { styles?.available ?? [] }
    func resolvedSummaryStyle(_ preferred: SummaryStyle) -> SummaryStyle {
        availableSummaryStyles.contains(preferred) ? preferred : (availableSummaryStyles.first ?? .short)
    }
    func summaryText(_ preferred: SummaryStyle) -> String {
        styles?.text(resolvedSummaryStyle(preferred)) ?? summary
    }
    var speechText: String { (ttsText ?? "\(title)。\(summary)").replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression) }
    init(topic: Topic, digestDate: String) {
        id = topic.articles.first?.link ?? "\(digestDate)-\(topic.rank)"
        self.digestDate = digestDate; title = topic.headline; summary = topic.summary; whyItMatters = topic.whyItMatters
        topics = topic.topics ?? InterestTopics.infer(topic.headline); styles = topic.summaryStyles; ttsText = topic.ttsText
        faq = topic.faq ?? []; sources = topic.articles; aiGenerated = topic.aiGenerated ?? false; audio = topic.audio
    }
    init(article: Article, digestDate: String) {
        id = article.link; self.digestDate = digestDate; title = article.title
        summary = article.excerpt ?? "この過去記事には要約が配信されていません。出典で内容を確認できます。"
        topics = InterestTopics.infer(article.title); faq = []; sources = [article]; aiGenerated = false
    }
}
struct PostDraft: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var text: String
    var sourceIDs: [String]
    var sourceURLs: [String]
    var aiGenerated: Bool
}
struct XPost: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var username: String
    var name: String
    var createdAt: String
    var url: URL? { WebURL.parse("https://x.com/\(username)/status/\(id)") }
}

enum DateFormat {
    static func localStamp(_ date: Date) -> String {
        let f = Foundation.DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日 H:mm"; return f.string(from: date)
    }
    static func day(_ date: Date = Date()) -> String {
        let f = Foundation.DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }

    static func time(_ s: String) -> String {
        guard let d = parse(s) else { return "" }
        let f = Foundation.DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo") // 「JST」表記と一致させる(端末が海外タイムゾーンでも正しく)
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }

    static func longDate(_ ymd: String) -> String {
        let f = Foundation.DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return ymd }
        let out = Foundation.DateFormatter()
        out.locale = Locale(identifier: "ja_JP")
        out.dateFormat = "yyyy年M月d日(E)"
        return out.string(from: d)
    }
}
