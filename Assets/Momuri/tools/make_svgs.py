"""모무리 자세 SVG 생성기.

몸·팔·다리를 따로 그리지 않고, 원 몇 개를 메타볼(액체처럼 녹아 붙는 덩어리)로 합친 뒤
그 윤곽을 매끈한 외곽선 하나로 만든다. 메타몽처럼 팔다리가 몸에서 솟아난 모양이 된다.
Rive에서는 이 외곽선 하나에 뼈대를 심어 늘이고 줄여 움직인다.

사용: python3 tools/make_svgs.py  → source/*.svg
"""
import math

STEP = 4          # 윤곽 계산 격자 간격(px)
SIZE = 1024


REACH = 1.35     # 원 반지름의 몇 배까지 영향을 주는지 (클수록 더 많이 녹아 붙음)
THRESHOLD = (1 - (1 / REACH) ** 2) ** 2   # 혼자 있는 원은 정확히 제 반지름에서 윤곽이 생긴다


def field(x, y, balls):
    """가까운 원끼리만 녹아 붙는 메타볼 (영향 범위가 유한한 커널)."""
    total = 0.0
    for cx, cy, r in balls:
        q = ((x - cx) ** 2 + (y - cy) ** 2) / (r * REACH) ** 2
        if q < 1:
            total += (1 - q) ** 2
    return total


