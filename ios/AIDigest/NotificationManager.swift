import Foundation
import UserNotifications

// 毎朝のローカル通知(サーバー不要・端末内で完結)
enum NotificationManager {
    static let identifier = "morning-digest"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifyEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notifyEnabled") }
    }
    static var hour: Int {
        UserDefaults.standard.object(forKey: "notifyHour") as? Int ?? 6
    }
    static var minute: Int {
        UserDefaults.standard.object(forKey: "notifyMinute") as? Int ?? 30
    }

    // 現在の設定に合わせて通知を組み直す。権限がなければ要求し、拒否されたらOFFに戻す。
    @discardableResult
    static func reschedule() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return false }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted {
                enabled = false
                return false
            }
        case .denied:
            enabled = false
            return false
        default:
            break
        }

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = "🌅 生成AIモーニングダイジェスト"
        content.body = "今朝の生成AIニュース TOP10が届いています"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }
}
