import Foundation
import HealthKit
import SwiftData

/// 건강 앱의 러닝 운동을 "건강 앱에서 자동 기록"이 켜진 러닝 루틴으로 가져온다
enum HealthSync {
    static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning)])
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func sync(context: ModelContext) async {
        let routines = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.autoHealth && $0.kind == .monthly }
        guard isAvailable, !routines.isEmpty else { return }
        await requestAuthorization()

        // 이번 달과 지난달만 본다
        let cal = Calendar.current
        guard let thisMonth = cal.dateInterval(of: .month, for: .now)?.start,
              let since = cal.date(byAdding: .month, value: -1, to: thisMonth) else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts: [HKWorkout]
        do {
            workouts = try await descriptor.result(for: store)
        } catch {
            NSLog("HealthSync: query failed \(error)")
            return
        }
        guard !workouts.isEmpty else { return }

        var changed = false
        for routine in routines {
            let known = Set((routine.logs ?? []).compactMap(\.externalID)).union(RoutineActions.dismissedExternalIDs)
            for workout in workouts where !known.contains(workout.uuid.uuidString) && workout.startDate >= routine.startDay {
                let km = kilometers(of: workout)
                let log = RoutineLog(date: workout.startDate, value: routine.targetUnit == "km" ? km : nil)
                log.externalID = workout.uuid.uuidString
                context.insert(log)
                routine.logs?.append(log)
                changed = true
            }
        }
        if changed { RoutineActions.commit(context) }
    }

    private static func kilometers(of workout: HKWorkout) -> Double {
        let quantity = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
        let km = quantity?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
        return (km * 10).rounded() / 10
    }
}

#if DEBUG
/// 실행 인자 -seedHealth 또는 환경변수 MOMURI_SEEDHEALTH=1: 시뮬레이터 건강 앱에 샘플 러닝 2개를 넣는다
enum HealthSeed {
    static func runIfRequested() async {
        guard DebugFlag.isOn("seedHealth") else { return }
        guard HealthSync.isAvailable else { return }
        let distance = HKQuantityType(.distanceWalkingRunning)
        try? await HealthSync.store.requestAuthorization(toShare: [HKObjectType.workoutType(), distance],
                                                         read: [HKObjectType.workoutType(), distance])
        let cal = Calendar.current
        for (daysAgo, km, minutes) in [(0, 5.3, 31.0), (2, 7.1, 42.0)] {
            guard let start = cal.date(byAdding: .day, value: -daysAgo, to: .now.addingTimeInterval(-3 * 3600)) else { continue }
            let end = start.addingTimeInterval(minutes * 60)
            let config = HKWorkoutConfiguration()
            config.activityType = .running
            let builder = HKWorkoutBuilder(healthStore: HealthSync.store, configuration: config, device: nil)
            do {
                try await builder.beginCollection(at: start)
                let sample = HKQuantitySample(type: distance, quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km), start: start, end: end)
                try await builder.addSamples([sample])
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
            } catch {
                NSLog("HealthSeed failed: \(error)")
            }
        }
    }
}
#endif
