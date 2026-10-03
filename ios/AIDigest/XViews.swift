import SwiftUI

struct XSettingsView: View {
    @EnvironmentObject var x: XStore
    @State private var keys = XCredentials()
    @State private var message: String?
    @State private var remove = false
    var body: some View {
        Form {
            Section {
                Text("ご自身のX開発者アプリのキーを設定すると、X情報の検索と、編集した投稿案の送信ができます。").font(.subheadline)
                Text("キーはこのiPhoneのKeychainに保存し、X APIにのみ送信します。開発者のサーバーや配信JSONには送信しません。").font(.caption).foregroundStyle(.secondary)
            }
            Section("投稿と検索 · OAuth 1.0a") {
                SecureField("API Key", text: $keys.apiKey)
                SecureField("API Key Secret", text: $keys.apiSecret)
                SecureField("Access Token", text: $keys.accessToken)
                SecureField("Access Token Secret", text: $keys.accessSecret)
                Text("XのApp permissionsをRead and writeに設定してください。権限を変更した場合はAccess TokenとSecretを再発行してください。").font(.caption).foregroundStyle(.secondary)
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Section("検索のみを使う場合") { SecureField("Bearer Token（任意）", text: $keys.bearerToken).textInputAutocapitalization(.never).autocorrectionDisabled(); Text("アプリ専用Bearer Tokenだけでは投稿できません。").font(.caption).foregroundStyle(.secondary) }
            Section {
                Button("キーを保存") { do { try x.saveCredentials(keys); message = "キーを保存しました。投稿する場合は接続アカウントを確認してください。" } catch { message = error.localizedDescription } }.disabled(x.loading)
                Button("接続アカウントを確認") { Task { await x.verifyAccount() } }.disabled(!x.credentials.canPost || x.loading)
                if let account = x.account { Label("\(account.name) @\(account.username)", systemImage: "checkmark.seal") }
                if x.loading { ProgressView() }
                if let text = x.message { Text(text).font(.caption).foregroundStyle(.secondary) }
                Button("連携を解除・キーを削除", role: .destructive) { remove = true }.disabled(x.loading)
            }
            Section("利用料金") {
                Text("X APIは利用量に応じたクレジット制です。検索は更新操作1回につき最大10投稿を取得します。検索・投稿・アカウント確認でAPI通信が発生します。XのDeveloper Consoleで利用条件と上限を確認してください。").font(.subheadline)
                Link("X APIの料金を確認", destination: URL(string: "https://docs.x.com/x-api/getting-started/pricing")!)
            }
            if !x.mutedAuthors.isEmpty { Section("非表示にしたアカウント") { ForEach(x.mutedAuthors, id: \.self) { username in Button("@\(username) の非表示を解除") { x.unmute(username) } } } }
        }.navigationTitle("X連携").navigationBarTitleDisplayMode(.inline)
            .onAppear { keys = x.credentials }
            .alert("X連携", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
            .confirmationDialog("この端末のX認証情報と検索キャッシュを削除します", isPresented: $remove) { Button("連携を解除", role: .destructive) { do { try x.disconnect(); keys = XCredentials() } catch { message = error.localizedDescription } } }
    }
}
struct XFeedView: View {
    @EnvironmentObject var x: XStore
    @State private var safari: BrowserLink?
    var body: some View {
        List {
            Section {
                Text("Xで見つける、AIの動き").font(.title3.bold())
                Text("ニュース記事とは別に、X上の公開投稿だけを表示します。投稿者名と原文を確認できます。").font(.subheadline).foregroundStyle(.secondary)
                TextField("検索条件", text: $x.query, axis: .vertical).lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(x.loading)
                Button { Task { await x.refresh() } } label: { Label(x.loading ? "取得中…" : "Xの投稿を取得（最大10件）", systemImage: "arrow.clockwise") }.disabled(x.loading || !x.credentials.canRead)
                Text("更新操作時のみX APIを使用します。利用料金は設定画面から確認できます。").font(.caption).foregroundStyle(.secondary)
            }
            if !x.credentials.canRead { Section { NavigationLink { XSettingsView() } label: { Label("XのAPIキーを設定する", systemImage: "key") }; Text("APIキーがなくても、今日のニュースと投稿案は利用できます。").font(.caption).foregroundStyle(.secondary) } }
            if let message = x.message { Section { Text(message).font(.subheadline).foregroundStyle(.secondary) } }
            if let updated = x.fetchedAt {
                Section { Text("取得日時 \(DateFormat.localStamp(updated)) · 自動更新なし").font(.caption).foregroundStyle(.secondary) }
                if Date().timeIntervalSince(updated) < 86400 {
                    ForEach(x.posts.filter { !x.mutedAuthors.contains($0.username) }) { post in
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Image(systemName: "person.crop.circle").font(.title2); VStack(alignment: .leading) { Text(post.name).font(.headline); Text("@\(post.username) · \(DateFormat.time(post.createdAt))").font(.caption).foregroundStyle(.secondary) } }
                                Text(post.text).font(.body).lineSpacing(5).textSelection(.enabled)
                                if let url = post.url { Button("Xで原文を確認") { safari = BrowserLink(url: url) }.frame(minHeight: 44) }
                                Menu("投稿の表示・報告") {
                                    Button("@\(post.username) の投稿を非表示") { x.mute(post.username) }
                                    if let url = post.url { Button("Xで開いて報告する") { safari = BrowserLink(url: url) } }
                                }.font(.caption).frame(minHeight: 44)
                            }.padding(.vertical, 6)
                        }
                    }
                } else { Section { Text("取得から24時間が経過しました。更新して現在公開されている投稿を確認してください。") } }
            }
        }.listStyle(.insetGrouped).navigationTitle("Xの情報").sheet(item: $safari) { SafariView(url: $0.url) }
    }
}
struct DraftsView: View {
    @EnvironmentObject var store: DigestStore
    @State private var selected: PostDraft?
    @State private var refreshID = UUID()
    var body: some View {
        Group {
            if let digest = store.digest {
                let drafts = DraftFactory.make(digest)
                List {
                    Section {
                        Text("AIニュースの投稿案").font(.title3.bold())
                        Text("\(digest.date)の取得済み記事から\(drafts.count)案。選んで編集し、内容と出典を確認してから投稿できます。").font(.subheadline).foregroundStyle(.secondary)
                        Text("案の作成と編集は通信不要です。記事数が少ない日は同じ記事の別案を含みます。").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(drafts) { draft in
                        Button { selected = draft } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text(draft.title).font(.headline).lineLimit(2); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                Text(store.database?.draftState(draft.id)?.text ?? draft.text).font(.subheadline).lineLimit(4).foregroundStyle(.secondary)
                                HStack { Text(draft.aiGenerated ? "AI生成の下書き" : "配信済み要約から構成"); Spacer(); Text(status(draft.id)) }.font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 10).foregroundStyle(.primary)
                        }.buttonStyle(.plain).accessibilityIdentifier("draftRow")
                    }
                }.id(refreshID).listStyle(.insetGrouped)
            } else { EmptyPanel(icon: "square.and.pencil", title: "記事を取得すると投稿案が届きます", message: "「今日」タブでダイジェストを読み込んでください。") }
        }.navigationTitle("投稿案").sheet(item: $selected, onDismiss: { refreshID = UUID() }) { draft in NavigationStack { PostEditor(draft: draft) } }
    }
    private func status(_ id: String) -> String { switch store.database?.draftState(id)?.status { case "posted": return "投稿済み"; case "sending", "unknown": return "結果確認が必要"; default: return "編集する" } }
}
struct PostEditor: View {
    @EnvironmentObject var store: DigestStore
    @EnvironmentObject var x: XStore
    @Environment(\.dismiss) private var dismiss
    let draft: PostDraft
    @State private var text = ""
    @State private var status = "draft"
    @State private var url: String?
    @State private var sending = false
    @State private var confirm = false
    @State private var message: String?
    @State private var reset = false
    @State private var restore = false
    @State private var safari: BrowserLink?
    var locked: Bool { sending || ["posted", "sending", "unknown"].contains(status) }
    var body: some View {
        Form {
            Section("投稿文") {
                TextEditor(text: $text).frame(minHeight: 240).disabled(locked).accessibilityIdentifier("postText")
                Text("\(XText.weight(text)) / 280 カウント（目安）").font(.caption.monospacedDigit()).foregroundStyle(XText.weight(text) > 280 ? .red : .secondary)
                Text("日本語・絵文字は通常2、URLは23カウントです。投稿時にX側でも検証されます。").font(.caption).foregroundStyle(.secondary)
                Button("元の投稿案に戻す") { restore = true }.disabled(locked)
            }
            Section("参照した記事") { ForEach(draft.sourceURLs, id: \.self) { source in if let url = WebURL.parse(source) { Button(url.host ?? "出典を確認") { safari = BrowserLink(url: url) } } }; Text("\(draft.aiGenerated ? "AI生成の要約" : "配信済みの要約・説明文")をもとにした案です。事実・日時・出典を確認し、ご自身の表現に編集してください。").font(.caption).foregroundStyle(.secondary) }
            Section {
                if let account = x.account { Label("投稿先 @\(account.username)", systemImage: "person.crop.circle.badge.checkmark") }
                else if x.credentials.canPost { Button("投稿先アカウントを確認") { Task { await x.verifyAccount() } }.disabled(x.loading) }
                else { NavigationLink { XSettingsView() } label: { Label("X連携を設定", systemImage: "key") } }
                if let value = x.message { Text(value).font(.caption).foregroundStyle(.secondary) }
                if status == "posted" { Label("投稿しました", systemImage: "checkmark.circle.fill").foregroundStyle(.green); if let url = url.flatMap(WebURL.parse) { Link("Xで投稿を見る", destination: url) } }
                else if ["sending", "unknown"].contains(status) {
                    Text("投稿結果の確認が必要です。Xのプロフィールを確認し、投稿されていない場合のみ再編集してください。").font(.subheadline)
                    if let account = x.account, let url = URL(string: "https://x.com/\(account.username)") { Link("Xのプロフィールを確認", destination: url) }
                    Button("未投稿を確認して再編集") { reset = true }.disabled(sending)
                } else {
                    Button { confirm = true } label: { Label("Xに投稿する", systemImage: "paperplane.fill").frame(minHeight: 44) }.disabled(!x.credentials.canPost || x.account == nil || x.loading || sending || XText.weight(text) > 280 || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.database == nil).accessibilityIdentifier("publishToX")
                }
                ShareLink(item: text) { Label("共有シートで渡す", systemImage: "square.and.arrow.up") }
                if sending { ProgressView("送信中…") }
            }
        }.navigationTitle("投稿案を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存して閉じる") { if save() { dismiss() } }.disabled(sending) } }
            .interactiveDismissDisabled(sending)
            .onAppear { if let state = store.database?.draftState(draft.id) { text = state.text; status = state.status; url = state.url } else { text = draft.text } }
            .onChange(of: text) { _ in if !locked { _ = save() } }
            .confirmationDialog("@\(x.account?.username ?? "") のXアカウントに、この内容で投稿します", isPresented: $confirm, titleVisibility: .visible) { Button("この内容をXに投稿") { Task { await publish() } }; Button("キャンセル", role: .cancel) {} }
            .confirmationDialog("Xで未投稿であることを確認しましたか？", isPresented: $reset, titleVisibility: .visible) { Button("未投稿を確認したので編集に戻る") { status = "draft"; _ = save() } }
            .confirmationDialog("編集内容を元の投稿案に戻しますか？", isPresented: $restore, titleVisibility: .visible) { Button("元の投稿案に戻す", role: .destructive) { text = draft.text; _ = save() }; Button("キャンセル", role: .cancel) {} }
            .alert("投稿", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
            .sheet(item: $safari) { SafariView(url: $0.url) }
    }
    @discardableResult private func save() -> Bool {
        guard let db = store.database else { message = "端末に保存できないため投稿できません。"; return false }
        do { try db.saveDraft(draft.id, text: text, status: status, url: url); return true } catch { message = error.localizedDescription; return false }
    }
    private func publish() async {
        guard !locked, x.account != nil, x.credentials.canPost else { return }
        let outgoing = text, credentials = x.credentials
        status = "sending"; guard save() else { status = "draft"; return }
        sending = true; defer { sending = false }
        do {
            let result = try await x.service.post(text: outgoing, credentials: credentials)
            status = "posted"; url = result.absoluteString
            if !save() { message = "Xへの投稿は成功しましたが、端末への結果保存に失敗しました。投稿を再送しないでください。\n\(result.absoluteString)" }
        } catch {
            if case XError.unknownOutcome = error { status = "unknown" } else { status = "draft" }
            _ = save(); message = error.localizedDescription
        }
    }
}
