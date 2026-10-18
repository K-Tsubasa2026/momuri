import SwiftUI

/// 홈: 오늘 루틴을 가운데 모무리에 이어진 액체 방울로 보여준다.
/// 방울은 천천히 떠다니고, 가까워지면 서로 녹아 붙는다 (blur + alphaThreshold).
/// 색은 상태만 말한다: 검정=할 일, 회색=끝냄, 주황=곧, 빨강=놓침·요즘 자주 놓침.
struct HomeBlobView: View {
    let routines: [Routine]
    let onOpen: (Routine) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 잠깐 보여 줄 반응 (점프·만세). 끝나면 nil 로 돌아가 평소 표정이 된다
    @State private var burst: MomuriCharacterView.Mood?

    private let cal = Calendar.current

    // MARK: - 방울 데이터

    enum Tone {
        case todo, done, soon, missed, rest

        var fill: Color {
            switch self {
            case .todo: Color(.label)
            case .done: Color(.systemGray4)
            case .soon: Color(.systemOrange)
            case .missed: Color(.systemRed)
            case .rest: Color(.systemGray5)
            }
        }

        var text: Color {
            switch self {
            case .done, .rest: Color(.secondaryLabel)
            default: Color(.systemBackground)
            }
        }
    }

    struct Blob: Identifiable {
        let id: UUID
        let routine: Routine
        let title: String
        let status: String
        let tone: Tone
        let radius: CGFloat
        let seed: Double
    }

