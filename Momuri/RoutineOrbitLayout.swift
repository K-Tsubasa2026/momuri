import CoreGraphics
import Foundation

/// 홈 궤도 배치 계산 (화면을 그리지 않는 순수 계산이라 테스트할 수 있다).
///
/// 카드마다 기준 위치(anchor)를 정하고, 그 주변을 떠다녀도 서로·가운데 캐릭터·화면 가장자리와
/// 겹치지 않도록 카드를 "떠다닐 범위만큼 부풀린 사각형"으로 보고 서로 밀어내며 자리를 잡는다.
/// 자리가 모자라면 떠다닐 범위 → 카드 크기 순으로 줄인다.
enum RoutineOrbitLayout {
    struct Result: Equatable {
        var anchors: [CGPoint]
        /// 떠다닐 범위(pt). 이 이상 움직이지 않는다
        var amplitude: CGFloat
        /// 카드 크기 배율
        var scale: CGFloat
        /// 겹침 없이 다 놓였는지
        var fits: Bool
    }

    /// 가운데 캐릭터 원의 반지름 (카드가 들어오면 안 되는 영역)
    static let centerRadius: CGFloat = 64
    /// 카드 사이 최소 간격
    static let gap: CGFloat = 8

    /// 넉넉한 것부터 시도한다: (떠다닐 범위, 카드 배율)
    static let attempts: [(CGFloat, CGFloat)] = [(18, 1), (14, 1), (10, 1), (8, 0.9), (6, 0.82)]

    static func solve(sizes: [CGSize], in bounds: CGSize) -> Result {
        guard !sizes.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return Result(anchors: [], amplitude: 0, scale: 1, fits: true)
        }
        var last = Result(anchors: [], amplitude: 0, scale: 1, fits: false)
        for (amplitude, scale) in attempts {
            let boxes = sizes.map { CGSize(width: $0.width * scale + 2 * amplitude + gap,
                                           height: $0.height * scale + 2 * amplitude + gap) }
            let anchors = relax(boxes: boxes, in: bounds)
            let ok = !overlaps(anchors: anchors, boxes: boxes, in: bounds)
            last = Result(anchors: anchors, amplitude: amplitude, scale: scale, fits: ok)
            if ok { return last }
        }
        return last
    }

    // MARK: - 밀어내기

    /// 가운데를 둘러싼 타원 위에 고르게 놓은 뒤, 겹친 만큼 서로 밀어낸다. 항상 같은 입력엔 같은 결과.
    static func relax(boxes: [CGSize], in bounds: CGSize, iterations: Int = 240) -> [CGPoint] {
        let c = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let n = boxes.count
        var p: [CGPoint] = boxes.enumerated().map { i, box in
            // 위에서 시작해 시계 방향. 정확히 옆(가운데와 겹치기 쉬운 자리)은 피하도록 반 칸 비튼다
            let angle = -Double.pi / 2 + (Double(i) + (n % 2 == 0 ? 0.5 : 0)) / Double(n) * 2 * .pi
            let rx = max(bounds.width / 2 - box.width / 2, 0)
            let ry = max(bounds.height / 2 - box.height / 2, 0)
            let ring: CGFloat = n > 7 && i % 2 == 1 ? 0.72 : 1
            return CGPoint(x: c.x + CGFloat(cos(angle)) * rx * ring, y: c.y + CGFloat(sin(angle)) * ry * ring)
        }

        for _ in 0..<iterations {
            var moved = false
            // 카드끼리
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = p[j].x - p[i].x, dy = p[j].y - p[i].y
                    let ox = (boxes[i].width + boxes[j].width) / 2 - abs(dx)
                    let oy = (boxes[i].height + boxes[j].height) / 2 - abs(dy)
                    guard ox > 0, oy > 0 else { continue }
                    moved = true
                    if ox < oy {
                        let s: CGFloat = dx == 0 ? (i < j ? 1 : -1) : (dx > 0 ? 1 : -1)
                        p[i].x -= s * ox / 2; p[j].x += s * ox / 2
                    } else {
                        let s: CGFloat = dy == 0 ? 1 : (dy > 0 ? 1 : -1)
                        p[i].y -= s * oy / 2; p[j].y += s * oy / 2
                    }
                }
            }
            // 가운데 캐릭터에서 바깥으로
            for i in 0..<n {
                let push = centerPenetration(p[i], box: boxes[i], center: c)
                if push.dx != 0 || push.dy != 0 {
                    moved = true
                    p[i].x += push.dx; p[i].y += push.dy
                }
            }
            // 화면 안으로
            for i in 0..<n {
                let hx = boxes[i].width / 2, hy = boxes[i].height / 2
                let x = min(max(p[i].x, hx), bounds.width - hx)
                let y = min(max(p[i].y, hy), bounds.height - hy)
                if x != p[i].x || y != p[i].y { p[i] = CGPoint(x: x, y: y) }
            }
            if !moved { break }
        }
        return p
    }

    /// 사각형이 가운데 원에 파고든 만큼 밀어낼 벡터
    static func centerPenetration(_ p: CGPoint, box: CGSize, center c: CGPoint) -> CGVector {
        let nx = min(max(c.x, p.x - box.width / 2), p.x + box.width / 2)
        let ny = min(max(c.y, p.y - box.height / 2), p.y + box.height / 2)
        var vx = nx - c.x, vy = ny - c.y
        var d = (vx * vx + vy * vy).squareRoot()
        if d < 0.001 {
            // 원 중심이 사각형 안: 사각형 중심 쪽으로 밀어낸다
            vx = p.x - c.x; vy = p.y - c.y
            d = max((vx * vx + vy * vy).squareRoot(), 0.001)
            let need = centerRadius + max(box.width, box.height) / 2
            return CGVector(dx: vx / d * (need - d), dy: vy / d * (need - d))
        }
        guard d < centerRadius else { return .zero }
        return CGVector(dx: vx / d * (centerRadius - d), dy: vy / d * (centerRadius - d))
    }

    static func overlaps(anchors p: [CGPoint], boxes: [CGSize], in bounds: CGSize) -> Bool {
        let c = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let eps: CGFloat = 0.5
        for i in p.indices {
            let push = centerPenetration(p[i], box: boxes[i], center: c)
            if abs(push.dx) > eps || abs(push.dy) > eps { return true }
            if p[i].x - boxes[i].width / 2 < -eps || p[i].x + boxes[i].width / 2 > bounds.width + eps { return true }
            if p[i].y - boxes[i].height / 2 < -eps || p[i].y + boxes[i].height / 2 > bounds.height + eps { return true }
            for j in p.indices where j > i {
                let ox = (boxes[i].width + boxes[j].width) / 2 - abs(p[j].x - p[i].x)
                let oy = (boxes[i].height + boxes[j].height) / 2 - abs(p[j].y - p[i].y)
                if ox > eps && oy > eps { return true }
            }
        }
        return false
    }
}

