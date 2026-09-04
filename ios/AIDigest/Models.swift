import Foundation

// GitHub Pagesで毎朝公開される data/latest.json に対応するモデル
struct Digest: Codable {
    let date: String
    let generatedAt: String
    let since: String
    let stats: Stats
    let topics: [Topic]
    let others: [Article]
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
}

struct Article: Codable, Identifiable, Hashable {
    var id: String { link }
    let title: String
    let link: String
    let feedName: String
    let date: String

    var url: URL? { URL(string: link) }
}

enum DateFormat {
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
