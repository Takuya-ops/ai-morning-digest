import SwiftUI
import AVFoundation

struct ListeningControls: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @EnvironmentObject var library: ExperienceStore
    @State private var minutes = 0
    var body: some View {
        let plan = BriefingPlan.make(store.orderedBrief, minutes: minutes, voice: player.voice, rate: player.rate, listened: library.state.listened, mutes: library.state.mutes)
        VStack(alignment: .leading, spacing: 12) {
            Picker("聴く時間", selection: $minutes) { Text("すべて").tag(0); Text("3分").tag(3); Text("5分").tag(5); Text("10分").tag(10) }.pickerStyle(.segmented)
            Button { player.start(plan.articles, completesBriefing: minutes == 0) } label: { Label("\(plan.articles.count)記事を再生 · 約\(max(1, Int(ceil(plan.seconds / 60))))分", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).disabled(plan.articles.isEmpty).accessibilityIdentifier("playBriefing")
            if minutes > 0 { Text("日本語・音声時間が確認できる記事から選びます。\(plan.excluded)件は時間超過・未準備・対象外です。未聴の記事を優先します。").font(.caption).foregroundStyle(.secondary) }
            if let digest = store.digest, let state = digest.publication?.audioByVoice[player.voice.rawValue] { Text(state.state == "ready" ? "音声配信済み" : state.state == "pending" ? "本文を先に公開しました。音声を準備中です。" : "音声は現在利用できません。本文は読めます。").font(.caption) }
            NavigationLink { DownloadView() } label: { Label("音声をまとめて保存", systemImage: "arrow.down.circle") }
        }
    }
}
struct PlayerDetailView: View {
    @EnvironmentObject var player: BriefingPlayer
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(player.current?.title ?? "").font(.headline); Text("\(player.index + 1) / \(player.articles.count)記事")
                    if player.canSeek { Slider(value: Binding(get: { player.position }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration)).accessibilityLabel("再生位置"); Text("\(Int(player.position)) / \(Int(player.duration))秒").monospacedDigit() }
                    else { Text("iPhone標準音声は記事単位で再開します。配信音声は秒単位で再開できます。").font(.caption) }
                    HStack { Button("15秒戻る") { player.seek(by: -15) }.disabled(!player.canSeek); Spacer(); Button(player.playing ? "一時停止" : "再生") { player.toggle() }; Spacer(); Button("15秒進む") { player.seek(by: 15) }.disabled(!player.canSeek) }.frame(minHeight: 44)
                }
                Section("スリープタイマー") { Picker("時間", selection: $player.sleepMinutes) { Text("オフ").tag(0); Text("15分").tag(15); Text("30分").tag(30) }; Toggle("この記事の終了で停止", isOn: $player.stopAfterArticle) }
                Section("再生する記事") { ForEach(Array(player.articles.enumerated()), id: \.offset) { i, article in Text("\(i + 1). \(article.title)").foregroundStyle(i == player.index ? Color.accentColor : .primary) } }
            }.navigationTitle("再生中").toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