/// 루틴마다 고정된 떠다니는 성격. 루틴 ID에서 만들어서 앱을 다시 켜도, 데이터가 바뀌어도 같다.
struct OrbitDrift: Equatable {
    /// 범위 1 기준 진폭 (8~18pt 범위를 0.44~1로 나타낸 값)
    let ampX: CGFloat, ampY: CGFloat
    /// 한 번 오가는 데 걸리는 초 (6~12초)
    let periodX: Double, periodY: Double
    let phaseX: Double, phaseY: Double

    init(id: UUID) {
        let b = withUnsafeBytes(of: id.uuid) { Array($0) }
        func unit(_ i: Int) -> Double { Double(b[i]) / 255 }
        ampX = CGFloat(8 + 10 * unit(0)) / 18
        ampY = CGFloat(8 + 10 * unit(1)) / 18
        periodX = 6 + 6 * unit(2)
        periodY = 6 + 6 * unit(3)
        phaseX = unit(4) * 2 * .pi
        phaseY = unit(5) * 2 * .pi
    }

    /// t초일 때 기준 위치에서 벗어난 정도. 사인 두 개를 섞어 매끈하고 끊김이 없다.
    /// 결과는 항상 ±amplitude 안이다.
    func offset(at t: Double, amplitude: CGFloat) -> CGSize {
        let x = 0.75 * sin(2 * .pi * t / periodX + phaseX) + 0.25 * sin(2 * .pi * t / (periodX * 0.53) + phaseY)
        let y = 0.75 * sin(2 * .pi * t / periodY + phaseY) + 0.25 * sin(2 * .pi * t / (periodY * 0.61) + phaseX)
        return CGSize(width: CGFloat(x) * ampX * amplitude, height: CGFloat(y) * ampY * amplitude)
    }
}
