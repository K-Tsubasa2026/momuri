import Foundation

/// 공유할 때 서버에 올리는 루틴 설정 (기록은 빼고 설정만)
struct RoutineDefinition: Codable, Equatable {
    var name: String
    var kind: String
    var category: String
    var intervalValue: Int
    var intervalUnit: String
    var reminderHour: Int
    var reminderMinute: Int
    var reminderTimes: [Int]
    var remindDaysBefore: Int
    var parts: [String]
    var weekendOnly: Bool
    var targetValue: Double
    var targetUnit: String
    var windowStart: Int
    var windowEnd: Int
    var goalMinutes: Int
    var eventDate: Date
    var allDay: Bool
    var location: String
    var remindOffsets: [Int]
    // 나중에 추가한 공부 설정 (예전 공유에는 없을 수 있음)
    var examDate: Date?
    var studyGoal: Double?
    var studyUnit: String?
    var studyTogether: Bool?
    var studyStart: Int?
    var studyEnd: Int?

    init(_ r: Routine) {
        name = r.name
        kind = r.kindRaw
        category = r.categoryRaw
        intervalValue = r.intervalValue
        intervalUnit = r.intervalUnitRaw
        reminderHour = r.reminderHour
        reminderMinute = r.reminderMinute
        reminderTimes = r.reminderTimes
        remindDaysBefore = r.remindDaysBefore
        parts = r.parts
        weekendOnly = r.weekendOnly
        targetValue = r.targetValue
        targetUnit = r.targetUnit
        windowStart = r.windowStart
        windowEnd = r.windowEnd
        goalMinutes = r.goalMinutes
        eventDate = Date(timeIntervalSince1970: r.eventDate.timeIntervalSince1970.rounded(.down))
        allDay = r.allDay
        location = r.location
        remindOffsets = r.remindOffsets
        examDate = r.examDate.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
        studyGoal = r.studyGoal
        studyUnit = r.studyUnit
        studyTogether = r.studyTogether
        studyStart = r.studyStart
        studyEnd = r.studyEnd
    }

    func apply(to r: Routine) {
        r.name = name
        r.kindRaw = kind
        r.categoryRaw = category
        r.intervalValue = intervalValue
        r.intervalUnitRaw = intervalUnit
        r.reminderHour = reminderHour
        r.reminderMinute = reminderMinute
        r.reminderTimes = reminderTimes
        r.remindDaysBefore = remindDaysBefore
        r.parts = parts
        r.weekendOnly = weekendOnly
        r.targetValue = targetValue
        r.targetUnit = targetUnit
        r.windowStart = windowStart
        r.windowEnd = windowEnd
        r.goalMinutes = goalMinutes
        r.eventDate = eventDate
        r.allDay = allDay
        r.location = location
        r.remindOffsets = remindOffsets
        r.examDate = examDate
        r.studyGoal = studyGoal ?? 30
        r.studyUnit = studyUnit ?? "문제"
        r.studyTogether = studyTogether ?? false
        r.studyStart = studyStart ?? 21 * 60
        r.studyEnd = studyEnd ?? 22 * 60
    }
}

struct ShareMember: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let days: [String]
    /// 날짜별 진행량 (공부 문제 수 등)
    var progress: [String: Double]?
    /// 지금 공부 중이면 시작 시각
    var studyingSince: Date?

    func progress(on day: Date) -> Double {
        progress?[ShareClient.dayKey(day)] ?? 0
    }
}

struct Cheer: Codable, Equatable {
    let id: Int
    let fromId: String
    let fromName: String
}

struct ShareView: Codable {
    let id: String
    let code: String
    let ownerId: String
    let routine: RoutineDefinition
    let members: [ShareMember]
    var cheers: [Cheer]?
}

extension ShareMember {
    /// 잔디 칸 (서로 보기용)
    func cells(days count: Int, today: Date = .now) -> [GrassCell] {
        let set = Set(days)
        let cal = Calendar.current
        return cal.days(endingAt: today, count: count).map { day in
            if set.contains(ShareClient.dayKey(day)) { return .done }
            return cal.isDate(day, inSameDayAs: today) ? .today : .empty
        }
    }
}
