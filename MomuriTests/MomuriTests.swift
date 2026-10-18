import SwiftData
import XCTest
@testable import Momuri

/// 일정·기록 계산 로직 테스트. 메모리 저장소만 쓴다.
@MainActor
final class ScheduleTests: XCTestCase {
    var context: ModelContext!
    let cal = Calendar.current

    override func setUp() async throws {
        let schema = Schema([Routine.self, RoutineLog.self, WorkoutSet.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func routine(_ kind: RoutineKind, _ category: RoutineCategory = .other, created: Date) -> Routine {
        let r = Routine(name: "테스트", kind: kind)
        r.category = category
        r.createdAt = created
        context.insert(r)
        return r
    }

    @discardableResult
    func log(_ r: Routine, _ d: Date, value: Double? = nil, part: String? = nil, skipped: Bool = false) -> RoutineLog {
        let l = RoutineLog(date: d, value: value, part: part)
        l.skipped = skipped
        context.insert(l)
        r.logs?.append(l)
        return l
    }

    // MARK: 매일형

    func testMultiDoseNeedsAllDoses() {
        let r = routine(.daily, .medicine, created: date(2026, 10, 1))
        r.reminderTimes = [8 * 60, 21 * 60]
        let day = date(2026, 10, 13, 9)
        log(r, day)
        XCTAssertFalse(r.isDone(on: day))
        XCTAssertEqual(r.nextTime(on: day), 21 * 60)
        log(r, day.addingTimeInterval(3600))
        XCTAssertTrue(r.isDone(on: day))
        XCTAssertNil(r.nextTime(on: day))
    }

    func testStudyDoneByAmount() {
        let r = routine(.daily, .study, created: date(2026, 10, 1))
        r.studyGoal = 30
        let day = date(2026, 10, 13, 10)
        log(r, day, value: 20)
        XCTAssertFalse(r.isDone(on: day))
        log(r, day, value: 10)
        XCTAssertTrue(r.isDone(on: day))
    }

    // MARK: 쉬는 날

    func testSkipIsRestNotDone() {
        let r = routine(.daily, created: date(2026, 10, 1))
        let day = date(2026, 10, 13)
        log(r, day, skipped: true)
        XCTAssertFalse(r.isDone(on: day))
        XCTAssertTrue(r.isRestDay(day))
        XCTAssertTrue(r.isSettled(on: day))
        XCTAssertTrue(r.doneDays.isEmpty)
        XCTAssertEqual(r.grassCell(on: day, today: date(2026, 10, 14)), .rest)
        XCTAssertEqual(r.logCount(on: day), 0)
    }

    func testRestWeekdayLeavesListAndCompletion() {
        let r = routine(.daily, created: date(2026, 10, 1))
        r.restWeekdays = [1] // 일요일
        let sunday = date(2026, 10, 11)
        XCTAssertFalse(r.appears(on: sunday, today: date(2026, 10, 13)))
        XCTAssertNil([r].completion(on: sunday, today: date(2026, 10, 13)))
        XCTAssertNotNil([r].completion(on: date(2026, 10, 12), today: date(2026, 10, 13)))
    }

    func testMonthBoundaryMidnight() {
        let r = routine(.monthly, .cardio, created: date(2026, 9, 1))
        log(r, date(2026, 11, 1), value: 7) // 11월 1일 자정 기록은 10월에 들어가면 안 됨
        XCTAssertEqual(r.monthTotal(of: date(2026, 10, 20)), 0)
        XCTAssertEqual(r.monthTotal(of: date(2026, 11, 2)), 7)
    }

    func testSkippedLogsDontCountInTotals() {
        let r = routine(.monthly, .cardio, created: date(2026, 10, 1))
        log(r, date(2026, 10, 5), value: 5)
        log(r, date(2026, 10, 6), skipped: true)
        XCTAssertEqual(r.monthTotal(of: date(2026, 10, 13)), 5)
    }

    // MARK: 주기형

    func testWeekendOnlyWithoutLogs() {
        // 수요일에 만든 주말 맞춤 루틴은 그 주 토요일이 첫 예정일
        let r = routine(.interval, .care, created: date(2026, 10, 14))
        r.weekendOnly = true
        XCTAssertEqual(r.nextDue, date(2026, 10, 17))
    }

    func testIntervalNextDue() {
        let r = routine(.interval, .care, created: date(2026, 8, 1))
        r.intervalValue = 1
        r.intervalUnit = .month
        log(r, date(2026, 9, 16))
        XCTAssertEqual(r.nextDue, date(2026, 10, 16))
        XCTAssertEqual(r.dueEnd, date(2026, 10, 16))
    }

    func testWeekendOnlyMovesToSaturdayOfThatWeek() {
        let r = routine(.interval, .care, created: date(2026, 8, 1))
        r.intervalValue = 1
        r.intervalUnit = .month
        r.weekendOnly = true
        log(r, date(2026, 9, 16)) // 다음 예정 10/16(금)
        XCTAssertEqual(r.nextDue, date(2026, 10, 17))
        XCTAssertEqual(r.dueEnd, date(2026, 10, 18))
        XCTAssertTrue(r.isWithinDueWindow(date(2026, 10, 18)))
        XCTAssertFalse(r.isWithinDueWindow(date(2026, 10, 19)))
    }

    func testWeekendOnlyWhenTargetIsSunday() {
        let r = routine(.interval, .care, created: date(2026, 8, 1))
        r.intervalValue = 1
        r.intervalUnit = .month
        r.weekendOnly = true
        log(r, date(2026, 9, 18)) // 다음 예정 10/18(일) → 같은 주 토요일 10/17
        XCTAssertEqual(r.nextDue, date(2026, 10, 17))
    }

    // MARK: 주간형 (월요일 시작)

    func testWeeklyPartsResetOnMonday() {
        let r = routine(.weekly, .gym, created: date(2026, 9, 1))
        r.parts = ["가슴", "등", "하체"]
        log(r, date(2026, 10, 11), part: "가슴") // 일요일 = 지난주
        log(r, date(2026, 10, 12), part: "등")   // 월요일 = 이번 주
        XCTAssertEqual(r.remainingParts(inWeekOf: date(2026, 10, 13)), ["가슴", "하체"])
        XCTAssertEqual(r.remainingParts(inWeekOf: date(2026, 10, 11)), ["등", "하체"])
    }

    // MARK: 약속

    func testAppointmentAppearsOnlyOnItsDay() {
        let r = routine(.once, .appointment, created: date(2026, 10, 13))
        r.eventDate = date(2026, 10, 15, 19, 30)
        XCTAssertTrue(r.appears(on: date(2026, 10, 15), today: date(2026, 10, 13)))
        XCTAssertFalse(r.appears(on: date(2026, 10, 14), today: date(2026, 10, 13)))
    }

    // MARK: 식단

    func testDietPhase() {
        let r = routine(.daily, .diet, created: date(2026, 10, 1))
        r.windowStart = 12 * 60
        r.windowEnd = 20 * 60
        XCTAssertFalse(r.dietPhase(at: date(2026, 10, 13, 9)).eating)
        XCTAssertEqual(r.dietPhase(at: date(2026, 10, 13, 9)).end, date(2026, 10, 13, 12))
        XCTAssertTrue(r.dietPhase(at: date(2026, 10, 13, 13)).eating)
        let night = r.dietPhase(at: date(2026, 10, 13, 22))
        XCTAssertFalse(night.eating)
        XCTAssertEqual(night.end, date(2026, 10, 14, 12))
    }

    // MARK: 연속 기록

    func testStreakForgivesOneMissPerWeek() {
        let today = cal.startOfDay(for: .now)
        let r = routine(.daily, created: cal.date(byAdding: .day, value: -30, to: today)!)
        for i in 1...10 where i != 4 {
            log(r, cal.date(byAdding: .day, value: -i, to: today)!)
        }
        // 4일 전 한 번 놓쳤어도 이어진다 (같은 주에 두 번 놓치지 않는 한)
        XCTAssertGreaterThanOrEqual(r.streak, 9)
    }

    // MARK: 알림

    func testNotificationsSkipDoneAndRestDays() {
        let now = date(2026, 10, 13, 7)
        let a = routine(.daily, created: date(2026, 10, 1))
        a.reminderHour = 8
        let b = routine(.daily, created: date(2026, 10, 1))
        b.reminderHour = 8
        log(b, now, skipped: true)
        let c = routine(.daily, created: date(2026, 10, 1))
        c.reminderHour = 8
        log(c, now)
        let ids = NotificationScheduler.buildRequests([a, b, c], now: now).map(\.identifier)
        XCTAssertTrue(ids.contains("\(a.id.uuidString)-0-0"))
        XCTAssertFalse(ids.contains("\(b.id.uuidString)-0-0"))
        XCTAssertFalse(ids.contains("\(c.id.uuidString)-0-0"))
    }

    func testNotificationsCappedAndFuture() {
        let now = date(2026, 10, 13, 12)
        let routines = (0..<40).map { _ -> Routine in
            let r = routine(.daily, .medicine, created: date(2026, 10, 1))
            r.reminderTimes = [8 * 60, 13 * 60, 21 * 60]
            return r
        }
        let requests = NotificationScheduler.buildRequests(routines, now: now)
        XCTAssertLessThanOrEqual(requests.count, 60)
        // 모두 기준 시각 이후, 같은 ID 없음
        for req in requests {
            let comps = try! XCTUnwrap((req.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
            XCTAssertGreaterThan(cal.date(from: comps)!, now)
        }
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count)
    }

    func testAppointmentReminders() {
        let r = routine(.once, .appointment, created: date(2026, 10, 13))
        r.eventDate = date(2026, 10, 15, 19, 30)
        r.remindOffsets = [60, 1440]
        let req = NotificationScheduler.buildRequests([r], now: date(2026, 10, 13, 12))
        XCTAssertEqual(req.count, 2)
    }

    // MARK: 알람

    func testAlarmSkipsRestDay() {
        let now = date(2026, 10, 13, 7)
        let r = routine(.daily, .medicine, created: date(2026, 10, 1))
        r.isCritical = true
        r.useAlarm = true
        r.reminderHour = 8
        log(r, now, skipped: true)
        let plans = AlarmScheduler.upcoming([r], now: now)
        XCTAssertFalse(plans.contains { cal.isDate($0.date, inSameDayAs: now) })
        XCTAssertTrue(plans.contains { cal.isDate($0.date, inSameDayAs: date(2026, 10, 14)) })
    }

    // MARK: 백업

    func testBackupRoundTrip() throws {
        let r = routine(.weekly, .gym, created: date(2026, 9, 1))
        r.parts = ["가슴", "등"]
        r.restWeekdays = [1]
        let l = log(r, date(2026, 10, 12), part: "가슴")
        let s = WorkoutSet(exercise: "벤치프레스", weight: 60, reps: 10, order: 0)
        context.insert(s)
        l.sets?.append(s)
        log(r, date(2026, 10, 13), skipped: true)
        try context.save()

        let data = try Backup.encode(Backup.makeFile(context: context))
        XCTAssertEqual(try Backup.restore(data, context: context), 1)
        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Routine>()).first)
        XCTAssertEqual(restored.parts, ["가슴", "등"])
        XCTAssertEqual(restored.restWeekdays, [1])
        XCTAssertEqual(restored.logs?.count, 2)
        XCTAssertEqual(restored.logs?.filter(\.skipped).count, 1)
        XCTAssertEqual(restored.logs?.first { $0.part == "가슴" }?.sets?.first?.weight, 60)
    }
}

/// 규칙 기반 대화 해석 (AI를 못 쓸 때)
@MainActor
final class ChatFallbackTests: XCTestCase {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 10))! // 화요일

