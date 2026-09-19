import SwiftUI
import WidgetKit

struct WidgetSnapshot: Codable {
    struct Item: Codable { var title: String; var topic: String; var url: String }
    var date: String
    var items: [Item]
    static let empty = WidgetSnapshot(date: "", items: [])
}
struct DigestEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot }
struct DigestProvider: TimelineProvider {
    private var cacheURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.takuyaops.aidigest")?.appendingPathComponent("widget.json") }
    private var cached: WidgetSnapshot { cacheURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) } ?? .empty }
    func placeholder(in context: Context) -> DigestEntry { DigestEntry(date: Date(), snapshot: WidgetSnapshot(date: "今日", items: [.init(title: "朝のAIニュースを、ホーム画面から", topic: "AIニュース", url: "aidigest://today")])) }
    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : DigestEntry(date: Date(), snapshot: cached)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        Task {
            var snapshot = cached
            struct Response: Decodable { var date: String; var topics: [Topic]; struct Topic: Decodable { var headline: String; var topics: [String]?; var articles: [Article]; struct Article: Decodable { var link: String } } }
            var request = URLRequest(url: URL(string: "https://takuya-ops.github.io/ai-morning-digest/data/latest.json")!); request.timeoutInterval = 10
            if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200, let digest = try? JSONDecoder().decode(Response.self, from: data), digest.date > snapshot.date {
                snapshot = WidgetSnapshot(date: digest.date, items: digest.topics.prefix(3).map { topic in
                    var url = URLComponents(string: "aidigest://article")!; url.queryItems = [URLQueryItem(name: "id", value: topic.articles.first?.link)]
                    return .init(title: topic.headline, topic: topic.topics?.first ?? "AIニュース", url: url.string!)
                })
                if let cacheURL { try? JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic) }
            }
            // iOS decides the actual update time; this requests the next morning.
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let next = calendar.nextDate(after: Date(), matching: DateComponents(hour: 6, minute: 30), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [DigestEntry(date: Date(), snapshot: snapshot)], policy: .after(snapshot.items.isEmpty ? Date().addingTimeInterval(1800) : next)))
        }
    }
}
struct DigestWidgetView: View {
    var entry: DigestEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) { content.containerBackground(.background, for: .widget) } else { content.padding() }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 8) {
            if family != .accessoryRectangular { HStack { Image(systemName: "sun.horizon.fill").foregroundStyle(.orange); Text(entry.snapshot.date.isEmpty ? "AIダイジェスト" : entry.snapshot.date).font(.caption.bold()); Spacer() } }
            if entry.snapshot.items.isEmpty { Text("アプリを開いて、今朝のニュースを取得").font(.subheadline).widgetURL(URL(string: "aidigest://today")) }
            else {
                ForEach(Array(entry.snapshot.items.prefix(family == .systemMedium ? 3 : 1).enumerated()), id: \.offset) { _, item in
                    Link(destination: URL(string: item.url) ?? URL(string: "aidigest://today")!) {
                        HStack(alignment: .top, spacing: 6) {
                            if family == .systemMedium { Text(item.topic).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange).frame(width: 66, alignment: .leading) }
                            Text(item.title).font(family == .systemSmall ? .headline : .caption).lineLimit(family == .systemSmall ? 4 : 2).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if family == .systemSmall { Spacer(minLength: 0); Text("タップして読む・聴く").font(.caption2).foregroundStyle(.secondary) }
            }
        }.widgetURL(URL(string: entry.snapshot.items.first?.url ?? "aidigest://today"))
    }
}
@main
struct AIDigestWidget: Widget {
    let kind = "AIDigestWidget"
    var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: DigestProvider()) { DigestWidgetView(entry: $0) }.configurationDisplayName("AIダイジェスト").description("最新のAIニュースの見出しを、ホーム画面とロック画面に。").supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular]) }
}
