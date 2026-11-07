"""MAZ 캐릭터 v4: 컨셉 인물 측정값 기준.
컨셉 인물 = 격자 없는 '그린 픽셀'. 4배 슈퍼샘플로 형태를 그린 뒤 면적 평균으로 줄여 부드러운 가장자리를 만든다.
기준(컨셉 원본 px): 키 46, 어깨 폭 19, 머리 폭 6, 코트 자락 무릎(키의 78%), 다리 노출 약 10, 몸 명도 0~45/255, 투구 하이라이트 220+."""
from PIL import Image
import numpy as np, math

W, H = 56, 64
FOOT, CX = 60.0, 28.0
BASE_CX = CX
TWIST = {'r': 0.0, 'sr': 0.0}            # 상체 회전(도, +=칼 든 어깨가 앞으로), 칼 어깨 높이

def shoulder(d, side, bw, sh, cx=None, r=None, sr=None):
    """몸통 회전을 반영한 어깨 위치. side: 화면 좌우(-1/1). E에서는 -1=칼(가까운) 1=방패(먼)"""
    cx = CX if cx is None else cx; r = math.radians(TWIST['r'] if r is None else r); sr = TWIST['sr'] if sr is None else sr
    if d == 'E':
        if side < 0: return cx - .4 + 3.0 * math.sin(r), sh + 2.4 + sr
        return cx + 1.0 - 2.0 * math.sin(r), sh + 2.3 - sr * .4
    sword = 1 if d == 'S' else -1
    x = cx + side * (7.0 + bw) * (.72 + .28 * math.cos(r))
    return x, sh + 2.3 + (sr if side == sword else -sr * .4)
SS = 4
LIGHT = np.array([-0.35, -0.75, 0.56]); LIGHT /= np.linalg.norm(LIGHT)

def c(h): return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float)
# (그늘색, 기본색, 밝은색, 반사광)
MAT = {
    'coat':   (c('#070606'), c('#100e0d'), c('#28231f'), 0.03),
    'chest':  (c('#141210'), c('#2a2623'), c('#4c4540'), 0.10),
    'mail':   (c('#0e0e0f'), c('#24242a'), c('#4a4a4c'), 0.25),
    'leg':    (c('#070606'), c('#0f0e0d'), c('#221e1b'), 0.00),
    'boot':   (c('#060505'), c('#0e0c0b'), c('#1d1915'), 0.05),
    'helm':   (c('#2a2a2b'), c('#6a6866'), c('#c9c5bc'), 0.9),
    'skin':   (c('#3a2c24'), c('#6a5546'), c('#a89080'), 0.10),
    'hood':   (c('#080707'), c('#121010'), c('#2c2723'), 0.02),
    'hair':   (c('#090807'), c('#151210'), c('#2a2420'), 0.02),
    'wood':   (c('#060505'), c('#0e0c0b'), c('#2a2420'), 0.10),
    'belt':   (c('#0a0807'), c('#1a1410'), c('#33271e'), 0.10),
    'robe':   (c('#080707'), c('#131110'), c('#2c2825'), 0.02),
    'iron':   (c('#101012'), c('#3a3a3c'), c('#9a978f'), 0.6),
    'hand':   (c('#2a201a'), c('#4a3a30'), c('#7a6555'), 0.05),
}

EDGE_MIX = .35
SAT = 1.0
# 아트 바이블 도트 밀도: 최소 도트 2px(1px 체크무늬 금지), 재질 덩어리 4~10px, 잔결 대비 약 21(인물)
DOT2 = True
RIM_K, RIM_B = 1.7, 26       # 윗선 반사광(컨셉 어깨·머리 윗선)
RIM_SK, RIM_SB = 1.25, 8     # 옆선은 약하게
DOT_K = 2.0      # 형태 대비 증폭(σ2 흐림 대비 잔결)
DOT_GRAIN = 1.6  # 2px 알갱이 세기
DOT_CLUMP = 1.6  # 4~10px 덩어리 세기
def _gblur(x, sg):
    k = int(3 * sg + .5); t = np.arange(-k, k + 1); g = np.exp(-t * t / (2 * sg * sg)); g /= g.sum()
    p = np.pad(x, ((k, k), (k, k)) + ((0, 0),) * (x.ndim - 2), mode='edge')
    y = sum(g[i] * p[i:i + x.shape[0]] for i in range(2 * k + 1))
    return sum(g[i] * y[:, i:i + x.shape[1]] for i in range(2 * k + 1))
