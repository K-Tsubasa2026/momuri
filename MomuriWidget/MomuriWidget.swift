import WidgetKit
import SwiftUI
import SwiftData

struct MomuriEntry: TimelineEntry {
    let date: Date
    let routines: [RoutineSnapshot]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MomuriEntry {
        MomuriEntry(date: .now, routines: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (MomuriEntry) -> Void) {
        completion(entry(for: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MomuriEntry>) -> Void) {
        // 알림 시각이 지나면 색·상태가 바뀌므로 30분마다
        completion(Timeline(entries: [entry(for: context.family)], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry(for family: WidgetFamily) -> MomuriEntry {
        let context = ModelContext(SharedStore.container)
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortOrder)])
        let routines = ((try? context.fetch(descriptor)) ?? []).filter(\.showInWidget)
        return MomuriEntry(date: .now, routines: routines.map { RoutineSnapshot($0, days: family.days) })
    }
}

extension WidgetFamily {
    var days: Int {
        switch self {
        case .systemSmall: 7
        case .systemLarge: 28
        default: 14
        }
    }

    var routineLimit: Int {
        switch self {
        case .systemSmall: 3
        case .systemLarge: 7
        default: 5
        }
    }
}

struct MomuriWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomuriEntry

    private var shown: [RoutineSnapshot] { Array(entry.routines.prefix(family.routineLimit)) }
    private var due: [RoutineSnapshot] { entry.routines.filter(\.dueToday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(family == .systemSmall ? "최근 7일" : family == .systemLarge ? "최근 4주" : "최근 2주")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !due.isEmpty {
                    Text("오늘 \(due.filter(\.doneToday).count)/\(due.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.routines.isEmpty {
                Spacer()
                Text("앱에서 루틴을 추가해 주세요").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(shown) { r in
                    GrassRow(name: r.name,
                             trailing: family == .systemSmall ? nil : r.status,
                             cells: r.cells,
                             urgency: r.urgency,
                             labelWidth: family == .systemSmall ? 30 : 48,
                             spacing: family == .systemLarge ? 1.5 : 2)
                }
                if family == .systemLarge {
                    Divider().padding(.vertical, 4)
                    todayList
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(due.prefix(5)) { r in
                // 양·부위를 적어야 하는 루틴은 위젯에서 기록하지 않고 앱을 연다
                if r.simpleCheck {
                    Button(intent: ToggleRoutineIntent(routineID: r.id)) { todayRow(r) }
                        .buttonStyle(.plain)
                } else {
                    Link(destination: URL(string: "momuri://today")!) { todayRow(r) }
                }
            }
        }
    }
}

extension MomuriWidgetView {
    func todayRow(_ r: RoutineSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: r.doneToday ? "checkmark.circle.fill" : r.simpleCheck ? "circle" : "arrow.up.forward.circle")
                .foregroundStyle(r.urgency.color ?? .primary)
            Text(r.name)
                .strikethrough(r.doneToday)
                .foregroundStyle(r.doneToday ? .secondary : .primary)
            Spacer()
            Text(r.status).foregroundStyle(r.urgency.color ?? .secondary).monospacedDigit()
        }
        .font(.caption)
    }
}

struct MomuriWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MomuriGrass", provider: Provider()) { entry in
            MomuriWidgetView(entry: entry)
        }
        .configurationDisplayName("momuri")
        .description("루틴별 잔디와 오늘 남은 일")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct MomuriWidgetBundle: WidgetBundle {
    var body: some Widget {
        MomuriWidget()
        LockScreenWidget()
        DietLiveActivityWidget()
        RoutineControl()
    }
}
