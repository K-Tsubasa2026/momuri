import Foundation
import SwiftData

enum SharedStore {
    static let appGroup = "group.com.rymchoi.momuri"

    /// 앱과 위젯이 같은 저장소를 쓰도록 App Group 컨테이너에 둔다
    static let container: ModelContainer = {
        let schema = Schema([Routine.self, RoutineLog.self, WorkoutSet.self])
        // App Group 권한이 없는 서명(무료 개인 계정)에서 groupContainer를 쓰면 SwiftData가 예외 대신 앱을 멈춘다.
        // 그래서 컨테이너가 실제로 있는지 먼저 확인한다.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
           let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))) {
            return container
        }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, groupContainer: .none))
    }()
}
