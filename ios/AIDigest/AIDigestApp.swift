import SwiftUI

@main
struct AIDigestApp: App {
    @StateObject private var store = DigestStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Color(red: 0.71, green: 0.33, blue: 0.18)) // サイトと同じアクセント色
                .task {
                    await store.load()
                    await syncNotifications()
                }
        }
    }

    // 初回起動時は通知の許可を求めて毎朝6:30に設定。
    // 2回目以降も設定と権限状態を突き合わせて再スケジュールする(冪等。
    // 許可ダイアログ表示中にアプリが落ちた等で不整合になっても次回起動で復旧する)
    private func syncNotifications() async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didAskNotify") {
            defaults.set(true, forKey: "didAskNotify")
            NotificationManager.enabled = true
        }
        await NotificationManager.reschedule()
    }
}