    func draft(_ text: String) -> RoutineFactory.Draft? {
        if case .draft(let d, _) = ChatFallback.handle(text, now: now) { return d }
        return nil
    }

    func testDailyVitamin() throws {
        let d = try XCTUnwrap(draft("매일 아침 8시에 비타민 먹기"))
        XCTAssertEqual(d.name, "비타민")
        XCTAssertEqual(d.category, .medicine)
        XCTAssertEqual(d.time?.hour, 8)
    }

    func testAppointmentNextWeekFriday() throws {
        let d = try XCTUnwrap(draft("다음 주 금요일 저녁 7시 강남역에서 유진이랑 저녁"))
        XCTAssertEqual(d.category, .appointment)
        XCTAssertEqual(d.name, "유진이랑 저녁")
        XCTAssertEqual(d.location, "강남역")
        XCTAssertEqual(d.time?.hour, 19)
        XCTAssertEqual(Calendar.current.component(.day, from: d.date!), 23)
    }

    func testThisWeekdayAndPM() throws {
        let d = try XCTUnwrap(draft("금요일 오후 3시 반 치과"))
        XCTAssertEqual(Calendar.current.component(.day, from: d.date!), 16)
        XCTAssertEqual(d.time?.hour, 15)
        XCTAssertEqual(d.time?.minute, 30)
        XCTAssertEqual(d.name, "치과")
    }