@MainActor final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published var running = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = ""
    @Published var bytes = 0
    @Published var pinned = 0
    private var work: Task<Void, Never>?
    func refresh() async { let value = await AudioCache.shared.usage(); bytes = value.bytes; pinned = value.pinned }
    func cancel() { work?.cancel(); status = "停止しています。取得済み音声は残ります。" }
    func download(_ articles: [ReaderArticle], voice: BriefingVoice) {
        guard !running else { return }; running = true; completed = 0
        let available = articles.filter { $0.audio?[voice.rawValue].flatMap(WebURL.parse) != nil }; total = available.count
        work = Task {
            defer { running = false }
            do {
                for article in available {
                    try Task.checkCancellation()
                    let url = WebURL.parse(article.audio![voice.rawValue]!)!
                    _ = try await AudioCache.shared.verifiedFile(for: url, metadata: article.audioMetadata?[voice.rawValue])
                    try await AudioCache.shared.pin(url, value: true); ExperienceStore.shared.pinDownload(article); completed += 1; status = "\(completed) / \(total)件を保存"; await refresh()
                }
                status = total == 0 ? "この音声はまだ配信されていません。" : "保存完了。\(articles.count - total)件は音声未配信です。"
            } catch is CancellationError { status = "停止しました。取得済み音声は残っています。" }
            catch { status = "保存できませんでした。通信・空き容量を確認して再試行してください。取得済みの\(completed)件は残っています。" }
            await refresh()
        }
    }
}
struct DownloadView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @StateObject private var manager = DownloadManager.shared
    @AppStorage("autoDownloadWiFi") private var automatic = false
    @State private var confirm = false
    var body: some View {
        Form {
            Section("今日の音声 · \(player.voice.shortName)") {
                Button("まとめてダウンロード") { confirm = true }.disabled(manager.running || player.voice == .device)
                if manager.running { ProgressView(value: Double(manager.completed), total: Double(max(1, manager.total))); Button("停止") { manager.cancel() } }
                Text(manager.status).font(.subheadline)
                Text("手動保存はモバイル通信も使用します。保存済みの音声は圏外でも聴けます。").font(.caption)
            }
            Section("自動保存") { Toggle("Wi-Fi接続時に自動取得", isOn: $automatic); Text("アプリの更新時に取得します。自動取得は7日間・合計250 MiBが上限です。手動保存した音声は削除するまで保持します。").font(.caption) }
            Section("保存容量") { Text("\(Double(manager.bytes) / 1048576, specifier: "%.1f") / 250 MiB · 手動保存\(manager.pinned)件"); Button("保存音声を削除", role: .destructive) { Task { await AudioCache.shared.removeDownloads(); ExperienceStore.shared.clearDownloadPins(); await manager.refresh() } }.disabled(manager.running); Text("再生中の音声は残します。記事・メモ・保存マークは消えません。").font(.caption) }
        }.navigationTitle("ダウンロード").task { await manager.refresh() }
        .confirmationDialog("\(player.voice.shortName)の音声を保存します。モバイル通信でもダウンロードします。", isPresented: $confirm, titleVisibility: .visible) { Button("ダウンロード") { manager.download(store.orderedBrief, voice: player.voice) } }
    }
}
struct LocalSearchView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var library: ExperienceStore
    @State private var query = ""
    @State private var category = ""
    @State private var date = ""
    @State private var saved = false
    @State private var unread = false
    @State private var results: [ReaderArticle] = []
    private var key: String { [query, category, date, String(saved), String(unread), String(library.state.articles.count), store.savedIDs.sorted().joined(), store.readIDs.sorted().joined()].joined(separator: "|") }
    var body: some View {
        List {
            Section { Text("端末に取得した記事だけを検索します。空白で区切った最大5語のAND検索です。").font(.caption)
                Picker("カテゴリ", selection: $category) { Text("すべて").tag(""); ForEach(InterestTopics.all, id: \.self) { Text($0).tag($0) } }
                Picker("日付", selection: $date) { Text("すべて").tag(""); ForEach(Array(Set(library.state.articles.values.map(\.digestDate))).sorted(by: >), id: \.self) { Text($0).tag($0) } }
                Toggle("保存済みのみ", isOn: $saved); Toggle("未読のみ", isOn: $unread)
            }
            Section("\(results.count)件") { ForEach(results, id: \.editionID) { ArticleNavigationRow(article: $0) } }
        }.navigationTitle("記事を検索").searchable(text: $query, prompt: "見出し・要約・媒体")
            .task(id: key) {
                let articles = Array(library.state.articles.values), query = query, date = date, category = category, savedIDs = saved ? store.savedIDs : nil, readIDs = unread ? store.readIDs : nil
                let found = await Task.detached { SearchIndex(articles).find(query, date: date, category: category, saved: savedIDs, unread: readIDs) }.value
                if !Task.isCancelled { results = found }
            }
    }
}
struct ArticleNotebook: View {
    let article: ReaderArticle
    @EnvironmentObject var library: ExperienceStore
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自分のメモ").font(.headline)
            TextEditor(text: $note).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3))).accessibilityLabel("この記事のメモ")
            Text("端末内だけに保存します。AIには送信しません。最大10,000文字。").font(.caption).foregroundStyle(.secondary)
            Menu("コレクションに追加・解除") { ForEach(library.state.collections) { collection in Button((collection.editions.contains(article.editionID) ? "✓ " : "") + collection.name) { library.toggleCollection(collection.id, article: article) } } }
            if library.state.collections.isEmpty { Text("ライブラリからコレクションを作成できます。").font(.caption) }
        }.task(id: article.editionID) { note = library.state.notes[article.editionID] ?? "" }
            .onChange(of: note) { value in library.note(value, for: article) }
    }
}
struct CollectionsView: View {
    @EnvironmentObject var library: ExperienceStore
    @State private var name = ""
    var body: some View {
        List {
            Section("作成") { TextField("名前", text: $name); Button("作成") { library.addCollection(name); name = "" }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            Section("コレクション") { ForEach(library.state.collections) { collection in NavigationLink("\(collection.name) · \(collection.editions.count)件") { List { ForEach(collection.editions.sorted().compactMap { library.state.articles[$0] }, id: \.editionID) { ArticleNavigationRow(article: $0) } }.navigationTitle(collection.name) } }.onDelete { indices in let ids = indices.map { library.state.collections[$0].id }; ids.forEach(library.deleteCollection) } }
            Section("メモのある記事") { ForEach(library.state.notes.filter { !$0.value.isEmpty }.keys.sorted().compactMap { library.state.articles[$0] }, id: \.editionID) { ArticleNavigationRow(article: $0) } }
            Text("コレクションを削除しても、記事の保存マークやメモは残ります。").font(.caption)
        }.navigationTitle("コレクションとメモ")
    }
}
struct MuteSettingsView: View {
    @EnvironmentObject var library: ExperienceStore
    @State private var keyword = ""
    @State private var feed = ""
    var body: some View {
        Form {
            Section("キーワード") { TextField("見出し・要約から除外", text: $keyword); Button("追加") { var rules = library.state.mutes; if !keyword.trimmingCharacters(in: .whitespaces).isEmpty { rules.keywords.append(keyword.trimmingCharacters(in: .whitespaces)); library.setMutes(rules); keyword = "" } }; ForEach(library.state.mutes.keywords, id: \.self) { word in Button("解除: \(word)") { var rules = library.state.mutes; rules.keywords.removeAll { $0 == word }; library.setMutes(rules) } } }
            Section("カテゴリ") { ForEach(InterestTopics.all, id: \.self) { topic in Toggle(topic, isOn: Binding(get: { library.state.mutes.categories.contains(topic) }, set: { value in var rules = library.state.mutes; rules.categories.removeAll { $0 == topic }; if value { rules.categories.append(topic) }; library.setMutes(rules) })) } }
            Section("媒体名（完全一致）") { TextField("媒体名", text: $feed); Button("追加") { var rules = library.state.mutes; if !feed.isEmpty { rules.feeds.append(feed); library.setMutes(rules); feed = "" } }; ForEach(library.state.mutes.feeds, id: \.self) { item in Button("解除: \(item)") { var rules = library.state.mutes; rules.feeds.removeAll { $0 == item }; library.setMutes(rules) } } }
            Text("今日の一覧と新しい再生リストから除外します。保存記事・検索結果・再生中のリストは残ります。").font(.caption)
        }.navigationTitle("非表示の設定")
    }
}
struct WeeklyReviewView: View {
    @EnvironmentObject var library: ExperienceStore
    @EnvironmentObject var store: DigestStore
    @State private var weeksAgo = 0
    private var days: [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!; calendar.firstWeekday = 2
        let now = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return (0..<7).map { DateFormat.day(calendar.date(byAdding: .day, value: $0, to: start)!) }
    }
    var body: some View {
        let items = library.state.articles.values.filter { days.contains($0.digestDate) }
        let covered = Set(items.map(\.digestDate))
        List {
            Section { Stepper("\(weeksAgo == 0 ? "今週" : "\(weeksAgo)週前")", value: $weeksAgo, in: 0...52); Text("\(days.first!) 〜 \(days.last!)（日本時間）"); Text("取得済み \(covered.count)/7日 · \(items.count)記事"); Text("既読 \(items.filter { store.readIDs.contains($0.id) }.count) · 聴了 \(items.filter { library.state.listened.contains($0.editionID) }.count) · 保存 \(items.filter { store.savedIDs.contains($0.id) }.count)") }
            Section("テーマ別") { ForEach(InterestTopics.all, id: \.self) { topic in let count = items.filter { $0.topics.contains(topic) }.count; if count > 0 { LabeledContent(topic, value: "\(count)件") } } }
            Section("未取得・未配信の日") { ForEach(days.filter { !covered.contains($0) }, id: \.self) { Text($0) } }
            Section("今週の保存記事") { ForEach(items.filter { store.savedIDs.contains($0.id) }.sorted { $0.digestDate > $1.digestDate }, id: \.editionID) { ArticleNavigationRow(article: $0) } }
            Text("取得した記事の集計です。ニュース全体を網羅するAI要約ではありません。過去の週は端末に残っている記事だけを集計します。").font(.caption)
        }.navigationTitle("週次の振り返り")
    }
}
@MainActor final class VoicePreview: ObservableObject {
    private var audio: AVAudioPlayer?
    @Published var error: String?
    func play() {
        guard let url = Bundle.main.url(forResource: "gemini-preview", withExtension: "wav") else { error = "サンプルが見つかりません。"; return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio); try AVAudioSession.sharedInstance().setActive(true); audio = try AVAudioPlayer(contentsOf: url); audio?.play() } catch { self.error = "サンプルを再生できませんでした。" }
    }
    func stop() { audio?.stop() }
}
