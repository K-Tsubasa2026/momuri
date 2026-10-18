import AppIntents
import SwiftData

/// 알람 화면의 "완료" 버튼: 앱을 열지 않고 그 루틴을 기록한다
struct CompleteFromAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "알람에서 완료"
    static let isDiscoverable = false

    @Parameter(title: "루틴 ID")
    var routineID: String

    init() {}

    init(routineID: String) {
        self.routineID = routineID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = SharedStore.container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        if let routine = all.first(where: { $0.id.uuidString == routineID }), !routine.isDone(on: .now) {
            RoutineActions.quickLog(routine, in: context)
        }
        return .result()
    }
}