    func testTomorrow() throws {
        let d = try XCTUnwrap(draft("내일 12시 점심 약속"))
        XCTAssertEqual(Calendar.current.component(.day, from: d.date!), 14)
        XCTAssertEqual(d.time?.hour, 12)
    }

    func testIntervals() throws {
        let a = try XCTUnwrap(draft("3일마다 화분 물주기"))
        XCTAssertEqual(a.intervalValue, 3)
        XCTAssertEqual(a.intervalUnit, .day)
        let b = try XCTUnwrap(draft("2주마다 강아지 샴푸"))
        XCTAssertEqual(b.category, .pet)
        XCTAssertEqual(b.intervalValue, 2)
        XCTAssertEqual(b.intervalUnit, .week)
        let c = try XCTUnwrap(draft("한 달에 한 번 수염 제모"))
        XCTAssertEqual(c.category, .care)
        XCTAssertEqual(c.intervalValue, 1)
        XCTAssertEqual(c.intervalUnit, .month)
        XCTAssertEqual(c.name, "수염 제모")
    }

    func testRepeatingIsNotAppointment() throws {
        let d = try XCTUnwrap(draft("매주 월요일 분리수거"))
        XCTAssertNotEqual(d.category, .appointment)
        XCTAssertEqual(d.intervalUnit, .week)
    }

