import AppIntents

struct PlayMorningBriefing: AppIntent {
    static var title: LocalizedStringResource = "今日のAIニュースを開く"
    static var description = IntentDescription("AIダイジェストを開いて、今日のニュースを表示します。")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.open(URL(string: "aidigest://today")!)
        return .result()
    }
}
struct DigestShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayMorningBriefing(), phrases: ["\(.applicationName)で今日のAIニュースを開く", "\(.applicationName)を読む"], shortTitle: "AIニュースを開く", systemImageName: "newspaper")
    }
}
