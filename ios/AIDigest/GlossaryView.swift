import SwiftUI
struct GlossaryTerm: Identifiable {
    let id: String; let aliases: [String]; let definition: String; let source: String
    static let all = [
        GlossaryTerm(id: "大規模言語モデル（LLM）", aliases: ["LLM", "大規模言語モデル"], definition: "大量のテキストなどから言語のパターンを学習し、文章の生成や要約を行うモデルです。出力は常に正しいとは限りません。", source: "https://developers.google.com/machine-learning/resources/intro-llms"),
        GlossaryTerm(id: "検索拡張生成（RAG）", aliases: ["RAG", "検索拡張"], definition: "質問に関連する資料を検索し、その内容をモデルへ渡して回答を生成する仕組みです。検索した資料の品質が回答に影響します。", source: "https://cloud.google.com/use-cases/retrieval-augmented-generation"),
        GlossaryTerm(id: "テキスト読み上げ（TTS）", aliases: ["TTS", "読み上げ", "音声合成"], definition: "文章から音声を生成する機能です。このアプリでは、運営側で作った音声を配信します。", source: "https://ai.google.dev/gemini-api/docs/speech-generation"),
        GlossaryTerm(id: "トークン", aliases: ["token", "トークン"], definition: "モデルが文章を処理する際の単位です。単語や文字と一対一に対応するとは限らず、モデルや言語で分割方法が異なります。", source: "https://ai.google.dev/gemini-api/docs/tokens"),
        GlossaryTerm(id: "コンテキストウィンドウ", aliases: ["コンテキスト", "context window"], definition: "モデルが一度に扱える情報量の範囲です。入力と出力に使える量や制約はモデルごとに異なります。", source: "https://ai.google.dev/gemini-api/docs/long-context")
    ]
}
struct GlossaryView: View {
    let text: String?
    private var terms: [GlossaryTerm] { guard let text else { return GlossaryTerm.all }; let normalized = SearchIndex.normalize(text); return GlossaryTerm.all.filter { term in term.aliases.contains { normalized.contains(SearchIndex.normalize($0)) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !terms.isEmpty {
                Text("AI用語集").font(.headline)
                ForEach(terms) { term in DisclosureGroup(term.id) { VStack(alignment: .leading, spacing: 10) { Text(term.definition).fixedSize(horizontal: false, vertical: true); Link("公式資料", destination: URL(string: term.source)!); Text("定義の確認: 2026-10-04").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10) }.padding(.vertical, 6) }
            }
        }.padding(text == nil ? 20 : 0).navigationTitle(text == nil ? "AI用語集" : "記事")
    }
}