    private var blobs: [Blob] {
        let today = Date.now
        let items = routines.filter { r in
            (r.kind != .once && r.appears(on: today)) || (r.kind == .once && r.isUpcoming && (r.eventLabel(relative: true) != "지남") && (cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: r.eventDate)).day ?? 99) <= 3)
        }
        return items.prefix(10).enumerated().map { i, r in
            let tone = tone(of: r)
            let base: CGFloat = r.isCritical ? 40 : 33
            return Blob(id: r.id, routine: r, title: r.name, status: r.kind == .once ? r.eventLabel(relative: true) : r.listStatus(on: today),
                        tone: tone, radius: tone == .done || tone == .rest ? base * 0.8 : base, seed: Double(i) * 1.7 + 0.3)
        }
    }

    private func tone(of r: Routine) -> Tone {
        let today = Date.now
        if r.isRestDay(today) && !r.isDone(on: today) { return .rest }
        if r.isSettled(on: today) && r.kind != .weekly && r.kind != .monthly { return .done }
        switch r.urgency() {
        case .overdue: return .missed
        case .soon: return .soon
        case .none: break
        }
        if let n = r.daysUntilDue(), n < 0 { return .missed }
        if missRate(r) >= 0.4 { return .missed }
        return .todo
    }

    /// 지난 7일(오늘 제외) 해야 했던 날 중 놓친 비율
    private func missRate(_ r: Routine) -> Double {
        guard r.kind == .daily, r.category != .screen else { return 0 }
        let days = (1...7).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
            .filter { $0 >= r.startDay && !r.isRestDay($0) }
        guard days.count >= 3 else { return 0 }
        return Double(days.filter { !r.isDone(on: $0) }.count) / Double(days.count)
    }

    /// 요즘 자주 놓치는 루틴 (홈 아래 한 줄)
    private var oftenMissed: [(String, Int, Int)] {
        routines.compactMap { r in
            guard r.kind == .daily, r.category != .screen else { return nil }
            let days = (1...7).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
                .filter { $0 >= r.startDay && !r.isRestDay($0) }
            let missed = days.filter { !r.isDone(on: $0) }.count
            return days.count >= 3 && Double(missed) / Double(days.count) >= 0.4 ? (r.name, missed, days.count) : nil
        }
    }

    private var progress: (done: Int, total: Int) {
        let due = routines.filter { $0.kind != .once && $0.appears(on: .now) && $0.kind != .weekly && $0.kind != .monthly }
        return (due.filter { $0.isSettled(on: .now) }.count, due.count)
    }

    // MARK: - 화면

    var body: some View {
        let blobs = blobs
        VStack(spacing: 12) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let points = positions(blobs, in: geo.size, center: center, t: t)
                    ZStack {
                        Canvas { context, _ in
                            // alphaThreshold는 한 가지 색만 남겨서, 색(상태)마다 층을 따로 그린다
                            for tone in [Tone.done, .rest, .todo, .soon, .missed] {
                                let group = zip(blobs, points).filter { $0.0.tone == tone }
                                guard !group.isEmpty || tone == .todo else { continue }
                                context.drawLayer { layer in
                                    layer.addFilter(.alphaThreshold(min: 0.5, color: tone.fill))
                                    layer.addFilter(.blur(radius: 8))
                                    // 가운데에서 뻗는 액체 줄기
                                    for (blob, p) in group {
                                        var path = Path()
                                        path.move(to: center)
                                        let mid = CGPoint(x: (center.x + p.x) / 2 + CGFloat(sin(t * 0.7 + blob.seed)) * 16,
                                                          y: (center.y + p.y) / 2 + CGFloat(cos(t * 0.6 + blob.seed)) * 16)
                                        path.addQuadCurve(to: p, control: mid)
                                        layer.stroke(path, with: .color(.black), lineWidth: 14)
                                    }
                                    for (blob, p) in group {
                                        let r = blob.radius * (1 + 0.05 * CGFloat(sin(t * 1.3 + blob.seed * 2)))
                                        layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.black))
                                    }
                                    if tone == .todo {
                                        let cr: CGFloat = 64 + 3 * CGFloat(sin(t * 2))
                                        layer.fill(Path(ellipseIn: CGRect(x: center.x - cr, y: center.y - cr, width: cr * 2, height: cr * 2)), with: .color(.black))
                                    }
                                }
                            }
                        }

                        // 가운데 모무리
                        character(t: t)
                            .position(center)

                        // 이름표와 누르는 자리 (방울을 따라 움직인다)
                        ForEach(Array(zip(blobs, points)), id: \.0.id) { blob, p in
                            Button { onOpen(blob.routine) } label: {
                                VStack(spacing: 1) {
                                    Text(blob.title).font(.caption2.weight(.semibold)).lineLimit(1)
                                    Text(blob.status).font(.caption2).monospacedDigit().lineLimit(1)
                                }
                                .foregroundStyle(blob.tone.text)
                                .frame(width: blob.radius * 2 - 8)
                                .minimumScaleFactor(0.6)
                                .frame(width: blob.radius * 2, height: blob.radius * 2)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .position(p)
                            .accessibilityLabel("\(blob.title) \(blob.status)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 470)

            summary
        }
        .padding(.horizontal, 20)
        .onChange(of: progress.done) { old, new in
            guard new > old else { return }
            // 하나 끝내면 작게 점프, 전부 끝내면 통통 뛰기
            if progress.total > 0 && new == progress.total { celebrate() } else { hop() }
        }
    }

    /// 평소 표정: 할 일이 없으면 갸웃, 밤이거나 오늘이 전부 쉬는 날이면 졸림
    private var restingMood: MomuriCharacterView.Mood {
        let hour = cal.component(.hour, from: .now)
        if hour >= 23 || hour < 6 { return .sleepy }
        if blobs.isEmpty { return routines.contains { $0.isRestDay(.now) } ? .sleepy : .wonder }
        return .idle
    }

    private func character(t: Double) -> some View {
        let p = progress
        return ZStack {
            Circle().fill(Color(.systemBackground)).frame(width: 116, height: 116)
            MomuriCharacterView(mood: reduceMotion ? restingMood : (burst ?? restingMood))
                .frame(width: 136, height: 136)
                .offset(y: -20)
                .allowsHitTesting(false)
            if p.total > 0 {
                Text("\(p.done)/\(p.total)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.label)))
                    .foregroundStyle(Color(.systemBackground))
                    .offset(y: 58)
            }
        }
        .accessibilityLabel("오늘 \(p.done)개 끝냄, 전체 \(p.total)개")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if blobs.isEmpty {
                Text(routines.isEmpty ? "오른쪽 위 + 로 첫 루틴을 만들어 보세요" : "오늘은 할 일이 없어요. 푹 쉬어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !oftenMissed.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color(.systemRed)).frame(width: 6, height: 6)
                    Text("요즘 자주 놓쳐요: " + oftenMissed.map { "\($0.0) (7일 중 \($0.1)번)" }.joined(separator: ", "))
                        .font(.footnote)
                }
            }
            Text("방울을 누르면 자세히 볼 수 있어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 움직임

    /// 가운데를 도는 두 겹 고리 위에 놓고, 저마다 천천히 흔들린다
    private func positions(_ blobs: [Blob], in size: CGSize, center: CGPoint, t: Double) -> [CGPoint] {
        let n = max(blobs.count, 1)
        let rx = size.width / 2 - 52
        let ry = size.height / 2 - 52
        return blobs.enumerated().map { i, b in
            let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2 + sin(t * 0.15 + b.seed) * 0.12
            let ring = i % 2 == 0 ? 0.95 : 0.74
            let wobble = 1 + 0.04 * sin(t * 0.9 + b.seed * 3)
            return CGPoint(x: center.x + CGFloat(cos(angle) * ring * wobble) * rx,
                           y: center.y + CGFloat(sin(angle) * ring * wobble) * ry)
        }
    }

    private func hop() { react(.hop, for: 1.3) }

    private func celebrate() { react(.cheer, for: 2.7) }

    /// 반응 애니메이션을 정해진 시간만 보여 준다 (점프 1회 1.3초, 만세 통통 3회 2.7초)
    private func react(_ mood: MomuriCharacterView.Mood, for seconds: Double) {
        burst = mood
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if burst == mood { burst = nil }
        }
    }
}
