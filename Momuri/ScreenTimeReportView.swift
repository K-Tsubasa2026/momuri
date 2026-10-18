import DeviceActivity
import SwiftUI

/// 리포트 확장이 그리는 오늘 사용 시간
struct ScreenTimeReportView: View {
    private var filter: DeviceActivityFilter {
        let today = Calendar.current.dateInterval(of: .day, for: .now) ?? DateInterval(start: .now, duration: 86400)
        return DeviceActivityFilter(segment: .daily(during: today), users: .all, devices: .init([.iPhone]))
    }

    var body: some View {
        if ScreenTimeManager.isAuthorized {
            DeviceActivityReport(.totalActivity, filter: filter)
                .frame(height: 36)
        } else {
            Text("루틴 설정에서 Screen Time 권한을 켜야 사용 시간이 보여요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
