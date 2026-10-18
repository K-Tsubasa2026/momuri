"""모무리 Rive 장면(RML) 생성기.

몸 외곽선은 make_svgs.py와 같은 메타볼(원 몇 개를 녹여 붙인 윤곽)로 만들고,
모든 자세에서 같은 개수(N)의 점으로 다시 찍어서 자세 사이를 키프레임으로 모핑한다.
상태는 view model 숫자 `mood` 하나로 고른다:
  0 기본(숨쉬기·깜빡임) 1 완료(점프) 2 전부 완료(두 팔 들고 통통) 3 일정 없음(앉아 갸웃) 4 휴식(졸림)

사용: python3 tools/make_rive.py  → rive/momuri/scene.rml
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_svgs import contour  # noqa: E402

N = 64            # 외곽선 점 개수 (모든 자세 동일해야 모핑된다)
FPS = 60
STROKE = 40

# ---------------------------------------------------------------- 자세

# 동글동글한 슬라임 몸 + 작게 솟은 손발. 눈은 (430,600)/(594,600), 입 (512,656) 기준.
BODY_C = [(512, 616, 258), (512, 690, 218)]
ARMS = [(232, 706, 58), (792, 706, 58)]
FEET = [(408, 912, 58), (616, 912, 58)]
BASE = BODY_C + ARMS + FEET
ARMS_UP = BODY_C + [(226, 676, 58), (798, 676, 58)] + FEET          # 손을 살짝 든 숨쉬기
CHEER = [(512, 626, 256), (512, 700, 216), (268, 560, 54), (208, 472, 58), (756, 560, 54), (816, 472, 58)] + FEET
SIT = [(512, 650, 264), (512, 724, 228), (238, 760, 58), (786, 760, 58), (356, 912, 58), (668, 912, 58)]


def scaled(balls, sx, sy, ox=512, oy=960):
    """바닥(oy)을 기준으로 눌리거나 늘어난 자세"""
    return [(ox + (x - ox) * sx, oy + (y - oy) * sy, r * (sx + sy) / 2) for x, y, r in balls]


def resample(balls):
    """윤곽을 N개 점으로, 위쪽 가운데에서 시작해 시계 방향으로 고르게 다시 찍는다."""
    pts = contour(balls)
    # 시계 방향(화면 좌표, y 아래로)으로 맞춘다
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts = pts[::-1]
    cx = sum(p[0] for p in pts) / len(pts)
    start = min(range(len(pts)), key=lambda i: abs(pts[i][0] - cx) + (pts[i][1] * 0.001 if pts[i][1] < 600 else 9999))
    pts = pts[start:] + pts[:start]
    # 누적 길이로 고르게
    seg = [math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts))]
    total = sum(seg)
    out, acc, i = [], 0.0, 0
    for k in range(N):
        target = total * k / N
        while acc + seg[i] < target:
            acc += seg[i]
            i += 1
        t = (target - acc) / seg[i] if seg[i] else 0
        a, b = pts[i], pts[(i + 1) % len(pts)]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def vertices(points):
    """각 점의 매끈한 핸들 (Catmull-Rom → 대칭 핸들)"""
    vs = []
    for i, p in enumerate(points):
        prev, nxt = points[i - 1], points[(i + 1) % len(points)]
        dx, dy = nxt[0] - prev[0], nxt[1] - prev[1]
        vs.append((p[0], p[1], math.atan2(dy, dx), math.hypot(dx, dy) / 6))
    return vs


POSE = {
    "base": vertices(resample(BASE)),
    "breathe": vertices(resample(scaled(ARMS_UP, 1.035, 0.965))),
    "squash": vertices(resample(scaled(BASE, 1.16, 0.8))),
    "stretch": vertices(resample(scaled(BASE, 0.9, 1.12))),
    "wobble": vertices(resample(scaled(BASE, 0.96, 1.04))),
    "wobble2": vertices(resample(scaled(BASE, 1.03, 0.97))),
    "cheer": vertices(resample(CHEER)),
    "cheerSquash": vertices(resample(scaled(CHEER, 1.1, 0.88))),
    "cheerStretch": vertices(resample(scaled(CHEER, 0.95, 1.06))),
    "sit": vertices(resample(SIT)),
    "sitBreathe": vertices(resample(scaled(SIT, 1.03, 0.97))),
}

# 상태 사이 전환(블렌드) 때 핸들이 한 바퀴 돌지 않도록, 모든 자세의 회전값을 기본 자세 근처로 맞춘다
for _name, _vs in POSE.items():
    for _i, (x, y, r, d) in enumerate(_vs):
        ref = POSE["base"][_i][2]
        while r - ref > math.pi:
            r -= 2 * math.pi
        while r - ref < -math.pi:
            r += 2 * math.pi
        _vs[_i] = (x, y, r, d)

# ---------------------------------------------------------------- id

_next = [100]


def nid():
    _next[0] += 1
    return f"0:{_next[0]}"


BODY = "0:20"
CHAR = "0:21"
FACE = "0:22"
EYE_L, EYE_R = "0:23", "0:24"
HAPPY_L, HAPPY_R = "0:25", "0:26"
CLOSED_L, CLOSED_R = "0:27", "0:28"
MOUTH_W, MOUTH_SMILE, MOUTH_OPEN = "0:29", "0:30", "0:31"
VERT_IDS = [f"0:{200 + i}" for i in range(N)]
VM, VM_MOOD, VM_INST = "0:40", "0:41", "0:42"

# ---------------------------------------------------------------- 그리기


def stroke(t=STROKE):
    return f'<Stroke thickness="{t}" cap="round" join="round" name="Stroke"><SolidColor colorValue="FF000000" name="Color"/></Stroke>'


def fill(c="FF000000"):
    return f'<Fill name="Fill"><SolidColor colorValue="{c}" name="Color"/></Fill>'


def body_shape():
    vs = "\n".join(
        f'                <CubicMirroredVertex x="{x:.1f}" y="{y:.1f}" rotation="{r:.4f}" distance="{d:.1f}" id="{vid}"/>'
        for (x, y, r, d), vid in zip(POSE["base"], VERT_IDS))
    return f'''            <Shape name="Body" id="{BODY}">
                <PointsPath isClosed="true" isClockwise="true" name="Path">
{vs}
                </PointsPath>
                {stroke()}
                {fill("FFFFFFFF")}
            </Shape>'''


def arc_shape(name, sid, cx, cy, w, h, up, thick, opacity):
    """눈 웃음(^)·감은 눈(‿) 같은 열린 곡선"""
    y2 = cy + (h if up else -h)
    return f'''                <Shape x="{cx}" y="{cy}" opacity="{opacity}" name="{name}" id="{sid}">
                    <PointsPath isClosed="false" name="Path">
                        <StraightVertex x="{-w}" y="0"/>
                        <CubicDetachedVertex x="0" y="{(-h if up else h)}" inRotation="{math.pi}" inDistance="{w*0.55:.1f}" outRotation="0" outDistance="{w*0.55:.1f}"/>
                        <StraightVertex x="{w}" y="0"/>
                    </PointsPath>
                    {stroke(thick)}
                </Shape>'''


def face():
    ex1, ex2, ey, mx, my = 430, 594, 600, 512, 656
    w = '''                <Shape x="{mx}" y="{my}" name="Mouth W" id="{mid}">
                    <PointsPath isClosed="false" name="Path">
                        <StraightVertex x="-42" y="-12"/>
                        <CubicDetachedVertex x="-21" y="20" inRotation="{pi}" inDistance="16" outRotation="0" outDistance="16"/>
                        <StraightVertex x="0" y="-2"/>
                        <CubicDetachedVertex x="21" y="20" inRotation="{pi}" inDistance="16" outRotation="0" outDistance="16"/>
                        <StraightVertex x="42" y="-12"/>
                    </PointsPath>
                    {s}
                </Shape>'''.format(mx=mx, my=my, mid=MOUTH_W, pi=math.pi, s=stroke(26))
    return f'''            <Node x="0" y="0" name="Face" id="{FACE}">
                <Shape x="{ex1}" y="{ey}" name="Eye L" id="{EYE_L}"><Ellipse width="64" height="80" name="Path"/>{fill()}</Shape>
                <Shape x="{ex2}" y="{ey}" name="Eye R" id="{EYE_R}"><Ellipse width="64" height="80" name="Path"/>{fill()}</Shape>
{arc_shape("Happy L", HAPPY_L, ex1, ey + 10, 32, 30, True, 28, 0)}
{arc_shape("Happy R", HAPPY_R, ex2, ey + 10, 32, 30, True, 28, 0)}
{arc_shape("Closed L", CLOSED_L, ex1, ey, 32, 18, False, 26, 0)}
{arc_shape("Closed R", CLOSED_R, ex2, ey, 32, 18, False, 26, 0)}
{w}
                <Shape x="{mx}" y="{my + 6}" opacity="0" name="Mouth Smile" id="{MOUTH_SMILE}">
                    <PointsPath isClosed="true" name="Path">
                        <StraightVertex x="-40" y="-8"/>
                        <CubicDetachedVertex x="0" y="46" inRotation="{math.pi}" inDistance="26" outRotation="0" outDistance="26"/>
                        <StraightVertex x="40" y="-8"/>
                    </PointsPath>
                    {stroke(14)}{fill()}
                </Shape>
                <Shape x="{mx}" y="{my + 4}" opacity="0" name="Mouth Open" id="{MOUTH_OPEN}"><Ellipse width="44" height="56" name="Path"/>{fill()}</Shape>
            </Node>'''

# ---------------------------------------------------------------- 애니메이션


EASE = {
    "io": (0.42, 0, 0.58, 1),     # 천천히 출발, 천천히 도착
    "out": (0.16, 1, 0.3, 1),     # 튀어 올라 감속
    "in": (0.5, 0, 0.84, 0),      # 떨어지며 가속
    "soft": (0.37, 0, 0.63, 1),
}


def kf(value, frame, ease="io"):
    x1, y1, x2, y2 = EASE[ease]
    return (f'<KeyFrameDouble value="{value:.4f}" frame="{frame}" interpolationType="cubic">'
            f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></KeyFrameDouble>')


def keyed(obj, prop_frames):
    """prop_frames: {propertyKey: [(frame, value), ...]}"""
    props = "".join(
        f'<KeyedProperty propertyKey="{k}">' + "".join(kf(k[1], k[0], *k[2:]) for k in frames) + '</KeyedProperty>'
        for k, frames in prop_frames.items())
    return f'<KeyedObject objectId="{obj}">{props}</KeyedObject>'


def char_keys(y, rot):
    """캐릭터 전체(발 가운데 기준): y는 바닥에서 위로 뜬 정도"""
    return keyed(CHAR, {14: [(k[0], 960 + k[1], *k[2:]) for k in y], 15: rot})


def body_keys(timeline):
    """timeline: [(frame, poseName or (poseA, poseB, t))] → 몸 꼭짓점 키"""
    out = []
    for i, vid in enumerate(VERT_IDS):
        frames = {24: [], 25: [], 82: [], 83: []}
        for step in timeline:
            f, pose = step[0], step[1]
            ease = step[2] if len(step) > 2 else "io"
            x, y, r, d = POSE[pose][i]
            frames[24].append((f, x, ease))
            frames[25].append((f, y, ease))
            frames[82].append((f, r, ease))
            frames[83].append((f, d, ease))
        # 회전은 -π~π 경계에서 튀지 않게 이어 준다
        rs = frames[82]
        for j in range(1, len(rs)):
            prev = rs[j - 1][1]
            v = rs[j][1]
            while v - prev > math.pi:
                v -= 2 * math.pi
            while v - prev < -math.pi:
                v += 2 * math.pi
            rs[j] = (rs[j][0], v, rs[j][2])
        out.append(keyed(vid, frames))
    return "".join(out)


FACE_PARTS = [EYE_L, EYE_R, HAPPY_L, HAPPY_R, CLOSED_L, CLOSED_R, MOUTH_W, MOUTH_SMILE, MOUTH_OPEN]


def face_set(visible, last):
    """표정: 보일 부위만 opacity 1"""
    return "".join(keyed(p, {18: [(0, 1 if p in visible else 0), (last, 1 if p in visible else 0)]}) for p in FACE_PARTS)


NORMAL = [EYE_L, EYE_R, MOUTH_W]


def animations():
    anims = []

    # 0 기본: 몽글몽글 숨쉬기(손도 살짝) + 깜빡임 (2.4초)
    d = 144
    a = body_keys([(0, "base", "soft"), (72, "breathe", "soft"), (d, "base")])
    a += keyed(FACE, {14: [(0, 0, "soft"), (72, 7, "soft"), (d, 0)]})
    a += char_keys([(0, 0), (d, 0)], [(0, 0), (d, 0)])
    a += face_set(NORMAL, d)
    blink = [(0, 1), (112, 1, "in"), (116, 0.1, "out"), (122, 1), (d, 1)]
    a += keyed(EYE_L, {17: blink})
    a += keyed(EYE_R, {17: blink})
    anims.append(("Idle", d, a, "loop"))

    # 1 완료: 웅크림 → 쭉 늘며 점프 → 납작 착지 → 출렁출렁 (1.3초)
    d = 78
    a = body_keys([(0, "base"), (10, "squash", "out"), (18, "stretch", "out"), (30, "wobble2", "in"),
                   (40, "stretch", "in"), (46, "squash", "out"), (56, "wobble", "io"), (64, "wobble2", "io"),
                   (71, "base"), (d, "base")])
    a += char_keys([(0, 0), (10, 0, "out"), (30, -130, "in"), (46, 0), (d, 0)], [(0, 0), (d, 0)])
    a += keyed(FACE, {14: [(0, 0), (10, 18, "out"), (18, -14), (30, -4, "in"), (46, 20, "out"), (56, -6), (64, 4), (71, 0), (d, 0)]})
    a += face_set([HAPPY_L, HAPPY_R, MOUTH_SMILE], d)
    anims.append(("Hop", d, a, "loop"))

    # 2 전부 완료: 두 팔 들고 통통 (0.9초 반복)
    d = 54
    a = body_keys([(0, "cheer"), (10, "cheerSquash", "out"), (20, "cheerStretch", "out"), (32, "cheer", "in"),
                   (40, "cheerSquash", "out"), (48, "cheer"), (d, "cheer")])
    a += char_keys([(0, 0), (10, 0, "out"), (26, -80, "in"), (40, 0), (d, 0)], [(0, 0), (d, 0)])
    a += keyed(FACE, {14: [(0, 0), (10, 12, "out"), (24, -8, "in"), (40, 12, "out"), (48, 0), (d, 0)]})
    a += face_set([HAPPY_L, HAPPY_R, MOUTH_SMILE], d)
    anims.append(("Cheer", d, a, "loop"))

    # 3 일정 없음: 퍼질러 앉아 갸웃 갸웃 (3초)
    d = 180
    t = 0.1
    a = body_keys([(0, "sit", "soft"), (90, "sitBreathe", "soft"), (d, "sit")])
    a += char_keys([(0, 0), (d, 0)], [(0, 0), (30, -t), (70, -t), (100, t * 0.6), (150, t * 0.6), (d, 0)])
    a += keyed(FACE, {14: [(0, 30, "soft"), (90, 36, "soft"), (d, 30)]})
    a += face_set(NORMAL, d)
    blink = [(0, 1), (130, 1, "in"), (134, 0.1, "out"), (140, 1), (d, 1)]
    a += keyed(EYE_L, {17: blink})
    a += keyed(EYE_R, {17: blink})
    anims.append(("Wonder", d, a, "loop"))

    # 4 휴식: 퍼진 채 졸며 천천히 숨쉬기 (3.6초)
    d = 216
    a = body_keys([(0, "sit", "soft"), (108, "sitBreathe", "soft"), (d, "sit")])
    a += char_keys([(0, 0, "soft"), (108, 6, "soft"), (d, 0)], [(0, 0, "soft"), (108, 0.05, "soft"), (d, 0)])
    a += keyed(FACE, {14: [(0, 34, "soft"), (108, 44, "soft"), (d, 34)]})
    a += face_set([CLOSED_L, CLOSED_R, MOUTH_OPEN], d)
    a += keyed(MOUTH_OPEN, {17: [(0, 0.6, "soft"), (108, 1.1, "soft"), (d, 0.6)]})
    anims.append(("Sleepy", d, a, "loop"))
    return anims


def state_machine(anims):
    ids = [f"0:{60 + i}" for i in range(len(anims))]
    states = []
    for i, sid in enumerate(ids):
        trans = ""
        for j, tid in enumerate(ids):
            if i == j:
                continue
            trans += f'''
                    <StateTransition stateToId="{tid}" duration="200">
                        <TransitionViewModelCondition opValue="equal">
                            <TransitionPropertyViewModelComparator>
                                <BindablePropertyNumber><DataBindContext sourcePathIds="{VM}-{VM_MOOD}" propertyKey="636"/></BindablePropertyNumber>
                            </TransitionPropertyViewModelComparator>
                            <TransitionValueNumberComparator value="{j}"/>
                        </TransitionViewModelCondition>
                    </StateTransition>'''
        states.append(f'                <AnimationState x="{160 + i * 200}" y="0" animationId="{anims[i][3]}" id="{sid}">{trans}\n                </AnimationState>')
    return f'''        <StateMachine name="Momuri" id="0:7">
            <StateMachineLayer name="Mood" id="0:8">
                <AnyState x="160" y="-160"/>
                <ExitState x="560" y="-160"/>
                <EntryState x="-80" y="0"><StateTransition stateToId="{ids[0]}"/></EntryState>
{chr(10).join(states)}
            </StateMachineLayer>
        </StateMachine>'''


def build():
    raw = animations()
    anims = [(name, d, body, loop, f"0:{80 + i}") for i, (name, d, body, loop) in enumerate(raw)]
    sm = state_machine([(n, d, b, aid) for n, d, b, _, aid in anims])
    la = "\n".join(f'        <LinearAnimation loopValue="{loop}" fps="{FPS}" duration="{d}" name="{n}" id="{aid}">{b}</LinearAnimation>'
                   for n, d, b, loop, aid in anims)
    return f'''<Rive version="1" kind="fragment">
    <Artboard defaultStateMachineId="0:7" viewModelId="{VM}" viewModelInstanceId="{VM_INST}" styleId="0:5" width="1024" height="1024" name="Momuri" id="0:2">
        <LayoutComponentStyle name="Artboard Style" id="0:5"/>
        <Node x="512" y="960" name="Character" id="{CHAR}">
          <Node x="-512" y="-960" name="Pivot" id="0:19">
{face()}
{body_shape()}
          </Node>
        </Node>
{sm}
{la}
    </Artboard>
    <ViewModel defaultInstanceId="{VM_INST}" name="Momuri" id="{VM}">
        <ViewModelPropertyNumber name="mood" id="{VM_MOOD}"/>
        <ViewModelInstance exports="true" name="Default" id="{VM_INST}">
            <ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="{VM_MOOD}"/>
        </ViewModelInstance>
    </ViewModel>
</Rive>
'''


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "rive", "momuri", "scene.rml")
    open(out, "w").write(build())
    print("wrote", out)
