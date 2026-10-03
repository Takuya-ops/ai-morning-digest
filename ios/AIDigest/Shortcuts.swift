import AppIntents

struct PlayMorningBriefing: AppIntent {
    static var title: LocalizedStringResource = "今日のAIニュースを再生"
    static var description = IntentDescription("AIダイジェストを開いて、取得済みのブリーフィングを読み上げます。")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.open(URL(string: "aidigest://today?autoplay=1")!)
        return .result()
    }
}
struct DigestShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayMorningBriefing(), phrases: ["\(.applicationName)で今日のAIニュースを再生", "\(.applicationName)を聴く"], shortTitle: "AIニュースを再生", systemImageName: "play.circle")
    }
}
