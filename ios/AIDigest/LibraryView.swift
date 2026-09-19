import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: DigestStore
    @State private var section = 0
    @State private var calendar = false
    @State private var selectedDate = Date()
    @State private var archive: Digest?
    @State private var loading = false
    @State private var failure = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("ライブラリ", selection: $section) { Text("保存済み").tag(0); Text("アーカイブ").tag(1) }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            if section == 0 {
                if store.savedArticles.isEmpty { EmptyPanel(icon: "bookmark", title: "あとで読みたい記事を保存", message: "記事を左にスワイプするか、記事内の保存ボタンを押すとここに残ります。") }
                else { List { ForEach(store.savedArticles) { ArticleNavigationRow(article: $0) } }.listStyle(.insetGrouped) }
            } else {
                List {
                    if calendar {
                        DatePicker("日付", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical)
                        Button("選択した日を開く") { load(DateFormat.day(selectedDate)) }
                    }
                    Section("\(store.cachedDates.count)日分を端末に保存") {
                        ForEach(store.availableDates, id: \.self) { day in
                            Button { load(day) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(DateFormat.longDate(day)).foregroundStyle(.primary)
                                        if let digest = store.cachedDigest(day) { Text("\(digest.readerArticles.count)記事 · \(digest.briefArticles.filter { store.readIDs.contains($0.id) }.count)/\(digest.briefArticles.count)トピック読了").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(); Image(systemName: store.cachedDates.contains(day) ? "arrow.down.circle.fill" : "icloud.and.arrow.down").foregroundStyle(Color.accentColor)
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                    Text("直近7日分を自動取得し、30日間保存します。保存済み記事は期限後も残ります。画像は端末のキャッシュ容量により削除されることがあります。").font(.caption).foregroundStyle(.secondary)
                }.listStyle(.insetGrouped)
            }
        }.navigationTitle("ライブラリ")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if section == 1 { Button { calendar.toggle() } label: { Image(systemName: calendar ? "list.bullet" : "calendar") }.accessibilityLabel("カレンダー表示切替") } } }
            .overlay { if loading { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
            .sheet(isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } })) {
                if let archive { NavigationStack { List { Section(DateFormat.longDate(archive.date)) { ForEach(archive.readerArticles) { ArticleNavigationRow(article: $0) } } }.navigationTitle("アーカイブ").toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { self.archive = nil } } } }.playerInset() }
            }
            .alert("この日を開けませんでした", isPresented: $failure) { Button("OK") {} } message: { Text("未配信の日付、または端末に未保存のデータです。通信状態と日付を確認してください。") }
    }
    private func load(_ day: String) { guard !loading else { return }; loading = true; Task { archive = await store.archive(day); failure = archive == nil; loading = false } }
}