    func testAskToRemindCreatesRoutine() throws {
        let d = try XCTUnwrap(draft("매일 8시 비타민 알려줘"))
        XCTAssertEqual(d.name, "비타민")
    }

    func testAppointmentTimeDefaultsToAfternoon() throws {
        XCTAssertEqual(try XCTUnwrap(draft("내일 3시 회의")).time?.hour, 15)
        XCTAssertEqual(try XCTUnwrap(draft("내일 오전 9시 회의")).time?.hour, 9)
        XCTAssertEqual(try XCTUnwrap(draft("내일 밤 12시 영화")).time?.hour, 0)
    }

    func testHoursOfDurationAreNotTime() throws {
        let d = try XCTUnwrap(draft("매일 2시간 공부"))
        XCTAssertNil(d.time)
    }

    func testNegativeIsNotLogged() {
        if case .reply(let text) = ChatFallback.handle("약 못 먹었어", now: now) {
            XCTAssertTrue(text.contains("기록하지 않았"))
        } else {
            XCTFail("약속·루틴으로 해석하면 안 됨")
        }
    }

    func testMonthDayDate() throws {
        let d = try XCTUnwrap(draft("11월 3일 오전 10시 건강검진"))
        XCTAssertEqual(Calendar.current.component(.month, from: d.date!), 11)
        XCTAssertEqual(Calendar.current.component(.day, from: d.date!), 3)
        XCTAssertEqual(d.time?.hour, 10)
        XCTAssertEqual(d.name, "건강검진")
    }
}