def contour(balls, threshold=THRESHOLD):
    """마칭 스퀘어로 field == threshold 인 윤곽선(가장 긴 고리)을 구한다."""
    n = SIZE // STEP + 1
    v = [[field(i * STEP, j * STEP, balls) - threshold for i in range(n)] for j in range(n)]

    def interp(p1, p2, a, b):
        t = a / (a - b)
        return (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t)

    segs = []
    for j in range(n - 1):
        for i in range(n - 1):
            c = [(i * STEP, j * STEP), ((i + 1) * STEP, j * STEP), ((i + 1) * STEP, (j + 1) * STEP), (i * STEP, (j + 1) * STEP)]
            val = [v[j][i], v[j][i + 1], v[j + 1][i + 1], v[j + 1][i]]
            pts = []
            for k in range(4):
                a, b = val[k], val[(k + 1) % 4]
                if (a > 0) != (b > 0):
                    pts.append(interp(c[k], c[(k + 1) % 4], a, b))
            if len(pts) == 2:
                segs.append((pts[0], pts[1]))
            elif len(pts) == 4:
                segs.append((pts[0], pts[1]))
                segs.append((pts[2], pts[3]))

    # 선분들을 이어 고리로
    def key(p):
        return (round(p[0], 2), round(p[1], 2))

    adj = {}
    for a, b in segs:
        adj.setdefault(key(a), []).append(key(b))
        adj.setdefault(key(b), []).append(key(a))
    seen, loops = set(), []
    for start in list(adj):
        if start in seen:
            continue
        loop, prev, cur = [start], None, start
        seen.add(start)
        while True:
            nxt = [p for p in adj[cur] if p != prev and p not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        loops.append(loop)
    return max(loops, key=len)


def smooth_path(points, every=4):
    """점을 솎아낸 뒤 Catmull-Rom 곡선을 베지어로 바꿔 매끈한 닫힌 경로를 만든다."""
    p = points[::every]
    n = len(p)
    d = f"M{p[0][0]:.1f} {p[0][1]:.1f} "
    for i in range(n):
        p0, p1, p2, p3 = p[(i - 1) % n], p[i], p[(i + 1) % n], p[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f} "
    return d + "Z"


def svg(title, balls, face, back="", front=""):
    body = smooth_path(contour(balls))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <!-- {title}. 팔다리가 몸과 한 덩어리인 외곽선(body) 하나 + 얼굴·소품 레이어 -->
  <g id="momuri" stroke="#000" stroke-width="30" stroke-linecap="round" stroke-linejoin="round" fill="#fff">
{back}    <g id="body"><path d="{body}"/></g>
{front}{face}  </g>
</svg>
'''


def face(ex1, ey1, ex2, ey2, mx, my, eyes="open", mouth="default", tilt=0):
    t = f' transform="rotate({tilt} {(ex1 + ex2) / 2} {ey1})"' if tilt else ""
    if eyes == "open":
        e = (f'    <g id="eye_L_open" stroke="none" fill="#000"><ellipse cx="{ex1}" cy="{ey1}" rx="32" ry="40"/></g>\n'
             f'    <g id="eye_R_open" stroke="none" fill="#000"><ellipse cx="{ex2}" cy="{ey2}" rx="32" ry="40"/></g>\n')
    elif eyes == "happy":
        e = (f'    <g id="eye_L_happy" fill="none"><path d="M{ex1-32} {ey1+16} Q {ex1} {ey1-30} {ex1+32} {ey1+16}" stroke-width="22"/></g>\n'
             f'    <g id="eye_R_happy" fill="none"><path d="M{ex2-32} {ey2+16} Q {ex2} {ey2-30} {ex2+32} {ey2+16}" stroke-width="22"/></g>\n')
    else:
        e = (f'    <g id="eye_L_closed" fill="none"><path d="M{ex1-32} {ey1} Q {ex1} {ey1+22} {ex1+32} {ey1}" stroke-width="20"/></g>\n'
             f'    <g id="eye_R_closed" fill="none"><path d="M{ex2-32} {ey2} Q {ex2} {ey2+22} {ex2+32} {ey2}" stroke-width="20"/></g>\n')
    if mouth == "default":
        m = f'    <g id="mouth_default" fill="none"><path d="M{mx-42} {my-12} Q {mx-44} {my+20} {mx-21} {my+20} Q {mx} {my+20} {mx} {my-2} Q {mx} {my+20} {mx+21} {my+20} Q {mx+44} {my+20} {mx+42} {my-12}" stroke-width="20"/></g>\n'
    elif mouth == "smile":
        m = f'    <g id="mouth_smile"><path d="M{mx-40} {my-8} Q {mx} {my+54} {mx+40} {my-8} Z" fill="#000" stroke-width="14"/></g>\n'
    else:
        m = f'    <g id="mouth_open" stroke="none" fill="#000"><ellipse cx="{mx}" cy="{my}" rx="22" ry="28"/></g>\n'
    return f'    <g id="face"{t}>\n{e}{m}    </g>\n'


poses = {}

# 1. 기본: 종이에 체크하는 자세 (로고와 같은 구도)
paper = '''    <g id="paper"><path d="M236 690 L 748 650 L 718 900 L 160 886 Z"/></g>
    <g id="checkbox_1"><path d="M304 704 L 354 700 L 350 746 L 300 750 Z" stroke-width="13"/></g>
    <g id="check_1" fill="none"><path d="M314 720 L 330 738 L 370 696" stroke-width="13"/></g>
    <g id="line_1" fill="none"><path d="M390 732 L 620 722" stroke-width="17"/></g>
    <g id="checkbox_2"><path d="M266 782 L 316 778 L 312 824 L 262 828 Z" stroke-width="13"/></g>
    <g id="line_2" fill="none"><path d="M350 808 L 580 800" stroke-width="17"/></g>
'''
hands = '''    <g id="pen"><path d="M210 430 L 246 416 L 338 640 L 320 676 L 304 650 Z" fill="#000" stroke-width="13"/></g>
'''
effect = '''    <g id="effect" fill="none"><path d="M150 266 L 180 320" stroke-width="20"/><path d="M92 354 L 146 388" stroke-width="20"/></g>
'''
# 몸 덩어리 + 펜 쥔 손(왼쪽) + 종이 누르는 손(오른쪽)이 모두 한 외곽선
poses["momuri"] = svg("기본 자세", [(560, 470, 210), (500, 600, 200), (700, 600, 150), (250, 600, 78), (680, 720, 86)],
                      face(470, 500, 650, 530, 560, 572), back="", front=paper + hands + effect)

# 2. 앉기: 고개 갸웃 (오늘 일정 없음)
q = '''    <g id="effect" fill="none"><path d="M806 236 Q 836 186 876 216 Q 896 246 862 270 Q 842 284 846 308" stroke-width="18"/><circle cx="848" cy="350" r="6" fill="#000" stroke-width="10"/></g>
'''
poses["momuri-sit"] = svg("앉기", [(512, 580, 250), (512, 650, 240), (270, 690, 72), (754, 690, 72), (400, 840, 70), (624, 840, 70)],
                          face(430, 600, 594, 600, 512, 656, tilt=-8), front=q)

# 3. 두 팔 들기: 통통 (전부 완료)
cheer_fx = '''    <g id="effect" fill="none"><path d="M110 290 L 146 334" stroke-width="20"/><path d="M70 390 L 120 406" stroke-width="20"/><path d="M914 290 L 878 334" stroke-width="20"/><path d="M954 390 L 904 406" stroke-width="20"/></g>
    <g id="shadow" fill="none" opacity="0.3"><path d="M380 950 L 644 950" stroke-width="16"/></g>
'''
poses["momuri-cheer"] = svg("두 팔 들기", [(512, 600, 250), (512, 670, 230), (290, 560, 62), (210, 470, 62), (734, 560, 62), (814, 470, 62), (420, 860, 58), (604, 860, 58)],
                            face(432, 620, 592, 620, 512, 672, eyes="happy", mouth="smile"), front=cheer_fx)

# 4. 옆모습 (오른쪽을 봄)
poses["momuri-side"] = svg("옆모습", [(500, 590, 250), (540, 670, 230), (740, 710, 70), (420, 860, 62), (600, 866, 62)],
                           face(672, 596, 672, 596, 712, 690).replace('    <g id="eye_R_open"', '    <g id="eye_R_hidden" opacity="0"'))

# 5. 졸림 표정 (기본 자세 + 감은 눈·하품)
poses["momuri-sleepy"] = svg("졸림", [(512, 580, 250), (512, 650, 240), (270, 690, 72), (754, 690, 72), (400, 840, 70), (624, 840, 70)],
                             face(430, 610, 594, 610, 512, 670, eyes="closed", mouth="open"),
                             front='    <g id="effect" fill="none" opacity="0.6"><path d="M760 300 L 820 300 L 760 360 L 820 360" stroke-width="14"/><path d="M850 220 L 890 220 L 850 260 L 890 260" stroke-width="11"/></g>\n')

for name, s in poses.items():
    open(f"source/{name}.svg", "w").write(s)
print("ok", list(poses))
