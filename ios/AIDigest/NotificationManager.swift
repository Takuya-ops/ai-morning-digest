import Foundation
import UserNotifications

@MainActor
enum NotificationManager {
    private static var revision = 0
    private static var pending: Task<Bool, Never>?
    static func requests(now: Date = Date(), headline: String? = nil, calendar: Calendar = .current, defaults: UserDefaults = .standard) -> [UNNotificationRequest] {
        let hour = defaults.object(forKey: "notifyHour") as? Int ?? 7
        let minute = defaults.object(forKey: "notifyMinute") as? Int ?? 0
        let weekdays = defaults.bool(forKey: "notifyWeekdays")
        let autoplay = defaults.bool(forKey: "notifyAutoplay")
        return (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), date > now else { return nil }
            if weekdays && [1, 7].contains(calendar.component(.weekday, from: date)) { return nil }
            let content = UNMutableNotificationContent()
            content.title = "AIモーニングダイジェスト"
            content.body = offset == 0 ? (headline ?? "朝のAIニュースを確認する時間です") : "朝のAIニュースを確認する時間です"
            content.sound = .default
            content.userInfo = ["url": "aidigest://today?autoplay=\(autoplay ? 1 : 0)"]
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return UNNotificationRequest(identifier: "morning-digest-\(offset)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
    }
    @discardableResult
    static func reschedule(headline: String? = nil, requestPermission: Bool = false) async -> Bool {
        revision += 1; let current = revision
        let previous = pending
        let task = Task { @MainActor in
            _ = await previous?.value
            guard current == revision else { return true }
            return await performSchedule(headline: headline, requestPermission: requestPermission, current: current)
        }
        pending = task
        return await task.value
    }
    private static func performSchedule(headline: String?, requestPermission: Bool, current: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let oldIDs = ["morning-digest"] + (0..<30).map { "morning-digest-\($0)" }
        guard UserDefaults.standard.bool(forKey: "notifyEnabled") else { center.removePendingNotificationRequests(withIdentifiers: oldIDs); return true }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, requestPermission {
            _ = try? await center.requestAuthorization(options: [.alert, .sound]); settings = await center.notificationSettings()
        }
        guard current == revision else { return false }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        for request in requests(headline: headline) {
            guard current == revision else { return false }
            do { try await center.add(request) } catch { return false }
        }
        return true
    }
    static func testNotification() async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw NotificationError.denied }
        let content = UNMutableNotificationContent(); content.title = "AIダイジェスト · 通知テスト"; content.body = "タップすると今日のニュースを開きます。"; content.sound = .default
        content.userInfo = ["url": "aidigest://today?autoplay=\(UserDefaults.standard.bool(forKey: "notifyAutoplay") ? 1 : 0)"]
        try await center.add(UNNotificationRequest(identifier: "digest-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)))
    }
    enum NotificationError: LocalizedError { case denied; var errorDescription: String? { "iOSの設定で通知を許可してください。" } }
}