def dot2(rgb, a, seed):
    op = (a > .5).astype(float)
    w = _gblur(op, 2.0); low = _gblur(rgb * op[..., None], 2.0) / np.maximum(w, 1e-6)[..., None]
    dl = (rgb - low).mean(-1, keepdims=True)                          # 형태(주름·경계·밝은 윗면) 명도 대비만 키움(색은 그대로)
    rgb = rgb + dl * (DOT_K - 1) * (1 - (rgb.mean(-1, keepdims=True) / 140).clip(0, 1))
    h2, w2 = (rgb.shape[0] + 1) // 2, (rgb.shape[1] + 1) // 2
    rng = np.random.default_rng(int(seed))
    g = rng.normal(0, 1, (h2, w2)); c = _gblur(rng.normal(0, 1, (h2, w2)), 1.6); c /= c.std() + 1e-6
    n = np.kron(DOT_GRAIN * g + DOT_CLUMP * c, np.ones((2, 2)))[:rgb.shape[0], :rgb.shape[1]]
    pw = op.reshape(rgb.shape[0] // 2, 2, rgb.shape[1] // 2, 2) if rgb.shape[0] % 2 == 0 and rgb.shape[1] % 2 == 0 else None
    blk = (rgb * op[..., None]).reshape(rgb.shape[0] // 2, 2, rgb.shape[1] // 2, 2, 3).sum((1, 3)) / np.maximum(pw.sum((1, 3)), 1e-6)[..., None]
    blk = np.kron(blk, np.ones((2, 2, 1)))
    full = np.kron(pw.min((1, 3)), np.ones((2, 2))) > .5               # 2x2 칸이 모두 몸 안이면 2px 도트로
    rgb = np.where(full[..., None], blk, rgb)
    f = (.6 + rgb.mean(-1, keepdims=True) / 60).clip(.6, 1.6)          # 어두운 곳은 알갱이 약하게
    return (rgb + n[..., None] * f * (op[..., None] > 0)).clip(0, 255)
class Canvas:
    def __init__(s):
        s.rgb = np.zeros((H * SS, W * SS, 3)); s.a = np.zeros((H * SS, W * SS))
        ys, xs = np.mgrid[0:H * SS, 0:W * SS]
        s.X = (xs + .5) / SS; s.Y = (ys + .5) / SS; s.seed = 7

    def paint(s, mask, nx, ny, nz, mat, gain=1.0):
        dk, base, lt, spec = MAT[mat]
        d = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
        t = d * gain
        col = np.where((t < .5)[..., None], dk + (base - dk) * (t / .5)[..., None], base + (lt - base) * ((t - .5) / .5).clip(0, 1)[..., None])
        if spec:
            hl = (d ** 18 * spec)[..., None]
            col = col + (np.array([235, 230, 220]) - col) * hl
        s.rgb[mask] = col[mask]; s.a[mask] = 1

    def capsule(s, x0, y0, x1, y1, r0, r1, mat, gain=1.0, clip=None):
        dx, dy = x1 - x0, y1 - y0; ll = dx * dx + dy * dy or 1e-6
        t = (((s.X - x0) * dx + (s.Y - y0) * dy) / ll).clip(0, 1)
        r = r0 + (r1 - r0) * t
        ex, ey = s.X - (x0 + dx * t), s.Y - (y0 + dy * t)
        dist = np.hypot(ex, ey); u = (dist / r)
        m = u <= 1
        if clip is not None: m &= clip(s.X, s.Y)
        nz = np.sqrt((1 - u ** 2).clip(0)); k = np.where(dist > 1e-6, u / np.maximum(dist, 1e-6), 0)
        s.paint(m, ex * k, ey * k, nz, mat, gain)

    def ell(s, cx, cy, rx, ry, mat, gain=1.0, clip=None):
        ex, ey = (s.X - cx) / rx, (s.Y - cy) / ry; u = np.hypot(ex, ey)
        m = u <= 1
        if clip is not None: m &= clip(s.X, s.Y)
        s.paint(m, ex, ey, np.sqrt((1 - u ** 2).clip(0)), mat, gain)

    def trap(s, cx, y0, y1, w0, w1, mat, gain=1.0, skew=0.0, round_hem=1.2):
        t = ((s.Y - y0) / (y1 - y0))
        hw = w0 + (w1 - w0) * t.clip(0, 1); ccx = cx + skew * t.clip(0, 1)
        u = (s.X - ccx) / hw
        hem = y1 - round_hem * (u ** 2)          # 아래 자락이 둥글게
        m = (np.abs(u) <= 1) & (s.Y >= y0) & (s.Y <= hem)
        s.paint(m, u * .9, np.full_like(u, .1), np.sqrt((1 - u ** 2).clip(0)), mat, gain)

    def stick(s, x0, y0, x1, y1, wdt, mat, gain=1.0):
        s.capsule(x0, y0, x1, y1, wdt, wdt, mat, gain)

    def image(s):
        a = s.a.reshape(H, SS, W, SS).mean((1, 3))
        rgb = (s.rgb * s.a[..., None]).reshape(H, SS, W, SS, 3).sum((1, 3)) / np.maximum(s.a.reshape(H, SS, W, SS).sum((1, 3)), 1e-6)[..., None]
        rgb = dot2(rgb, a, s.seed)
        # 윗면·외곽 반사광(컨셉의 어깨·팔 윗선 하이라이트)
        op = a > .5
        up = np.zeros_like(op); up[1:] = ~op[:-1]; up[0] = True
        lf = np.zeros_like(op); lf[:, 1:] = ~op[:, :-1]
        rt = np.zeros_like(op); rt[:, :-1] = ~op[:, 1:]
        pass                                                           # 반사광은 2px 도트화 뒤(아래)에서
        # 경계 흐림: 알파·색을 3x3 가우시안으로 살짝 번지게(안쪽은 원본 유지)
        k = np.array([1, 2, 1], float); k = np.outer(k, k); k /= k.sum()
        def blur(m):
            p = np.pad(m, ((1, 1), (1, 1)) + ((0, 0),) * (m.ndim - 2), mode='edge' if m.ndim == 2 else 'constant')
            return sum(k[j, i] * p[j:j + H, i:i + W] for j in range(3) for i in range(3))
        ab = blur(a); pm = blur(rgb * a[..., None])
        rgbb = pm / np.maximum(ab, 1e-6)[..., None]
        edge = (ab > .02) & (ab < .98) | ((a > 0) & (a < 1))
        mix = np.where(edge, EDGE_MIX, 0.0)
        a = a * (1 - mix) + ab * mix
        rgb = np.where(edge[..., None], rgb * (1 - mix[..., None]) + rgbb * mix[..., None], rgb)
        lum = rgb.mean(-1, keepdims=True); rgb = lum + (rgb - lum) * SAT
        if DOT2:                                                       # 컨셉처럼 2px 도트: 색·알파 모두 2x2 칸 단위
            hh, ww = H // 2 * 2, W // 2 * 2
            aa = a[:hh, :ww].reshape(hh // 2, 2, ww // 2, 2); cc = (rgb[:hh, :ww] * a[:hh, :ww, None]).reshape(hh // 2, 2, ww // 2, 2, 3)
            ab2 = aa.mean((1, 3)); cb2 = cc.sum((1, 3)) / np.maximum(aa.sum((1, 3)), 1e-6)[..., None]
            a = a.copy(); rgb = rgb.copy()
            a[:hh, :ww] = np.kron(ab2, np.ones((2, 2))); rgb[:hh, :ww] = np.kron(cb2, np.ones((2, 2, 1)))
            # 윗선·옆선 반사광을 2px 도트 단위로(컨셉: 어깨·머리 윗선이 한 도트 굵기로 밝음)
            op2 = ab2 > .5
            up2 = np.zeros_like(op2); up2[1:] = ~op2[:-1]; up2[0] = True
            lf2 = np.zeros_like(op2); lf2[:, 1:] = ~op2[:, :-1]
            rt2 = np.zeros_like(op2); rt2[:, :-1] = ~op2[:, 1:]
            yy = np.arange(hh // 2)[:, None] * 2
            ru = op2 & up2; rs = op2 & ~up2 & ((lf2 & (yy < FOOT - 14)) | (rt2 & (yy < FOOT - 30)))
            c2 = rgb[:hh, :ww].reshape(hh // 2, 2, ww // 2, 2, 3)[:, 0, :, 0]
            c2 = np.where(ru[..., None], c2 * RIM_K + RIM_B, c2); c2 = np.where(rs[..., None], c2 * RIM_SK + RIM_SB, c2)
            rgb[:hh, :ww] = np.kron(c2, np.ones((2, 2, 1)))
        out = np.dstack([rgb.clip(0, 255), (a * 255)]).astype(np.uint8)
        return Image.fromarray(out, 'RGBA')

    def band(s, x0, x1, y, th, mat, gain=1.0, clip=None):
        m = (s.X >= x0) & (s.X <= x1) & (np.abs(s.Y - y) <= th / 2)
        if clip is not None: m &= clip(s.X, s.Y)
        s.paint(m, np.zeros_like(s.X), np.full_like(s.X, -.3), np.full_like(s.X, .95), mat, gain)

# ------------------------------------------------------------------ 인물
def figure(sp, d, ph, walking, atk=None):
    global CX
    P = atk if isinstance(atk, dict) else (atk_body(atk, d) if atk is not None else ZERO_POSE)
    CX = BASE_CX + P['lean']               # 상체 기울임: 상체 그리는 동안 중심선 이동
    TWIST['r'] = P.get('tw', 0.0); TWIST['sr'] = P.get('sr', 0.0)
    try: return _figure(sp, d, ph, walking, atk, P)
    finally: CX = BASE_CX; TWIST['r'] = TWIST['sr'] = 0.0

def _leg(cv, hx, hy, fx, fy, knee, k=1.0):
    mx, my = (hx + fx) / 2 + knee, (hy + fy) / 2
    cv.capsule(hx, hy, mx, my, 2.3, 1.6, 'leg', k)
    cv.capsule(mx, my, fx, fy, 1.6, 0.9, 'leg', k)

def _figure(sp, d, ph, walking, atk, P):
    cv = Canvas()
    th = atk if isinstance(atk, dict) else (atk_pose(atk, d)[0] if atk is not None else 0)
    abob = P['drop']
    s = math.sin(2 * math.pi * ph); co = math.cos(2 * math.pi * ph)
    bob = (-.6 * abs(math.sin(2 * math.pi * ph))) if walking else .25 * math.sin(2 * math.pi * ph) * 0
    br = .3 * math.sin(2 * math.pi * ph) if not walking else 0
    bob += abob
    top = FOOT - 46 + bob                # 머리 꼭대기
    hy = top + 3.4                       # 머리 중심
    sh = top + 9.0 + br * .4             # 어깨선
    wa = top + 22.0                      # 허리
    hem = top + sp.get('hem', 36.0)      # 자락 끝(무릎)
    bw = sp.get('build', 0.0)
    coat = sp.get('coat', 'coat')

    if d in 'SN':
        front = d == 'S'
        if not front: back_gear(cv, sp, d, sh, wa, top)
        if atk is not None and not front: atk_arm(cv, sp, d, th, sh, wa, -1, coat)
        # 다리
        for side in (-1, 1):
            lift = max(0, 2.2 * (s if side < 0 else -s)) if walking else 0
            fx = BASE_CX + side * 2.4 + P['f'][side]
            _leg(cv, BASE_CX + side * 2.3 + P['lean'] * .45, wa + 8, fx, FOOT - 1.6 - lift, side * P['drop'] * .45)
            cv.ell(fx, FOOT - 1.0 - lift, 1.5, 1.0, 'boot')
        if front and sp.get('quiver'): cv.capsule(CX + 6.5, sh - 4, CX + 4, sh + 4, 1.3, 1.3, 'belt', .8)
        # 코트 자락
        cv.trap(CX, wa - 1, hem, 6.4 + bw, sp.get('flare', 7.8) + bw, coat, skew=-P['lean'] * .5)
        # 몸통(넓은 누비 상의)
        rr = math.radians(TWIST['r']); tsc = .8 + .2 * math.cos(rr); sw_ = 1 if front else -1
        cv.capsule(CX, sh + 2 + TWIST['sr'] * .3, CX, wa, (7.6 + bw) * tsc, 6.3 + bw, coat)
        if sp.get('chest'):
            cv.ell(CX + math.sin(rr) * 2.5 * sw_, sh + 6.5, (4.6 + bw * .5) * tsc, 6.0, sp['chest'], .95)
            for yy in (sh + 4.0, sh + 6.5, sh + 9.0):
                cv.band(CX - 4.2, CX + 4.2, yy, .45, 'coat', .3, clip=lambda X, Y: np.hypot((X - CX) / 4.6, (Y - sh - 6.5) / 6.0) < .95)
        if front and sp.get('tabard', True):
            cv.trap(CX, wa + .8, hem - .6, 2.6, 3.4, sp.get('tabmat', 'chest'), .75, round_hem=.4)
            cv.band(CX - .25, CX + .25, (wa + hem) / 2, hem - wa - 2, 'coat', .2)
        if sp.get('mailcoif'):
            cv.ell(CX, sh + .5, 5.0, 2.2, 'mail', 1.0)
        cv.trap(CX, wa - .6, wa + .7, 6.4 + bw, 6.4 + bw, 'belt', .8, round_hem=0)
        if front and sp.get('buckle', True): cv.ell(CX - .5, wa, .8, .7, 'iron', 1.0)
        # 팔(넓은 소매, 몸에 붙음)
        for side in (-1, 1):
            if atk is not None and side == (1 if front else -1): continue
            a = (s * (1 if side < 0 else -1)) * 1.2 if walking else 0
            hx = CX + side * (8.3 + bw); hy2 = wa + 3.5
            if atk is not None: hx += P['sh'][0]; hy2 += P['sh'][1]
            if atk is not None:                  # 방패 팔: 팔꿈치를 굽혀 방패를 받침
                s0x, s0y = shoulder(d, side, bw, sh)
                elx, ely = (s0x + hx) / 2 + side * 2.2, (s0y + hy2) / 2 + 1.0
                cv.capsule(s0x, s0y, elx, ely, 2.9, 2.3, coat, .95); cv.ell(elx, ely, 2.2, 2.2, coat, .9)
                cv.capsule(elx, ely, hx, hy2 - .5, 2.2, 1.7, coat, .95)
            else: cv.capsule(CX + side * (7.0 + bw), sh + 2.3, hx, hy2 - 1.5 + a * .3, 2.9, 2.4, coat, .95)
            cv.ell(hx + side * .1, hy2 + a * .3, 1.2, 1.3, 'hand' if front else coat, .9 if front else .6)
        # 어깨 둥근 덩어리
        for side in (-1, 1):
            cv.ell(shoulder(d, side, bw, sh)[0] - side * .7, shoulder(d, side, bw, sh)[1] - .1, 3.4, 2.8, coat, 1.05)
        head(cv, sp, d, hy, top)
        if front: front_gear(cv, sp, d, sh, wa, top)
        if front and sp.get('shield'): shield(cv, CX - 9.0 - bw + P['sh'][0], wa + 1.0 + P['sh'][1], 3.6, 4.0)
        if atk is not None and front: atk_arm(cv, sp, d, th, sh, wa, 1, coat)
    else:
        near = s if walking else 0
        far_first = [(1, .6), (-1, 1.0)]
        for side, k in far_first:
            step = (near if side < 0 else -near) * 3.8
            lift = max(0, 2.0 * (co if side < 0 else -co)) if walking else 0
            fx = BASE_CX + step + (0 if walking else (1.0 if side < 0 else -1.0)) + P['f'][side]
            _leg(cv, BASE_CX - .3 + P['lean'] * .45, wa + 8, fx, FOOT - 1.6 - lift, (P['drop'] * 1.0 if side < 0 else P['drop'] * .3), k)
            cv.ell(fx + .8, FOOT - 1.0 - lift, 1.9, 1.0, 'boot', k)
        a = -near * 2.2
        if atk is not None:
            hx_, hy_ = CX + 4.0 + P['sh'][0], sh + 7.5 + P['sh'][1]
            elx, ely = (shoulder('E', 1, bw, sh)[0] + hx_) / 2 - 1.5, (sh + 2.3 + hy_) / 2 + 2.0
            s1x, s1y = shoulder('E', 1, bw, sh)
            cv.capsule(s1x, s1y, elx, ely, 2.6, 2.1, coat, .55); cv.capsule(elx, ely, hx_, hy_, 2.1, 1.7, coat, .55)
        else: cv.capsule(CX + 1.0, sh + 2.3, CX + 1.0 + a, wa + 2.5, 2.6, 2.2, coat, .55)
        back_gear(cv, sp, 'E', sh, wa, top)
        cv.trap(CX - .3, wa - 1, hem, 5.0 + bw * .6, sp.get('flare', 7.8) - 1.6 + bw * .6, coat, skew=(-.8 if walking else 0) - P['lean'] * .5)
        rr = math.radians(TWIST['r'])
        cv.capsule(CX, sh + 2, CX, wa, (5.4 + bw * .6) * (1 + .3 * abs(math.sin(rr))), 4.8 + bw * .5, coat)
        if sp.get('chest'): cv.ell(CX + 1.6 - math.sin(rr) * 1.5, sh + 6.5, 3.0 * (1 + .5 * abs(math.sin(rr))), 6.0, sp['chest'], .9)
        if sp.get('mailcoif'): cv.ell(CX + .8, sh + .5, 3.8, 2.0, 'mail')
        cv.trap(CX, wa - .6, wa + .7, 5.0, 5.0, 'belt', .8, round_hem=0)
        cv.ell(CX - .2 + math.sin(rr) * 1.5, sh + 2.0 + TWIST['sr'] * .5, 3.6, 2.8, coat, 1.05)
        head(cv, sp, 'E', hy, top)
        if sp.get('shield'): shield(cv, CX + 4.6 + P['sh'][0], sh + 7.5 + P['sh'][1], 1.6, 4.2)
        if atk is not None:
            atk_arm(cv, sp, 'E', th, sh, wa, 1, coat)
            return cv.image()
        a = near * 2.2
        cv.capsule(CX - .4, sh + 2.4, CX - .2 + a, wa + 2.5, 2.8, 2.3, coat, .95)
        cv.ell(CX - .1 + a, wa + 4.6, 1.2, 1.3, 'hand', .9)
        side_gear(cv, sp, sh, wa, top, a)
    return cv.image()

def ease(t): t = min(1, max(0, t)); return t * t * (3 - 2 * t)
def atk_pose(p, d):
    """공격 위상 p(0..1) → ((어깨 각, 팔꿈치 굽힘), 0, 0). 각도 0=아래, +=바깥/앞으로 들어 올림"""
    E = d == 'E'
    K = [(20.0, 15.0),                                   # 준비: 칼 낮게
         (185.0 if E else 165.0, 95.0 if E else 85.0),   # 들어올림: 팔꿈치 접어 칼을 머리 뒤로
         (78.0 if E else 300.0, 4.0),                    # 베기: 팔 끝까지 펴서 휘두름
         (70.0 if E else 312.0, 12.0)]                   # 따라가기
    back = (20.0 if E else 380.0, 15.0)
    def mix(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    if p < .33: q = mix(K[0], K[1], ease(p / .33))
    elif p < .46: q = mix(K[1], K[2], ease((p - .33) / .13))
    elif p < .62: q = mix(K[2], K[3], (p - .46) / .16)
    else: q = mix(K[3], back, ease((p - .62) / .38))
    return q, 0, 0

UPPER, FORE, BLADE = 7.6, 7.0, 11.0
def arm_chain(cx, sh, d, q, bw, side):
    """어깨→팔꿈치→손→칼끝 좌표"""
    sx, sy = (cx - .4, sh + 2.4) if d == 'E' else (cx + side * (7.0 + bw), sh + 2.3)
    a1 = math.radians(q[0]); a2 = math.radians(q[0] + q[1])
    ex, ey = sx + UPPER * side * math.sin(a1), sy + UPPER * math.cos(a1)
    fx_, fy_ = side * math.sin(a2), math.cos(a2)
    hx, hy = ex + FORE * fx_, ey + FORE * fy_
    return (sx, sy), (ex, ey), (hx, hy), (fx_, fy_)

ZERO_POSE = dict(lean=0.0, drop=0.0, f={-1: 0.0, 1: 0.0}, sh=(0.0, 0.0))
def _key(d):
    m = -1 if d == 'N' else 1                  # 뒷면은 좌우 반전
    if d == 'E':
        return [dict(lean=0, drop=0, f={-1: 0, 1: 0}, sh=(0, 0)),
                dict(lean=-3.0, drop=-.4, f={-1: 1.0, 1: -3.5}, sh=(3.0, -3.5)),       # 뒤로 젖히며 들어올림
                dict(lean=5.0, drop=3.8, f={-1: 7.0, 1: -6.5}, sh=(-5.0, 2.5)),       # 앞발 내딛고 내려찍기
                dict(lean=4.4, drop=3.6, f={-1: 7.0, 1: -6.5}, sh=(-5.0, 2.5))]
    return [dict(lean=0, drop=0, f={-1: 0, 1: 0}, sh=(0, 0)),
            dict(lean=2.8 * m, drop=-.4, f={-m: -.5 * m, m: 3.0 * m}, sh=(5 * m, -5)),   # 칼 쪽으로 비틀며 방패 앞으로
            dict(lean=-4.2 * m, drop=3.6, f={-m: -6.0 * m, m: 2.0 * m}, sh=(-5 * m, 3)),  # 반대쪽으로 크게 내딛으며 베기
            dict(lean=-3.7 * m, drop=3.4, f={-m: -6.0 * m, m: 2.0 * m}, sh=(-5 * m, 3))]
def _lerp(a, b, t):
    return dict(lean=a['lean'] + (b['lean'] - a['lean']) * t, drop=a['drop'] + (b['drop'] - a['drop']) * t,
                f={k: a['f'][k] + (b['f'][k] - a['f'][k]) * t for k in (-1, 1)},
                sh=tuple(a['sh'][i] + (b['sh'][i] - a['sh'][i]) * t for i in (0, 1)))
def atk_body(p, d):
    K = _key(d)
    if p < .33: return _lerp(K[0], K[1], ease(p / .33))
    if p < .46: return _lerp(K[1], K[2], ease((p - .33) / .13))
    if p < .62: return _lerp(K[2], K[3], (p - .46) / .16)
    return _lerp(K[3], K[0], ease((p - .62) / .38))

def ik(sx, sy, hx, hy, side, up):
    """2마디 팔 IK: 어깨→손 목표, 팔꿈치 위치"""
    vx, vy = hx - sx, hy - sy; dd = math.hypot(vx, vy) or 1e-6
    dc = min(max(dd, abs(UPPER - FORE) + .05), UPPER + FORE - .05)
    hx, hy = sx + vx / dd * dc, sy + vy / dd * dc
    a = (UPPER ** 2 - FORE ** 2 + dc ** 2) / (2 * dc); h = math.sqrt(max(0, UPPER ** 2 - a ** 2))
    px, py = sx + vx / dd * a, sy + vy / dd * a
    nx, ny = -vy / dd, vx / dd
    c1, c2 = (px + nx * h, py + ny * h), (px - nx * h, py - ny * h)
    if up: e = max((c1, c2), key=lambda c: side * c[0])     # 손이 어깨 위: 팔꿈치는 바깥쪽
    else: e = max((c1, c2), key=lambda c: c[1] + side * c[0] * .3)  # 아래: 팔꿈치는 아래·바깥
    return e, (hx, hy)

def pose_arm(cv, d, A, sh, bw, side, coat):
    sx, sy = shoulder(d, -1 if d == 'E' else side, bw, sh)
    hx, hy = sx + A['hand'][0], sy + A['hand'][1]
    (ex, ey), (hx, hy) = ik(sx, sy, hx, hy, side if d != 'E' else -1, A['hand'][1] < 0)
    cv.capsule(sx, sy, ex, ey, 2.8, 2.2, coat, .95); cv.ell(ex, ey, 2.1, 2.1, coat, .9)
    cv.capsule(ex, ey, hx, hy, 2.1, 1.6, coat, 1.0); cv.ell(sx, sy - .2, 3.4, 2.8, coat, 1.05)
    al = math.radians(A['alpha']); dx, dy = math.cos(al), math.sin(al); L = BLADE * A.get('k', 1.0)
    tx, ty = hx + L * dx, hy + L * dy
    cv.capsule(hx - 1.4 * dy, hy + 1.4 * dx, hx + 1.4 * dy, hy - 1.4 * dx, .45, .45, 'iron', .8)
    if L > 1: cv.capsule(hx + .8 * dx, hy + .8 * dy, tx, ty, .75, .4, 'iron', 1.3)
    cv.capsule(hx - 1.2 * dx, hy - 1.2 * dy, hx, hy, .45, .45, 'wood', 1.0)
    cv.ell(hx, hy, 1.3, 1.3, 'hand', .9)
    return tx, ty

def atk_arm(cv, sp, d, th, sh, wa, side, coat):
    bw = sp.get('build', 0)
    if isinstance(th, dict): return pose_arm(cv, d, th, sh, bw, side, coat)
    (sx, sy), (ex, ey), (hx, hy), (dx, dy) = arm_chain(CX, sh, d, th, bw, side)
    cv.capsule(sx, sy, ex, ey, 2.8, 2.2, coat, .95)          # 위팔
    cv.ell(ex, ey, 2.1, 2.1, coat, .9)                       # 팔꿈치
    cv.capsule(ex, ey, hx, hy, 2.1, 1.6, coat, 1.0)          # 아래팔
    cv.ell(sx, sy - .2, 3.4, 2.8, coat, 1.05)
    tx, ty = hx + BLADE * dx, hy + BLADE * dy
    cv.capsule(hx - 1.4 * dy, hy + 1.4 * dx, hx + 1.4 * dy, hy - 1.4 * dx, .45, .45, 'iron', .8)   # 가드
    cv.capsule(hx + .8 * dx, hy + .8 * dy, tx, ty, .75, .4, 'iron', 1.3)
    cv.capsule(hx - 1.2 * dx, hy - 1.2 * dy, hx, hy, .45, .45, 'wood', 1.0)
    cv.ell(hx, hy, 1.3, 1.3, 'hand', .9)

def blade_tip(sp, d, p):
    q = atk_pose(p, d)[0]; P = atk_body(p, d); cx = BASE_CX + P['lean']
    top = FOOT - 46 + P['drop']; sh = top + 9.0
    _, _, (hx, hy), (dx, dy) = arm_chain(cx, sh, d, q, sp.get('build', 0), 1 if d in 'SE' else -1)
    return hx + BLADE * dx, hy + BLADE * dy

def attack_frame(sp, d, p):
    from PIL import ImageDraw
    im = figure(sp, d, 0, False, atk=p)
    if .38 <= p <= .52:                       # 휘두르는 순간 잔상
        K = 4; tr = Image.new('RGBA', (W * K, H * K)); dr = ImageDraw.Draw(tr)
        pts = [blade_tip(sp, d, max(.33, p - i * .012)) for i in range(9)]
        for i in range(len(pts) - 1):
            al = int(70 * (1 - i / 8))
            dr.line([(pts[i][0] * K, pts[i][1] * K), (pts[i + 1][0] * K, pts[i + 1][1] * K)], fill=(150, 145, 135, al), width=K * 2)
        tr = tr.resize((W, H), Image.LANCZOS)
        out = tr.copy(); out.alpha_composite(im); im = out
    return im

def shield(cv, x, y, rx, ry):
    cv.ell(x, y, rx, ry, 'wood', 1.15)
    cv.ell(x, y, max(.6, rx * .32), ry * .3, 'iron', 1.0)
    cv.capsule(x - rx * .9, y, x + rx * .9, y, .25, .25, 'iron', .5) if rx > 2 else None

HEAD_SCALE = 1.25
def head(cv, sp, d, hy, top):
    q = HEAD_SCALE
    hy = top - .4 + 3.8 * q              # 꼭대기는 그대로, 머리만 키움
    ox = 1.0 * q if d == 'E' else 0
    k = sp['head']
    if k == 'hood':
        cv.ell(CX + ox * .4, hy + .6 * q, 3.6 * q, 4.2 * q, 'hood')
        if d == 'S': cv.ell(CX, hy + 1.8 * q, 2.0 * q, 2.4 * q, 'hair', .4); cv.ell(CX, hy + 2.2 * q, 1.3 * q, 1.2 * q, 'skin', .55)
        if d == 'E': cv.ell(CX + 2.4 * q, hy + 1.8 * q, 1.0 * q, 2.0 * q, 'skin', .55)
        return
    cv.ell(CX + ox, hy + 1.6 * q, 2.5 * q, 3.0 * q, 'skin' if d != 'N' else 'hair', .9)
    if k == 'helm':
        cv.ell(CX + ox * .3, hy, 3.1 * q, 2.9 * q, 'helm', 1.0, clip=lambda X, Y: Y <= hy + 1.0 * q)
        cv.capsule(CX - 3.5 + ox * .3, hy + 1.0 * q, CX + 3.5 + ox * .3, hy + 1.0 * q, .55 * q, .55 * q, 'helm', .7)
    elif k == 'bare':
        cv.ell(CX + ox * .2, hy - .2 * q, 2.8 * q, 2.3 * q, 'hair', 1.0, clip=lambda X, Y: Y <= hy + .6 * q)
        if d != 'N': cv.ell(CX + ox, hy + 3.6 * q, 1.8 * q, 1.4 * q, 'hair', 1.0)

def front_gear(cv, sp, d, sh, wa, top):
    bw = sp.get('build', 0)
    if sp.get('spear'):
        x = CX + 10.2 + bw
        cv.stick(x, top - 12, x, FOOT - .5, .7, 'wood', .8)
        cv.capsule(x, top - 15.5, x, top - 12, .2, .9, 'iron', 1.0)
        cv.ell(x - .2, wa + 1.5, 1.3, 1.4, 'hand', .9)
    if sp.get('staff'):
        x = CX + 10.0 + bw
        cv.stick(x, top - 2, x, FOOT - .5, .6, 'wood', .9)
        cv.ell(x + .4, top - 2.5, 1.2, 1.4, 'wood', 1.0)
        cv.ell(x - .2, wa + 1.0, 1.3, 1.4, 'hand', .9)
    if sp.get('bow'):
        x = CX - 10.0 - bw
        for i in range(-12, 13):
            cv.ell(x - (1.4 - (i / 12) ** 2 * 1.4), wa + 2 + i, .45, .7, 'wood', .9)
        cv.stick(x + .2, wa - 10, x + .2, wa + 14, .15, 'hood', 1.0)

def side_gear(cv, sp, sh, wa, top, a):
    hx = CX - .2 + a
    if sp.get('spear'):
        x = hx + 1.6
        cv.stick(x, top - 12, x, FOOT - .5, .7, 'wood', .8); cv.capsule(x, top - 15.5, x, top - 12, .2, .9, 'iron')
    if sp.get('staff'):
        x = hx + 1.6
        cv.stick(x, top - 2, x, FOOT - .5, .6, 'wood', .9); cv.ell(x + .4, top - 2.5, 1.2, 1.4, 'wood')
    if sp.get('bow'):
        x = hx + 1.8
        for i in range(-12, 13): cv.ell(x + (1.4 - (i / 12) ** 2 * 1.4), wa + 2.5 + i, .45, .7, 'wood', .9)
        cv.stick(x - .2, wa - 9.5, x - .2, wa + 14.5, .15, 'hood')

def back_gear(cv, sp, d, sh, wa, top):
    if sp.get('quiver'):
        if d == 'N': cv.capsule(CX + 4.5, sh - 4, CX - .5, sh + 9, 1.6, 1.6, 'belt', .9)
        else: cv.capsule(CX - 2.0, sh - 4, CX - 4.0, sh + 8, 1.6, 1.6, 'belt', .8)
    if d == 'N':
        x = CX - 10.2
        if sp.get('spear'): cv.stick(x, top - 12, x, FOOT - .5, .7, 'wood', .8); cv.capsule(x, top - 15.5, x, top - 12, .2, .9, 'iron')
        if sp.get('staff'): cv.stick(x, top - 2, x, FOOT - .5, .6, 'wood', .9); cv.ell(x + .4, top - 2.5, 1.2, 1.4, 'wood')

CLASSES = {
    'warrior': dict(name='전사', head='helm', chest='chest', mailcoif=True, shield=True, hem=35.0, build=.6),
    'soldier': dict(name='병사', head='helm', chest='chest', mailcoif=True, spear=True, hem=36.0, build=.4),
    'archer':  dict(name='궁수', head='hood', chest='belt', bow=True, quiver=True, hem=34.5, build=-.6, flare=7.0),
    'priest':  dict(name='사제', head='bare', staff=True, hem=44.0, coat='robe', flare=8.6, buckle=False, build=-.2),
}

NF = 24
def anims(sp):
    F = {}
    for d in 'SNE':
        F['idle_' + d] = [figure(sp, d, i / NF, False) for i in range(NF)]
        F['walk_' + d] = [figure(sp, d, i / NF, True) for i in range(NF)]
    if sp.get('shield'):
        for d in 'SNE': F['attack_' + d] = [attack_frame(sp, d, i / NF) for i in range(NF)]
    for k in (('idle', 'walk', 'attack') if sp.get('shield') else ('idle', 'walk')):
        F[k + '_W'] = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in F[k + '_E']]
    return F
