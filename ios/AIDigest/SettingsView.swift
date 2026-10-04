import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @AppStorage("defaultSummary") private var summary = "short"
    @AppStorage("theme") private var theme = "system"
    @AppStorage("readingSize") private var readingSize = 17.0
    @AppStorage("speechVoice") private var voice = ""
    @State private var safari: BrowserLink?
    var body: some View {
        Form {
            NotificationSettings()
            Section("興味のあるトピック · \(store.followedTopics.count)件") { TopicChoices() }
            Section("読む") {
                Picker("要約のスタイル", selection: $summary) { ForEach(SummaryStyle.allCases) { Text($0.label).tag($0.rawValue) } }
                Text("3行・詳細・やさしくは、運営側で生成して配信します。利用者のAPIキーは不要です。選んだスタイルがない記事は、配信済みの本文を表示します。").font(.caption).foregroundStyle(.secondary)
                Picker("テーマ", selection: $theme) { Text("システム").tag("system"); Text("ライト").tag("light"); Text("ダーク").tag("dark") }
                Picker("記事の文字サイズ", selection: $readingSize) { Text("標準").tag(17.0); Text("大きめ").tag(20.0); Text("特大").tag(24.0) }
            }
            Section("ライブラリ") { NavigationLink("非表示キーワード・媒体") { MuteSettingsView() }; NavigationLink("AI用語集") { ScrollView { GlossaryView(text: nil) } } }
            Section("記録") { LabeledContent("連続読了", value: "\(store.streak)日"); LabeledContent("保存済みの記事", value: "\(store.savedIDs.count)件"); LabeledContent("オフライン保存", value: "\(store.cachedDates.count)日分") }
            Section("このアプリについて") {
                Text("AIダイジェスト \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")\n毎朝のニュースを、読む・保存する・振り返る。").font(.subheadline)
                Text("ホーム画面を長押し → ウィジェットを追加 → AIダイジェストで、最新の見出しを配置できます。").font(.subheadline)
                NavigationLink("プライバシーポリシー") { PrivacyView() }
                Button("サポート") { safari = BrowserLink(url: URL(string: "https://github.com/Takuya-ops/ai-morning-digest/issues")!) }
            }
        }.navigationTitle("設定").sheet(item: $safari) { SafariView(url: $0.url) }
    }
}
struct PrivacyView: View {
    var body: some View {
        List {
            Section("端末内の記録") { Text("興味トピック、通知・表示設定、既読・保存、読了日、メモ、コレクションを端末内に保存します。ダイジェストは30日、保存した記事は保存解除まで保持します。開発者によるアカウント登録、広告、行動分析はありません。") }
            Section("通信") { Text("ニュースはGitHub Pagesから取得し、画像は各配信元へ接続します。各配信先にはIPアドレスなど通信に必要な情報が伝わります。出典はアプリ内Safariで開きます。マイクでの録音は行わず、閲覧履歴や利用者の入力を生成AIへ送りません。") }
            Section { Text("最終更新 2026年10月4日").font(.caption); Link("Web版のポリシー・お問い合わせ", destination: URL(string: "https://takuya-ops.github.io/ai-morning-digest/privacy.html")!) }
        }.navigationTitle("プライバシー").navigationBarTitleDisplayMode(.inline)
    }
}
struct TopicChoices: View {
    @EnvironmentObject var store: DigestStore
    var body: some View {
        ForEach(InterestTopics.all, id: \.self) { topic in
            Button { store.follow(topic) } label: { HStack { Text(topic).foregroundStyle(.primary); Spacer(); Image(systemName: store.followedTopics.contains(topic) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.accentColor) }.frame(minHeight: 44) }.accessibilityLabel("\(topic)、\(store.followedTopics.contains(topic) ? "選択済み" : "未選択")")
        }
    }
}
struct NotificationSettings: View {
    @EnvironmentObject var store: DigestStore
    @AppStorage("notifyEnabled") private var enabled = false
    @AppStorage("notifyHour") private var hour = 7
    @AppStorage("notifyMinute") private var minute = 0
    @AppStorage("notifyWeekdays") private var weekdays = false
    @AppStorage("notifyAutoplay") private var autoplay = false
    @State private var message: String?
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() }, set: { value in let parts = Calendar.current.dateComponents([.hour, .minute], from: value); hour = parts.hour ?? 7; minute = parts.minute ?? 0; schedule() })
    }
    var body: some View {
        Section {
            Toggle("毎朝のリマインダー", isOn: $enabled).onChange(of: enabled) { _ in schedule(requestPermission: true) }
            DatePicker("通知時刻", selection: time, displayedComponents: .hourAndMinute).disabled(!enabled)
            Toggle("平日のみ", isOn: $weekdays).disabled(!enabled).onChange(of: weekdays) { _ in schedule() }
            Button("2分後にテスト通知") { Task { do { try await NotificationManager.testNotification(); message = "2分後に通知します。アプリを閉じてお待ちください。" } catch { message = error.localizedDescription } } }
        } header: { Text("配信時刻") } footer: { Text("端末の時刻で通知します。30日先まで予約し、起動・バックグラウンド更新で延長します。ニュースの更新は毎朝5:30 JST以降。バックグラウンド取得の時刻はiOSが決定します。") }
        .alert("通知", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil }; if enabled { Button("iOSの設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } } } message: { Text(message ?? "") }
    }
    private func schedule(requestPermission: Bool = false) {
        Task {
            let ok = await NotificationManager.reschedule(headline: store.digest?.date == DateFormat.day() ? store.orderedBrief.first?.title : nil, requestPermission: requestPermission)
            if !ok { message = "通知を予約できませんでした。iOSの設定で通知の許可を確認してください。" }
        }
    }
}
struct OnboardingView: View {
    @StateObject private var preview = VoicePreview()
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var player: BriefingPlayer
    @AppStorage("onboardingComplete") private var complete = false
    @State private var step = 0
    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 8) { ForEach(0..<3) { index in Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.2)).frame(width: 28, height: 4) } }.padding(.top, 24).accessibilityLabel("ステップ\(step + 1)/3")
                if step == 0 {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "sun.horizon.fill").font(.system(size: 64)).foregroundStyle(Color.accentColor)
                        Text("朝の6分を、\nAIを知る時間に。").font(.largeTitle.bold())
                        Text("ニュースを読む。気になる動きを追う。\n保存して、圏外でも振り返る。").font(.title3).foregroundStyle(.secondary).lineSpacing(8)
                        Label("登録不要 · 基本機能はすべて無料", systemImage: "checkmark.shield").font(.subheadline)
                        Spacer()
                    }.padding(28).padding(.top, 28)
                } else if step == 1 {
                    Form { Section { Text("気になるトピックを選ぶ").font(.title2.bold()); Text("3つを目安に、いくつでも。選んだテーマを上に表示します。あとから設定で変更できます。").foregroundStyle(.secondary) }; Section { TopicChoices() } }
                } else {
                    Form { Section { Text("朝の時間を決める").font(.title2.bold()); Text("通知は必要なときだけ。オフのままでも使えます。").foregroundStyle(.secondary) }; NotificationSettings() }
                }
                HStack {
                    if step > 0 { Button("戻る") { step -= 1 }.frame(minWidth: 60, minHeight: 48) }
                    Button(step == 2 ? "今日のダイジェストへ" : step == 1 && store.followedTopics.isEmpty ? "スキップして次へ" : "次へ") { preview.stop(); if step == 2 { complete = true } else { step += 1 } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 48)
                }.padding(20)
            }.background(Color(.systemGroupedBackground))
        }.interactiveDismissDisabled().onDisappear { preview.stop() }
    }
}
