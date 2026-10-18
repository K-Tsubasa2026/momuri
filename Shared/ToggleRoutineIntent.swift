import AppIntents
import SwiftData

/// 위젯에서 바로 체크하기 위한 인텐트.
/// LiveActivityIntent 라서 앱 프로세스에서 실행된다 (알람 재예약·공유 업로드가 함께 돈다).
struct ToggleRoutineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "루틴 체크"

    @Parameter(title: "Routine ID")
    var routineID: String

    init() {}

    init(routineID: String) {
        self.routineID = routineID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = SharedStore.container.mainContext
        let routines = try context.fetch(FetchDescriptor<Routine>())
        if let routine = routines.first(where: { $0.id.uuidString == routineID }), routine.isSimpleCheck {
            RoutineActions.toggle(routine, on: .now, in: context)
        }
        return .result()
    }
}
