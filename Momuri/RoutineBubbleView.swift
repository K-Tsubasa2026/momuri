import SwiftUI

/// 홈 궤도의 루틴 카드 하나 (글자·표시만. 카드 바탕은 RoutineOrbitView의 액체 층이 그린다).
struct RoutineBubbleView: View {
    let blob: HomeBlobView.Blob
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if blob.tone == .done {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.heavy))
                }
                Text(blob.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            Text(blob.status)
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(blob.tone.text)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        .frame(width: blob.size.width * scale, height: blob.size.height * scale)
        .overlay(alignment: .topTrailing) {
            // 요즘 자주 놓치는 루틴: 빨간 점만 (카드 색은 기한·긴급 상태만 말한다)
            if blob.oftenMissed {
                Circle()
                    .fill(Color(.systemRed))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 2, y: -2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: HomeBlobView.Blob.corner * scale))
    }
}
