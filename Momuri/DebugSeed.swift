#if DEBUG
import Foundation
import SwiftData

/// 실행 인자 -seed(Xcode 스킴) 또는 환경변수 MOMURI_SEED=1(simctl)로 띄우면 샘플 루틴과 지난 기록을 넣는다 (시뮬레이터 확인용)
enum DebugFlag {
    /// 실행 인자 -name 또는 환경변수 MOMURI_NAME=1
    static func isOn(_ name: String) -> Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("-" + name) || info.environment["MOMURI_" + name.uppercased()] == "1"
    }
}

enum DebugRestore {
    /// 환경변수 MOMURI_RESTORE=<파일 경로>: 백업 복원 시험
    @MainActor
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["MOMURI_RESTORE"],
              let data = FileManager.default.contents(atPath: path) else { return }
        let n = try? Backup.restore(data, context: SharedStore.container.mainContext)
        NSLog("momuri restore: \(n.map(String.init) ?? "failed")")
    }
}

enum DebugSeed {
    @MainActor
    static func runIfRequested() {
        guard DebugFlag.isOn("seed") else { return }
        let context = SharedStore.container.mainContext
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: RoutineLog.self)
        try? context.delete(model: Routine.self)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }

        let samples: [(String, RoutineKind, Int, IntervalUnit, Int, [Int])] = [
            ("약", .daily, 1, .day, 8, Array(1...20).filter { $0 % 6 != 0 }),
            ("러닝", .daily, 1, .day, 7, [1, 3, 6, 9, 12, 15, 19]),
            ("수염 제모", .interval, 1, .month, 11, [27]),
            ("겨드랑이 제모", .interval, 2, .month, 21, [40]),
        ]
        for (i, s) in samples.enumerated() {
            let r = Routine(name: s.0, kind: s.1, sortOrder: i)
            r.intervalValue = s.2
            r.intervalUnit = s.3
            r.reminderHour = s.4
            r.createdAt = day(60)
            r.isCritical = s.0 == "약" || s.0 == "수염 제모"
            r.weekendOnly = s.0 == "수염 제모"
            r.category = s.0 == "약" ? .medicine : s.0 == "러닝" ? .cardio : .care
            if s.0 == "약" {
                r.reminderTimes = [8 * 60, 21 * 60]
                r.useAlarm = true
            }
            if s.0 == "러닝" {
                r.kind = .monthly
                r.targetUnit = "km"
                r.targetValue = 50
                r.autoHealth = true
            }
            context.insert(r)
            for offset in s.5 {
                let repeats = s.0 == "약" ? 2 : 1
                for _ in 0..<repeats {
                    let value: Double? = s.0 == "러닝" ? 4.5 + Double(offset % 3) : nil
                    let log = RoutineLog(date: day(offset), value: value)
                    context.insert(log)
                    log.routine = r
                }
            }
        }
        let gym = Routine(name: "헬스", kind: .weekly, sortOrder: samples.count)
        gym.category = .gym
        gym.parts = ["가슴", "등", "하체", "어깨"]
        gym.reminderHour = 19
        gym.isCritical = true
        gym.createdAt = day(60)
        context.insert(gym)
        // 이번 주(월요일 시작)부터 거슬러 올라가며 부위 기록을 넣는다
        let weekStart = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: today)!.start
        let offsetToMonday = cal.dateComponents([.day], from: weekStart, to: today).day!
        let history: [(Int, String)] = [
            (offsetToMonday, "등"),
            (offsetToMonday + 1, "어깨"), (offsetToMonday + 3, "하체"), (offsetToMonday + 5, "등"), (offsetToMonday + 6, "가슴"),
            (offsetToMonday + 9, "가슴"), (offsetToMonday + 11, "등"), (offsetToMonday + 13, "하체"),
            (offsetToMonday + 15, "가슴"), (offsetToMonday + 17, "어깨"), (offsetToMonday + 18, "등"), (offsetToMonday + 20, "하체"),
        ]
        let plans: [String: [(String, Double)]] = [
            "가슴": [("벤치프레스", 60), ("인클라인 덤벨프레스", 20)],
            "등": [("랫풀다운", 55), ("바벨 로우", 50)],
            "하체": [("스쿼트", 80), ("레그프레스", 140)],
            "어깨": [("오버헤드 프레스", 35), ("사이드 레터럴 레이즈", 8)],
        ]
        for (offset, part) in history {
            let log = RoutineLog(date: day(offset), part: part)
            context.insert(log)
            log.routine = gym
            // 오래된 기록일수록 조금 가볍게
            let bump = Double(3 - offset / 7) * 2.5
            for (i, plan) in (plans[part] ?? []).enumerated() {
                for n in 0..<3 {
                    let set = WorkoutSet(exercise: plan.0, weight: plan.1 + bump, reps: 10 - n, order: i * 3 + n)
                    context.insert(set)
                    set.log = log
                }
            }
        }
        let meeting = Routine(name: "유진이랑 저녁", kind: .once, sortOrder: samples.count + 1)
        meeting.category = .appointment
        meeting.eventDate = cal.date(bySettingHour: 19, minute: 30, second: 0, of: cal.date(byAdding: .day, value: 2, to: today)!)!
        meeting.location = "강남역"
        meeting.showInWidget = false
        context.insert(meeting)
        let shampoo = Routine(name: "샴푸", kind: .interval, sortOrder: samples.count + 2)
        shampoo.category = .pet
        shampoo.intervalValue = 2
        shampoo.intervalUnit = .week
        shampoo.createdAt = day(30)
        context.insert(shampoo)
        let washed = RoutineLog(date: day(12))
        context.insert(washed)
        washed.routine = shampoo
        let study = Routine(name: "정보처리기사", kind: .daily, sortOrder: samples.count + 3)
        study.category = .study
        study.examDate = cal.date(byAdding: .day, value: 45, to: today)
        study.studyGoal = 30
        study.reminderHour = 22
        study.studyTogether = true
        study.createdAt = day(20)
        context.insert(study)
        for offset in [1, 2, 3, 5, 6, 8, 9, 10, 12] {
            let log = RoutineLog(date: day(offset), value: offset % 4 == 0 ? 20 : 30)
            context.insert(log)
            log.routine = study
        }
        let todayLog = RoutineLog(date: .now, value: 12)
        context.insert(todayLog)
        todayLog.routine = study
        RoutineActions.commit(context)
    }
}
#endif
