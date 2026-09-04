import Foundation

// ダイジェストの取得と、オフライン時のための前回分キャッシュ。
// viewingDate == nil のときは最新を表示し、日付を指定すると過去分(data/<date>.json)を表示する。
@MainActor
final class DigestStore: ObservableObject {
    @Published var digest: Digest?
    @Published var isLoading = false
    @Published var notice: String?
    @Published var availableDates: [String] = [] // 新しい順
    @Published var viewingDate: String? // nil = 最新

    private static let baseURL = URL(string: "https://takuya-ops.github.io/ai-morning-digest/data/")!
    private static let cacheKey = "cachedDigestJSON"

    var isViewingLatest: Bool { viewingDate == nil }

    // 現在表示中の日付から見て1日古い/新しい日付(availableDatesは新しい順)
    var previousDate: String? { neighbor(offset: +1) }
    var nextDate: String? { neighbor(offset: -1) }

    private func neighbor(offset: Int) -> String? {
        guard let current = digest?.date,
              let idx = availableDates.firstIndex(of: current) else { return nil }
        let target = idx + offset
        guard availableDates.indices.contains(target) else { return nil }
        return availableDates[target]
    }

    func reload() async {
        await load(date: viewingDate)
    }

    func showLatest() async {
        if await load(date: nil) { viewingDate = nil }
    }

    func show(date: String) async {
        // 最新の日付が選ばれたら「最新モード」に戻す(以後の更新で自動的に新しい日に切り替わる)
        if date == availableDates.first {
            await showLatest()
        } else if await load(date: date) {
            viewingDate = date
        }
    }

    func showPrevious() async {
        if let d = previousDate { await show(date: d) }
    }

    func showNext() async {
        if let d = nextDate { await show(date: d) }
    }

    func loadIndex() async {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("index.json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let index = try? JSONDecoder().decode(DigestIndex.self, from: data) else { return }
        availableDates = index.dates
    }

    // 成功したら true。失敗時は表示中の内容を維持して notice で知らせる。
    @discardableResult
    private func load(date: String?) async -> Bool {
        guard !isLoading else { return false } // 起動時の.taskとscenePhase変化による二重フェッチを防ぐ
        isLoading = true
        defer { isLoading = false }
        let file = date.map { "\($0).json" } ?? "latest.json"
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(file))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            digest = try JSONDecoder().decode(Digest.self, from: data)
            notice = nil
            if date == nil {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            return true
        } catch {
            if digest != nil {
                // 表示中の内容は保持しつつ、取得に失敗したことは知らせる
                notice = date == nil
                    ? "更新に失敗しました(前回取得分を表示中)"
                    : "\(date ?? "")のデータを取得できませんでした"
                return false
            }
            if let cached = UserDefaults.standard.data(forKey: Self.cacheKey),
               let d = try? JSONDecoder().decode(Digest.self, from: cached) {
                digest = d
                notice = "オフライン表示中(前回取得分)"
            } else {
                notice = "読み込みに失敗しました。通信環境をご確認のうえ、下に引っ張って更新してください。"
            }
            return false
        }
    }
}
