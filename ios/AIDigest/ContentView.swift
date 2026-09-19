import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @EnvironmentObject var router: AppRouter
    @AppStorage("onboardingComplete") private var onboarded = false
    @State private var linkedArticle: ReaderArticle?
    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { TodayView() }.playerInset().tabItem { Label("今日", systemImage: "sun.max") }.tag(0)
            NavigationStack { XFeedView() }.playerInset().tabItem { Label("X", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            NavigationStack { DraftsView() }.playerInset().tabItem { Label("投稿案", systemImage: "square.and.pencil") }.tag(2)
            NavigationStack { LibraryView() }.playerInset().tabItem { Label("ライブラリ", systemImage: "books.vertical") }.tag(3)
            NavigationStack { SettingsView() }.playerInset().tabItem { Label("設定", systemImage: "gearshape") }.tag(4)
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) { OnboardingView() }
        .sheet(item: $linkedArticle) { article in NavigationStack { ArticleDetailView(article: article).toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { linkedArticle = nil } } } }.playerInset() }
        .onChange(of: router.articleID) { _ in handleLink() }
        .onChange(of: router.autoplay) { _ in handleLink() }
        .onChange(of: store.digest?.generatedAt) { _ in player.adoptMicrosoftDefaultIfAvailable(store.orderedBrief); handleLink() }
        .onChange(of: onboarded) { _ in handleLink() }
        .onAppear { player.adoptMicrosoftDefaultIfAvailable(store.orderedBrief); handleLink() }
        .alert("音声再生", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) { Button("OK") { player.error = nil } } message: { Text(player.error ?? "") }
    }
    private func handleLink() {
        guard onboarded else { return }
        if let id = router.articleID, let article = store.database?.article(id: id) ?? store.digest?.readerArticles.first(where: { $0.id == id }) { linkedArticle = article; router.articleID = nil }
        if router.autoplay, !store.orderedBrief.isEmpty { router.autoplay = false; player.start(store.orderedBrief, completesBriefing: true) }
    }
}
private struct PlayerInset: ViewModifier {
    @EnvironmentObject var player: BriefingPlayer
    func body(content: Content) -> some View { content.safeAreaInset(edge: .bottom, spacing: 0) { if player.current != nil { MiniPlayer() } } }
}
extension View { func playerInset() -> some View { modifier(PlayerInset()) } }

