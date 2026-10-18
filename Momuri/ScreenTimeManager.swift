import DeviceActivity
import FamilyControls
import Foundation
import SwiftData
import SwiftUI

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

extension DeviceActivityName {
    static let daily = Self("daily")
}

/// 폰 사용 루틴: 권한 요청, 하루 감시 시작, 지난날 "목표 지킴" 자동 기록
@MainActor
enum ScreenTimeManager {
    static var selection: FamilyActivitySelection {
        get {
            guard let data = ScreenTimeShared.selectionData,
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return FamilyActivitySelection() }
            return value
        }
        set { ScreenTimeShared.selectionData = try? JSONEncoder().encode(newValue) }
    }

    static var isAuthorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return true
        } catch {
            NSLog("ScreenTime authorization failed: \(error)")
            return false
        }
    }

    /// 매일 0시부터 고른 앱·카테고리 사용 시간이 목표의 80%·100%에 닿는지 감시한다
    static func startMonitoring(goalMinutes: Int) {
        ScreenTimeShared.goalMinutes = goalMinutes
        let selection = selection
        guard isAuthorized, !(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty) else { return }
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                              intervalEnd: DateComponents(hour: 23, minute: 59),
                                              repeats: true)
        func event(_ minutes: Int) -> DeviceActivityEvent {
            DeviceActivityEvent(applications: selection.applicationTokens,
                                categories: selection.categoryTokens,
                                webDomains: selection.webDomainTokens,
                                threshold: DateComponents(minute: minutes))
        }
        let center = DeviceActivityCenter()
        center.stopMonitoring([.daily])
        do {
            try center.startMonitoring(.daily, during: schedule, events: [
                DeviceActivityEvent.Name("warning"): event(goalMinutes * 8 / 10),
                DeviceActivityEvent.Name("limit"): event(goalMinutes),
            ])
            if ScreenTimeShared.monitoringSince == nil { ScreenTimeShared.monitoringSince = Calendar.current.startOfDay(for: .now) }
        } catch {
            NSLog("ScreenTime monitoring failed: \(error)")
        }
    }

    static func stopMonitoring() {
        DeviceActivityCenter().stopMonitoring([.daily])
        ScreenTimeShared.monitoringSince = nil
    }

    /// 감시 중이었고 초과하지 않은 지난날을 "지킴"으로 기록한다
    static func syncLogs(context: ModelContext) {
        guard let since = ScreenTimeShared.monitoringSince else { return }
        let routines = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.category == .screen }
        let cal = Calendar.current
        var changed = false
        for routine in routines {
            for offset in 1...14 {
                guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)),
                      day >= max(since, routine.startDay),
                      !routine.isDone(on: day),
                      ScreenTimeShared.status(on: day) != .exceeded else { continue }
                let log = RoutineLog(date: day)
                log.externalID = ScreenTimeShared.key(day)
                context.insert(log)
                routine.logs?.append(log)
                changed = true
            }
        }
        if changed { RoutineActions.commit(context) }
    }
}
