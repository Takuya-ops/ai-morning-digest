import Foundation
import WidgetKit

enum WidgetBridge {
    static let group = "group.com.takuyaops.aidigest"
    static func update(digest: Digest, articles: [ReaderArticle]) {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let items = articles.prefix(3).map { article -> [String: String] in
            var link = URLComponents(); link.scheme = "aidigest"; link.host = "article"; link.queryItems = [URLQueryItem(name: "id", value: article.id)]
            return ["title": article.title, "topic": article.topics.first ?? "AIニュース", "url": link.string ?? "aidigest://today"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["date": digest.date, "items": items]) else { return }
        try? data.write(to: root.appendingPathComponent("widget.json"), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
