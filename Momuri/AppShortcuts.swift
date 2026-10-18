import AppIntents

/// Siri에 바로 말할 수 있는 문장들
struct MomuriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogRoutineIntent(),
            phrases: [
                "\(.applicationName)에 \(\.$routine) 기록",
                "\(.applicationName)에서 \(\.$routine) 했어",
                "\(.applicationName) \(\.$routine) 완료",
            ],
            shortTitle: "루틴 기록",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "\(.applicationName) 오늘 남은 일",
                "\(.applicationName)에서 오늘 할 일 알려줘",
            ],
            shortTitle: "오늘 남은 일",
            systemImageName: "list.bullet"
        )
    }
}
