import SwiftUI
import UserNotifications
import BackgroundTasks

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab = 0
    @Published var articleID: String?
    @Published var autoplay = false
    func open(_ url: URL) {
        guard url.scheme == "aidigest" else { return }
        tab = 0
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        articleID = query.first { $0.name == "id" }?.value
        autoplay = query.first { $0.name == "autoplay" }?.value == "1"
    }
}
final class DigestAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.takuyaops.aidigest.refresh", using: nil) { task in
            Task { @MainActor in
                let work = Task { await DigestStore().refresh() }
                task.expirationHandler = { work.cancel() }
                let success = await work.value
                task.setTaskCompleted(success: success); Self.scheduleRefresh()
            }
        }
        return true
    }
    static func scheduleRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.takuyaops.aidigest.refresh")
        let request = BGAppRefreshTaskRequest(identifier: "com.takuyaops.aidigest.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: value) else { return }
        AppRouter.shared.open(url)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
@main
struct AIDigestApp: App {
    @UIApplicationDelegateAdaptor(DigestAppDelegate.self) var delegate
    @StateObject private var store = DigestStore()
    @StateObject private var player = BriefingPlayer()
    @StateObject private var router = AppRouter.shared
    @StateObject private var x = XStore()
    @AppStorage("theme") private var theme = "system"
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).environmentObject(player).environmentObject(router).environmentObject(x)
                .tint(Color.accentColor)
                .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
                .onOpenURL { router.open($0) }
                .task {
                    player.onFinishedArticle = { store.markRead($0) }
                    player.onFinishedBriefing = { store.completeBriefing(date: $0) }
                    await store.refresh()
                    DigestAppDelegate.scheduleRefresh()
                }
                .onChange(of: phase) { value in
                    if value == .active { store.reloadLocalState(); Task { await store.refresh() } }
                    if value == .background { DigestAppDelegate.scheduleRefresh() }
                }
        }
    }
}
