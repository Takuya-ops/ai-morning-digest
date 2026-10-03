import SwiftUI
import SafariServices

struct ArticleDetailView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @State var article: ReaderArticle
    @State private var style = SummaryStyle.short
    @State private var safari: BrowserLink?
    @State private var share: SharePayload?
    @AppStorage("defaultSummary") private var preferredStyle = "short"
    @AppStorage("readingSize") private var readingSize = 17.0
    @ScaledMetric(relativeTo: .body) private var scaledBodySize = 17.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(article.topics, id: \.self) { topic in Button { store.follow(topic) } label: { Label(topic, systemImage: store.followedTopics.contains(topic) ? "checkmark" : "plus").font(.caption).padding(.vertical, 10) }.buttonStyle(.bordered).accessibilityLabel("\(topic)を\(store.followedTopics.contains(topic) ? "フォロー解除" : "フォロー")") } } }
                Text(article.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text("\(article.sources.first?.feedName ?? "") · \(DateFormat.time(article.sources.first?.date ?? "")) JST").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    if article.availableSummaryStyles.count > 1 {
                        Picker("要約スタイル", selection: $style) {
                            ForEach(article.availableSummaryStyles) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("summaryStylePicker")
                    } else {
                        Text(article.availableSummaryStyles.first.map { "\($0.label)の要約" } ?? "記事の説明").font(.headline)
                    }
                    Label(article.aiGenerated ? "AI生成の要約" : "配信済みの要約・説明文", systemImage: article.aiGenerated ? "sparkles" : "doc.text").font(.caption).foregroundStyle(.secondary)
                    Text(article.summaryText(style)).font(.system(size: readingSize * scaledBodySize / 17)).lineSpacing(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("summaryText")
                    if article.availableSummaryStyles.count < SummaryStyle.allCases.count {
                        Label("この配信分には3種類の要約がそろっていません。用意されている本文を表示しています。要約は運営側で生成するため、利用者のAPIキー設定は不要です。", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let why = article.whyItMatters, !why.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Label("なぜ重要？", systemImage: "lightbulb").font(.headline); Text(why).font(.body).lineSpacing(6) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("この記事の疑問").font(.title3.bold())
                    if article.faq.isEmpty { Text("この配信分には事前生成のQ&Aがありません。").font(.subheadline).foregroundStyle(.secondary) }
                    else {
                        Label("AI生成 · 記事に記載のない内容は回答しません", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        ForEach(article.faq) { item in
                            DisclosureGroup { VStack(alignment: .leading, spacing: 12) { Text(item.a).lineSpacing(6).textSelection(.enabled); if let url = article.sourceURL { Button("出典を見る") { safari = BrowserLink(url: url) }.font(.caption) } }.padding(.vertical, 12) } label: { Text(item.q).font(.body.weight(.medium)).foregroundStyle(.primary).padding(.vertical, 10) }
                            Divider()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("出典").font(.headline)
                    if let source = article.sources.first, let url = source.url { Button { safari = BrowserLink(url: url) } label: { Text("\(source.feedName) · 元記事を読む").font(.subheadline).frame(minHeight: 44, alignment: .leading) } }
                    if article.sources.count > 1 {
                        DisclosureGroup("関連する出典 · \(article.sources.count - 1)件") {
                            ForEach(Array(article.sources.dropFirst())) { source in if let url = source.url { Button { safari = BrowserLink(url: url) } label: { Text(source.feedName).font(.subheadline).frame(minHeight: 44, alignment: .leading) } } }
                        }.font(.subheadline)
                    }
                    Text("情報は配信時点のものです。要約は誤りを含む場合があるため、重要な内容は出典でも確認してください。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .navigationTitle("記事").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { store.toggleSave(article) } label: { Label(store.savedIDs.contains(article.id) ? "保存済み" : "保存", systemImage: store.savedIDs.contains(article.id) ? "bookmark.fill" : "bookmark") }.accessibilityIdentifier("saveArticle")
                Spacer()
                Menu { Button("テキストと出典を共有") { share = SharePayload(items: ["\(article.title)\n\(article.summary)\n\(article.sourceURL?.absoluteString ?? "")"]) }; Button("要約カードを共有") { shareCard() } } label: { Label("共有", systemImage: "square.and.arrow.up") }
                Spacer()
                Button { playFromHere() } label: { Label("再生", systemImage: "play.fill") }
            }.font(.subheadline).padding(.horizontal, 20).frame(minHeight: 56).background(.regularMaterial)
        }
        .onAppear { style = article.resolvedSummaryStyle(SummaryStyle(rawValue: preferredStyle) ?? .short); store.markRead(article) }
        .onChange(of: article.id) { _ in style = article.resolvedSummaryStyle(SummaryStyle(rawValue: preferredStyle) ?? .short) }
        .sheet(item: $safari) { SafariView(url: $0.url).ignoresSafeArea() }
        .sheet(item: $share) { ShareSheet(items: $0.items) }
        .simultaneousGesture(DragGesture(minimumDistance: 70).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            let items = store.cachedDigest(article.digestDate)?.readerArticles ?? []
            guard let index = items.firstIndex(where: { $0.id == article.id }) else { return }
            let next = index + (value.translation.width < 0 ? 1 : -1)
            if items.indices.contains(next) { article = items[next]; store.markRead(article) }
        })
    }
    private func playFromHere() {
        let items = store.cachedDigest(article.digestDate)?.briefArticles ?? []
        if let index = items.firstIndex(where: { $0.id == article.id }) { player.start(items, at: index) } else { player.start([article]) }
    }
    @MainActor private func shareCard() {
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 24) {
            Text("AI MORNING DIGEST").font(.caption.bold()).foregroundStyle(Color.accentColor)
            Text(article.title).font(.title.bold())
            Text(article.summaryText(.short)).font(.body).lineSpacing(7)
            Divider(); Text("\(article.digestDate) · \(article.sources.first?.feedName ?? "")").font(.caption)
            Text("AIダイジェスト · \(article.aiGenerated ? "AI生成の要約" : "出典の説明文")").font(.caption)
        }.padding(36).frame(width: 560).background(Color.white).foregroundStyle(Color.black))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }
        var items: [Any] = [image]; if let url = article.sourceURL { items.append(url) }; share = SharePayload(items: items)
    }
}
struct BrowserLink: Identifiable { let id = UUID(); let url: URL }
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
struct SharePayload: Identifiable { let id = UUID(); let items: [Any] }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
