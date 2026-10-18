import SwiftUI

/// 가운데 캐릭터를 둘러싸고 루틴 카드가 물속처럼 떠다니는 궤도.
/// 카드와 가운데를 잇는 줄기는 액체처럼 녹아 붙는다 (blur + alphaThreshold, 색마다 층 하나).
///
/// 배치는 크기·루틴이 바뀔 때만 계산하고(RoutineOrbitLayout), 매 프레임은 떠다니는 오프셋만 더한다.
/// 홈이 보이고 앱이 앞에 있을 때만 초당 30번 갱신하고, 동작 줄이기에서는 멈춘 배치를 보여 준다.
struct RoutineOrbitView<Center: View>: View {
    let blobs: [HomeBlobView.Blob]
    let onOpen: (Routine) -> Void
    @ViewBuilder let center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var animating: Bool { visible && scenePhase == .active && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = RoutineOrbitLayout.solve(sizes: blobs.map(\.size), in: size)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { timeline in
                    let t = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                    let points = positions(layout: layout, t: t)
                    ZStack {
                        liquid(points: points, scale: layout.scale, center: mid, t: t)
                        cards(points: points, scale: layout.scale)
                    }
                }
                center().position(mid)
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private func positions(layout: RoutineOrbitLayout.Result, t: Double) -> [CGPoint] {
        zip(blobs, layout.anchors).map { blob, a in
            let o = blob.drift.offset(at: t, amplitude: layout.amplitude)
            return CGPoint(x: a.x + o.width, y: a.y + o.height)
        }
    }

    private func liquid(points: [CGPoint], scale: CGFloat, center: CGPoint, t: Double) -> some View {
        Canvas { context, _ in
            // alphaThreshold는 한 가지 색만 남겨서, 색(상태)마다 층을 따로 그린다
            for tone in [HomeBlobView.Tone.done, .rest, .todo, .soon, .missed] {
                let group = zip(blobs, points).filter { $0.0.tone == tone }
                guard !group.isEmpty || tone == .todo else { continue }
                context.drawLayer { layer in
                    layer.addFilter(.alphaThreshold(min: 0.5, color: tone.fill))
                    layer.addFilter(.blur(radius: 8))
                    for (blob, p) in group {
                        var path = Path()
                        path.move(to: center)
                        let seed = blob.drift.phaseX
                        let mid = CGPoint(x: (center.x + p.x) / 2 + CGFloat(sin(t * 0.7 + seed)) * 10,
                                          y: (center.y + p.y) / 2 + CGFloat(cos(t * 0.6 + seed)) * 10)
                        path.addQuadCurve(to: p, control: mid)
                        layer.stroke(path, with: .color(.black), lineWidth: 14)
                    }
                    for (blob, p) in group {
                        let w = blob.size.width * scale, h = blob.size.height * scale
                        let rect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
                        layer.fill(Path(roundedRect: rect, cornerRadius: HomeBlobView.Blob.corner * scale, style: .continuous),
                                   with: .color(.black))
                    }
                    if tone == .todo {
                        let r: CGFloat = 64
                        layer.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                   with: .color(.black))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func cards(points: [CGPoint], scale: CGFloat) -> some View {
        ForEach(Array(zip(blobs, points)), id: \.0.id) { blob, p in
            Button { onOpen(blob.routine) } label: {
                RoutineBubbleView(blob: blob, scale: scale)
            }
            .buttonStyle(.plain)
            .position(p)
            .accessibilityLabel(blob.accessibilityText)
            .accessibilityHint("두 번 탭하면 자세히 볼 수 있어요")
        }
    }
}
