import ActivityKit
import SwiftUI
import WidgetKit

struct DietLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DietActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.eating ? "식사 시간" : "금식 중", systemImage: icon(state))
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .font(.title3.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(.white)
                        Text("\(context.attributes.name) · 식사 \(context.attributes.window)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(state))
            } compactTrailing: {
                Text(timerInterval: state.start...state.end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
            } minimal: {
                Image(systemName: icon(state))
            }
        }
    }

    private func icon(_ state: DietActivityAttributes.ContentState) -> String {
        state.eating ? "fork.knife" : "moon.zzz"
    }

    private func lockScreen(_ context: ActivityViewContext<DietActivityAttributes>) -> some View {
        let state = context.state
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.eating ? "식사 시간" : "금식 중", systemImage: icon(state))
                    .font(.headline)
                Spacer()
                Text(timerInterval: state.start...state.end, countsDown: true)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(.primary)
            Text("\(context.attributes.name) · 식사 \(context.attributes.window)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}
