import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DigestStore
    @State private var showSettings = false
    @State private var showArchive = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let digest = store.digest {
                    digestList(digest)
                } else if store.isLoading {
                    ProgressView("今朝のダイジェストを取得中…")
                } else {
                    VStack(spacing: 12) {
                        Text("🌅").font(.system(size: 48))
                        Text(store.notice ?? "下に引っ張って更新してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("再読み込み") { Task { await store.reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("AIダイジェスト")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showArchive = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("過去のダイジェスト")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("通知設定")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .sheet(isPresented: $showArchive) { ArchiveSheet().environmentObject(store) }
        }
        .onChange(of: scenePhase) { phase in
            // 過去分を閲覧中に勝手に最新へ戻らないよう、最新表示のときだけ再取得する
            if phase == .active && store.isViewingLatest {
                Task { await store.reload() }
            }
        }
    }

    private func digestList(_ digest: Digest) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DateFormat.longDate(digest.date))
                        .font(.title3.bold())
                        .foregroundColor(.accentColor)
                    Text("📰 \(digest.stats.articleCount)記事 / 🗞️ \(digest.stats.feedCount)媒体 / 🧵 \(digest.stats.topicCount)トピック")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("更新: \(DateFormat.time(digest.generatedAt)) JST")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !store.isViewingLatest {
                        Text("📖 過去のダイジェストを表示中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let notice = store.notice {
                        Text("⚠️ \(notice)").font(.caption).foregroundColor(.orange)
                    }
                    dayNavigation
                }
                .padding(.vertical, 2)
            }

            if digest.topics.isEmpty {
                Section {
                    Text("対象期間内に生成AI関連のトピックが見つかりませんでした")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Section("今日の重要トピック TOP\(digest.topics.count)") {
                    ForEach(digest.topics) { TopicRow(topic: $0) }
                }
            }

            if !digest.others.isEmpty {
                Section("その他の生成AIニュース(\(digest.others.count)件)") {
                    ForEach(digest.others) { article in
                        ArticleRow(article: article)
                    }
                }
            }

            Section {
                Text("毎朝5:30(JST)に自動更新 / 国内外\(digest.stats.feedCount)媒体から収集")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
    }

    // 前日/翌日ナビゲーション(availableDatesが読めているときだけ表示)
    @ViewBuilder
    private var dayNavigation: some View {
        if !store.availableDates.isEmpty {
            HStack(spacing: 8) {
                Button {
                    Task { await store.showPrevious() }
                } label: {
                    Label("前日", systemImage: "chevron.left")
                        .font(.footnote)
                }
                .disabled(store.previousDate == nil)

                Spacer()

                if !store.isViewingLatest {
                    Button {
                        Task { await store.showLatest() }
                    } label: {
                        Text("最新へ")
                            .font(.footnote.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Spacer()

                Button {
                    Task { await store.showNext() }
                } label: {
                    HStack(spacing: 4) {
                        Text("翌日")
                        Image(systemName: "chevron.right")
                    }
                    .font(.footnote)
                }
                .disabled(store.nextDate == nil)
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
    }
}

// 過去のダイジェストの日付一覧シート
struct ArchiveSheet: View {
    @EnvironmentObject var store: DigestStore
    @Environment(\.dismiss) private var dismiss
    @State private var indexFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if store.availableDates.isEmpty {
                    if indexFailed {
                        VStack(spacing: 12) {
                            Text("日付一覧を取得できませんでした")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("再試行") {
                                Task {
                                    indexFailed = false
                                    indexFailed = !(await store.loadIndex())
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ProgressView("日付一覧を取得中…")
                    }
                } else {
                    List(store.availableDates, id: \.self) { date in
                        Button {
                            Task { await store.show(date: date) }
                            dismiss()
                        } label: {
                            HStack {
                                Text(DateFormat.longDate(date))
                                    .foregroundColor(.primary)
                                if date == store.availableDates.first {
                                    Text("最新")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(6)
                                }
                                Spacer()
                                if date == store.digest?.date {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("過去のダイジェスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { indexFailed = !(await store.loadIndex()) }
        }
    }
}

struct TopicRow: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RankBadge(rank: topic.rank)
                if let url = topic.articles.first?.url {
                    Link(destination: url) {
                        Text(topic.headline)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(topic.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(topic.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let why = topic.whyItMatters, !why.isEmpty {
                Label(why, systemImage: "lightbulb")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }
            if topic.articles.count > 1 {
                DisclosureGroup("関連記事 \(topic.articles.count)件") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(topic.articles) { article in
                            ArticleRow(article: article)
                                .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            } else if let article = topic.articles.first {
                Text(article.feedName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        // Listの行全体が先頭のLinkに反応しないようにし、見出し/展開/各記事を個別にタップ可能にする
        .buttonStyle(.borderless)
    }
}

struct ArticleRow: View {
    let article: Article

    var body: some View {
        if let url = article.url {
            Link(destination: url) {
                rowContent
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(article.title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Text(article.feedName)
                Text(DateFormat.time(article.date))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct RankBadge: View {
    let rank: Int

    private var color: Color {
        switch rank {
        case 1: return Color(red: 0.79, green: 0.59, blue: 0.0)
        case 2: return Color(red: 0.54, green: 0.58, blue: 0.62)
        case 3: return Color(red: 0.66, green: 0.44, blue: 0.29)
        default: return Color(.systemGray5)
        }
    }

    var body: some View {
        Text("\(rank)")
            .font(.subheadline.bold())
            .foregroundColor(rank <= 3 ? .white : .primary)
            .frame(width: 30, height: 30)
            .background(color)
            .cornerRadius(8)
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notifyEnabled") private var notifyEnabled = false
    @AppStorage("notifyHour") private var notifyHour = 6
    @AppStorage("notifyMinute") private var notifyMinute = 30
    @State private var showDeniedAlert = false

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: notifyHour, minute: notifyMinute)) ?? Date()
        } set: { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            notifyHour = comps.hour ?? 6
            notifyMinute = comps.minute ?? 30
            Task { await NotificationManager.reschedule() }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("毎朝通知する", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { newValue in
                            Task {
                                let ok = await NotificationManager.reschedule()
                                if newValue && !ok {
                                    notifyEnabled = false
                                    showDeniedAlert = true
                                }
                            }
                        }
                    if notifyEnabled {
                        DatePicker("通知時刻", selection: timeBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("ダイジェストは毎朝5:30(JST)ごろに更新されます。それ以降の時刻がおすすめです。")
                }
            }
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .alert("通知が許可されていません", isPresented: $showDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iOSの設定 → AIダイジェスト → 通知 から許可してください。")
            }
        }
    }
}