struct MiniPlayer: View {
    @EnvironmentObject var player: BriefingPlayer
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text(player.preparing ? "\(player.voice.shortName)の音声を準備中…" : player.current?.title ?? "").font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button { player.stop() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("再生を終了")
            }
            HStack {
                Text("\(player.index + 1) / \(player.articles.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { player.skip(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.disabled(player.index == 0).accessibilityLabel("前の記事")
                Button { player.toggle() } label: { if player.preparing { ProgressView().frame(width: 52, height: 44) } else { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 52, height: 44) } }.disabled(player.preparing).accessibilityLabel(player.playing ? "一時停止" : "再生を再開")
                Button { player.skip(1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.disabled(player.index + 1 >= player.articles.count).accessibilityLabel("次の記事")
                Spacer()
                Menu { ForEach([0.8, 1, 1.2, 1.5], id: \.self) { rate in Button("\(rate, specifier: "%.1f")x") { player.rate = rate } } } label: { Text("\(player.rate, specifier: "%.1f")x").font(.caption.bold()).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("読み上げ速度")
            }
        }.padding(.horizontal, 16).background(.regularMaterial)
    }
}

struct TodayView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @State private var unreadOnly = false
    var body: some View {
        Group {
            if let digest = store.digest { digestContent(digest) }
            else { EmptyPanel(icon: "sun.horizon", title: store.isLoading ? "朝のニュースを取得中" : "ダイジェストを読み込めません", message: store.notice ?? "初回はインターネットに接続してください。取得後はオフラインで読むことができます。") { Task { await store.refresh() } } }
        }
        .navigationTitle("今日")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if store.streak > 0 { Label("\(store.streak)日", systemImage: "flame").font(.caption).foregroundStyle(Color.accentColor) } } }
    }
    private func digestContent(_ digest: Digest) -> some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(DateFormat.longDate(digest.date)).font(.title3.bold())
                        Text("\(digest.stats.feedCount)媒体から、今知っておきたい動きを。").font(.subheadline).foregroundStyle(.secondary)
                        if digest.date != DateFormat.day() { Label("今日はまだ未配信です。\(digest.date)のダイジェストを表示中", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                        Button { player.start(store.orderedBrief, completesBriefing: true) } label: {
                            Label("再生 · 約\(max(1, Int(ceil(Double(store.orderedBrief.reduce(0) { $0 + $1.speechText.count }) / 300 / player.rate))))分", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(.borderedProminent).disabled(store.orderedBrief.isEmpty).accessibilityIdentifier("playBriefing")
                        Picker("音声", selection: $player.voice) { ForEach(BriefingVoice.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu)
                        if player.voice != .device, !store.orderedBrief.allSatisfy({ $0.audio?[player.voice.rawValue] != nil }) {
                            Text("この配信分には\(player.voice.shortName)の音声がありません。iPhoneの標準音声ですぐに聴けます。").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack { Label("\(player.voice.shortName)で読み上げ", systemImage: "headphones"); Spacer(); Text("\(digest.briefArticles.filter { store.readIDs.contains($0.id) }.count)/\(digest.briefArticles.count) 読了") }.font(.caption).foregroundStyle(.secondary)
                        if let notice = store.notice { Label(notice, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary) }
                        if let updated = store.lastUpdated { Text("最終取得 \(DateFormat.localStamp(updated))").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
                Section { Toggle("未読のみ表示", isOn: $unreadOnly).font(.subheadline) }
                ForEach(sectionNames(digest), id: \.self) { section in
                    let values = sectionArticles(section, digest: digest)
                    if !values.isEmpty {
                        Section(section) { ForEach(values) { article in ArticleNavigationRow(article: article).id(article.id) } }
                    }
                }
                if !digest.others.isEmpty {
                    Section("その他のニュース · \(digest.others.count)件") {
                        ForEach(digest.readerArticles.filter { !Set(digest.briefArticles.map(\.id)).contains($0.id) && (!unreadOnly || !store.readIDs.contains($0.id)) }) { article in ArticleNavigationRow(article: article) }
                    }
                }
                Section {
                    Button { store.completeBriefing(date: digest.date) } label: { Label(store.completedDays.contains(digest.date) ? "今日の読了を記録しました" : "今日のブリーフィングを読了", systemImage: "checkmark.circle") }.disabled(digest.date != DateFormat.day() || digest.topics.isEmpty)
                    Text("要約・疑問は配信時に作成。原文の全文ではありません。出典は各記事の末尾から確認できます。").font(.caption).foregroundStyle(.secondary)
                }
            }.listStyle(.insetGrouped).refreshable { await store.refresh() }
                .onChange(of: player.current?.id) { id in if let id, !unreadOnly { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
        }
    }
    private func sectionNames(_ digest: Digest) -> [String] { store.followedTopics.isEmpty ? ["今日の重要トピック"] : store.followedTopics + ["その他の動き"] }
    private func sectionArticles(_ section: String, digest: Digest) -> [ReaderArticle] {
        store.orderedBrief.filter { article in
            let label = store.followedTopics.first { article.topics.contains($0) } ?? (store.followedTopics.isEmpty ? "今日の重要トピック" : "その他の動き")
            return label == section && (!unreadOnly || !store.readIDs.contains(article.id))
        }
    }
}
struct ArticleNavigationRow: View {
    @EnvironmentObject var store: DigestStore
    let article: ReaderArticle
    var body: some View {
        NavigationLink { ArticleDetailView(article: article) } label: { NewsRow(article: article) }
            .swipeActions(edge: .trailing) { Button { store.toggleSave(article) } label: { Label(store.savedIDs.contains(article.id) ? "保存を解除" : "保存", systemImage: store.savedIDs.contains(article.id) ? "bookmark.slash" : "bookmark") }.tint(.accentColor) }
            .accessibilityIdentifier("articleRow")
    }
}
struct NewsRow: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    let article: ReaderArticle
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(url: article.thumbnailURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(article.topics.first ?? "AIニュース").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                Text(article.title).font(.headline).lineLimit(2).foregroundStyle(store.readIDs.contains(article.id) ? .secondary : .primary)
                Text(article.summary).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                HStack(spacing: 5) { Text(article.sources.first?.feedName ?? ""); if store.savedIDs.contains(article.id) { Image(systemName: "bookmark.fill") }; if player.current?.id == article.id { Image(systemName: "waveform").foregroundStyle(Color.accentColor) } }.font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8).listRowBackground(player.current?.id == article.id ? Color.accentColor.opacity(0.09) : nil)
    }
}
struct ThumbnailView: View {
    let url: URL?
    @State private var data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Color.accentColor.opacity(0.08); Image(systemName: "text.alignleft").font(.title2).foregroundStyle(Color.accentColor) } }
        }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            .task(id: url) { if let url { data = await ImageCache.shared.image(url) } }
    }
}
struct EmptyPanel: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 42)).foregroundStyle(Color.accentColor); Text(title).font(.title2.bold()); Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center); if let action { Button("再読み込み", action: action).buttonStyle(.borderedProminent) } }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
