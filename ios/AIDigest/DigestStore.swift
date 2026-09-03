import Foundation

// ダイジェストの取得と、オフライン時のための前回分キャッシュ
@MainActor
final class DigestStore: ObservableObject {
    @Published var digest: Digest?
    @Published var isLoading = false
    @Published var notice: String?

    private static let endpoint = URL(string: "https://takuya-ops.github.io/ai-morning-digest/data/latest.json")!
    private static let cacheKey = "cachedDigestJSON"

    func load() async {
        guard !isLoading else { return } // 起動時の.taskとscenePhase変化による二重フェッチを防ぐ
        isLoading = true
        defer { isLoading = false }
        var request = URLRequest(url: Self.endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            digest = try JSONDecoder().decode(Digest.self, from: data)
            notice = nil
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            if digest != nil {
                // 表示中の内容は保持しつつ、更新に失敗したことは知らせる
                notice = "更新に失敗しました(前回取得分を表示中)"
                return
            }
            if let cached = UserDefaults.standard.data(forKey: Self.cacheKey),
               let d = try? JSONDecoder().decode(Digest.self, from: cached) {
                digest = d
                notice = "オフライン表示中(前回取得分)"
            } else {
                notice = "読み込みに失敗しました。通信環境をご確認のうえ、下に引っ張って更新してください。"
            }
        }
    }
}
