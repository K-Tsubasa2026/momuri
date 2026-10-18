import Foundation

extension RoutineLog {
    var sortedSets: [WorkoutSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    /// 처음 나온 순서대로 종목 이름
    var exercises: [String] {
        var seen = Set<String>()
        return sortedSets.map(\.exercise).filter { seen.insert($0).inserted }
    }
}

extension Routine {
    /// 기준 날짜 이전에 이 종목을 한 가장 최근 세트들
    func previousSets(of exercise: String, before date: Date) -> [WorkoutSet] {
        let earlier = (logs ?? [])
            .filter { $0.date < date && $0.exercises.contains(exercise) }
            .max { $0.date < $1.date }
        return earlier?.sortedSets.filter { $0.exercise == exercise } ?? []
    }

    /// 종목별 최고 무게 세트
    func bestSet(of exercise: String) -> WorkoutSet? {
        (logs ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.exercise == exercise }
            .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }

    /// 이 부위에서 해 본 종목들 (최근 순)
    func usedExercises(for part: String?) -> [String] {
        var seen = Set<String>()
        return (logs ?? [])
            .filter { part == nil || $0.part == part }
            .sorted { $0.date > $1.date }
            .flatMap(\.exercises)
            .filter { seen.insert($0).inserted }
    }
}

extension WorkoutSet {
    var summary: String {
        Routine.format(weight) + "kg × \(reps)"
    }
}
