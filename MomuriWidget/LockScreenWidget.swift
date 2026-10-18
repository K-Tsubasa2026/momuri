import WidgetKit
import SwiftUI
import SwiftData

/// 잠금화면용: 오늘 남은 일 중심
struct TodayEntry: TimelineEntry {
    let date: Date
    let total: Int
    let done: Int
    /// 아직 안 한 일. 급한 순서.
    let remaining: [RoutineSnapshot]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, total: 3, done: 1, remaining: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry())
    }

    /// 알림 시각이 지나면 색이 바뀌므로 30분마다 갱신
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry() -> TodayEntry {
        let context = ModelContext(SharedStore.container)
        let routines = (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let due = routines.map { RoutineSnapshot($0, days: 1) }.filter(\.dueToday)
        let rank: (Urgency) -> Int = { $0 == .overdue ? 0 : $0 == .soon ? 1 : 2 }
        let remaining = due.filter { !$0.doneToday }.sorted { rank($0.urgency) < rank($1.urgency) }
        return TodayEntry(date: .now, total: due.count, done: due.count - remaining.count, remaining: remaining)
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var progress: Double {
        entry.total == 0 ? 1 : Double(entry.done) / Double(entry.total)
    }

    private var circular: some View {
        Gauge(value: progress) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(entry.remaining.count)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Group {
            if let first = entry.remaining.first {
                Text("남은 \(entry.remaining.count) · \(first.name) \(first.status)")
            } else {
                Text("오늘 할 일 끝")
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(entry.remaining.isEmpty ? "오늘 할 일 끝" : "남은 일 \(entry.remaining.count)")
                    .font(.headline)
                    .widgetAccentable()
                Spacer()
                Text("\(entry.done)/\(entry.total)").font(.caption).monospacedDigit()
            }
            ForEach(entry.remaining.prefix(2)) { r in
                HStack(spacing: 4) {
                    // 잠금화면은 무채색이라 놓친 일은 느낌표로 구분
                    if r.urgency == .overdue {
                        Image(systemName: "exclamationmark.circle.fill")
                    } else {
                        Image(systemName: "circle")
                    }
                    Text(r.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(r.status).monospacedDigit().lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MomuriToday", provider: TodayProvider()) { entry in
            LockScreenView(entry: entry)
        }
        .configurationDisplayName("momuri 오늘")
        .description("오늘 남은 일과 놓친 일")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
