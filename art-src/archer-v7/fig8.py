"""MAZ 캐릭터 v5: 3D 관절 모델 + 쿼터뷰(위에서 PITCH° 내려다봄) 정사영, 8방향.
타원체를 z-버퍼로 그린 뒤 fig4의 후처리(4x 축소·노이즈·반사광·경계 흐림)를 그대로 쓴다."""
import math, numpy as np
from PIL import Image, ImageDraw
import fig4
fig4.SAT = 1.15; fig4.EDGE_MIX = .3      # 바이블: 거의 무채색, 황토 한 줄기만

PITCH = 35.0
import os as _os
W, H = int(_os.environ.get('CELL_W', 64)), int(_os.environ.get('CELL_H', 72))   # 긴 무기는 칸을 키움
FOOT, CX = float(_os.environ.get('CELL_FOOT', 64)), W / 2
SS = fig4.SS
fig4.W, fig4.H, fig4.FOOT = W, H, FOOT
MAT = fig4.MAT
c_ = fig4.c
SHADE_POW = 1.25                    # 옆면은 빨리 어두워지고 윗면만 밝게(컨셉 인물: 몸 거의 검정, 어깨·머리 윗선만 반사광)
MAT.update({                       # 궁수 v2: 중성 회갈색, 윗면 밝기 차이 크게
    'coat':   (c_('#0a0909'), c_('#1f1c1a'), c_('#524c46'), 0.03),
    'chest':  (c_('#141312'), c_('#302c29'), c_('#66605a'), 0.06),
    'leg':    (c_('#070606'), c_('#0e0d0c'), c_('#2a2623'), 0.0),
    'boot':   (c_('#060505'), c_('#0d0c0b'), c_('#242120'), 0.04),
    'skin':   (c_('#2e2824'), c_('#584d43'), c_('#948472'), 0.08),
    'bowwood':(c_('#2c2825'), c_('#5a534c'), c_('#a1978c'), 0.10),     # 활대: 컨셉 창대처럼 읽히게 중간 밝기     # 활대: 중간 톤 나무(진흙 위에서 막대가 읽히게)
    'hood2':  (c_('#080707'), c_('#161413'), c_('#3d3936'), 0.02),
    'hood':   (c_('#0a0909'), c_('#201e1c'), c_('#6a6662'), 0.02),      # 후드: 윗면만 밝게
    'hair':   (c_('#080707'), c_('#121010'), c_('#2a2522'), 0.02),
    'wood':   (c_('#070606'), c_('#110f0d'), c_('#342e28'), 0.08),
    'belt':   (c_('#080707'), c_('#100e0d'), c_('#2a2622'), 0.10),      # 벨트: 코트보다 어두운 띠
    'hand':   (c_('#302a25'), c_('#5c5147'), c_('#a3957f'), 0.05),
})
MAT.update({                       # 단계별 갑옷 재질
    'wool':   (c_('#0b0a0a'), c_('#232120'), c_('#6c6864'), 0.03),
    'wool2':  (c_('#080808'), c_('#171615'), c_('#3b3734'), 0.03),
    'quilt':  (c_('#0c0b0a'), c_('#23201e'), c_('#5a544e'), 0.02),
    'quilt2': (c_('#090808'), c_('#1a1816'), c_('#45403c'), 0.02),
    'quilt3': (c_('#141312'), c_('#332f2c'), c_('#6e6862'), 0.02),     # 가슴 앞판(밝은 띠)
    'leather2':(c_('#131211'), c_('#302b27'), c_('#6a635b'), 0.15),
    'leather':(c_('#0b0a09'), c_('#211d1a'), c_('#58504a'), 0.15),
    'skinsh': (c_('#1c1815'), c_('#332c26'), c_('#574c41'), 0.05),
    'chainm': (c_('#0b0b0b'), c_('#211f1d'), c_('#4a4743'), 0.35),
    'skinsh': (c_('#1c140e'), c_('#2e2219'), c_('#4a372a'), 0.05),
    'helm':   (c_('#1c1b1a'), c_('#46443f'), c_('#9a958c'), 0.8),
    'plate':  (c_('#121212'), c_('#3a3936'), c_('#8a867e'), 0.7),
    'felt':   (c_('#0a0909'), c_('#1d1b19'), c_('#5a5652'), 0.0),      # 펠트 모자
    'fur':    (c_('#0b0a0a'), c_('#2a2724'), c_('#857e74'), 0.0),      # 털 어깨걸이(끝이 밝음)
    'fur2':   (c_('#080707'), c_('#161413'), c_('#3a3633'), 0.0),
    'shirt':  (c_('#131211'), c_('#2c2825'), c_('#605a53'), 0.03),     # 거친 아마 셔츠
    'jerkin': (c_('#0a0909'), c_('#1c1917'), c_('#4a443e'), 0.12),     # 짧은 가죽 조끼
    'cloak':  (c_('#080707'), c_('#171514'), c_('#4c4844'), 0.02),     # 긴 망토(등)
    'cloak2': (c_('#060505'), c_('#0f0e0d'), c_('#2c2926'), 0.02),
})
# 갑옷: 몸통·몸통줄무늬·가슴판·자락·자락앞·팔·견갑·정강이·사슬두건
ARMORS = {
 'coat':      dict(torso='coat', torso2='coat', front='chest', skirt='coat', skirt_front='chest', arm='coat', paul=None, greave=False, coif=True),
 'quilted':   dict(torso='quilt', torso2='quilt2', front=None, skirt='quilt', skirt_front=None, arm='quilt', paul=None, greave=False, coif=False),
 'leather':   dict(torso='leather', torso2='leather', front='belt', skirt='coat', skirt_front='leather', arm='coat', paul=None, greave=False, coif=False),
 'chain':     dict(torso='chainm', torso2='chainm', front='chest', skirt='chainm', skirt_front='chest', arm='chainm', paul=None, greave=False, coif=True),
 'chain_plus':dict(torso='chainm', torso2='chainm', front='plate', skirt='chainm', skirt_front='chest', arm='chainm', paul='plate', greave=False, coif=True),
 'arch1':     dict(torso='coat', torso2='coat', front='chest', skirt='coat', skirt_front='chest', arm='coat', paul=None, greave=False, coif=False),       # 궁수: 기존 천 코트
 'arch2':     dict(torso='quilt', torso2='quilt2', front='quilt3', skirt='coat', skirt_front='chest', arm='coat', paul=None, greave=False, coif=False),     # 코트 위 누비 조끼
 'arch3':     dict(torso='quilt', torso2='quilt2', front='quilt3', skirt='quilt', skirt_front='quilt3', arm='quilt', paul=None, greave=False, coif=False),     # 누비 갬비슨
 'arch4':     dict(torso='leather', torso2='leather', front='leather2', skirt='quilt', skirt_front='quilt3', arm='quilt', paul=None, greave=False, coif=False), # 갬비슨 위 가죽 조끼
 'arch5':     dict(torso='leather', torso2='leather', front='leather2', skirt='leather', skirt_front='leather2', arm='leather', paul='leather', greave=False, coif=False),  # 겹친 가죽 갑옷
 'n1': dict(torso='shirt', torso2='shirt', front='jerkin', skirt='shirt', skirt_front=None, arm='shirt', paul=None, greave=False, coif=False),      # 셔츠+짧은 가죽 조끼
 'n2': dict(torso='coat', torso2='coat', front='chest', skirt='coat', skirt_front='chest', arm='coat', paul=None, greave=False, coif=False),          # 천 코트
 'n3': dict(torso='quilt', torso2='quilt2', front='quilt3', skirt='quilt', skirt_front='quilt3', arm='quilt', paul=None, greave=False, coif=False),   # 누비 갬비슨
 'n4': dict(torso='leather', torso2='leather', front='leather2', skirt='quilt', skirt_front='leather2', arm='quilt', paul='leather2', greave=False, coif=False),  # 갬비슨+가죽 흉갑·견갑
 'n5': dict(torso='leather', torso2='leather', front='leather2', skirt='cloak', skirt_front='leather2', arm='leather', paul=None, greave=False, coif=False),   # 가죽 갑옷+긴 망토
 'plate':     dict(torso='plate', torso2='plate', front='plate', skirt='chainm', skirt_front='plate', arm='plate', paul='plate', greave=True, coif=True),
}
NDIR = 16
_NAMES16 = ['S', 'SSE', 'SE', 'ESE', 'E', 'ENE', 'NE', 'NNE', 'N', 'NNW', 'NW', 'WNW', 'W', 'WSW', 'SW', 'SSW']
DIRS = {n: (round(math.sin(math.radians(22.5 * i)), 6), round(-math.cos(math.radians(22.5 * i)), 6)) for i, n in enumerate(_NAMES16)}  # S부터 시계 반대(동쪽) 방향

_p = math.radians(PITCH)
EX = np.array([1.0, 0, 0]); EU = np.array([0, math.sin(_p), math.cos(_p)]); ED = np.array([0, -math.cos(_p), math.sin(_p)])
LIGHT = np.array([-0.22, 0.90, 0.38])     # 흐린 하늘 위쪽 빛: 윗면만 밝음; LIGHT /= np.linalg.norm(LIGHT)   # (화면x, 화면위, 카메라쪽)
SCALE = .985 / (0.55 * math.cos(_p) + 0.45)      # 컨셉 경비병과 같은 화면 키(약 46px)

def nrm(v): v = np.asarray(v, float); return v / (np.linalg.norm(v) or 1)
def rotz(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])
def rotx(a):
    c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def roty(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def frame_from(z):
    """z축을 주어진 방향으로 하는 회전행렬(열=로컬 축)"""
    z = nrm(z); a = np.array([1.0, 0, 0]) if abs(z[0]) < .9 else np.array([0, 1.0, 0])
    x = nrm(np.cross(a, z)); y = np.cross(z, x); return np.stack([x, y, z], 1)

class Raster:
    def __init__(s):
        s.cv = fig4.Canvas()
        s.z = np.full((H * SS, W * SS), -1e9)
        s.sx = s.cv.X - CX; s.su = FOOT - s.cv.Y
        s.tag = np.zeros((H * SS, W * SS), np.uint8); s.cur_tag = 0      # 얇은 소품(활대) 표시: 후처리에서 2px 격자에 맞춰 또렷하게

    def ellipsoid(s, c, R, r, mat, gain=1.0, matfn=None, clip=None):
        """c: 월드 중심, R: 3x3(열=로컬축), r: 반지름 3개"""
        c = np.asarray(c, float); r = np.asarray(r, float)
        pc = (c @ EX, c @ EU); rad = max(r) + .5
        x0 = int(max(0, (CX + pc[0] - rad) * SS)); x1 = int(min(W * SS, (CX + pc[0] + rad) * SS + 1))
        y0 = int(max(0, (FOOT - pc[1] - rad) * SS)); y1 = int(min(H * SS, (FOOT - pc[1] + rad) * SS + 1))
        if x0 >= x1 or y0 >= y1: return
        sx = s.sx[y0:y1, x0:x1]; su = s.su[y0:y1, x0:x1]
        base = sx[..., None] * EX + su[..., None] * EU - c
        q0 = (base @ R) / r; v = (ED @ R) / r
        a = v @ v; b = q0 @ v; c0 = (q0 * q0).sum(-1) - 1
        disc = b * b - a * c0; hit = disc >= 0
        t = (-b + np.sqrt(np.maximum(disc, 0))) / a
        qh = q0 + t[..., None] * v
        if clip is not None: hit &= clip(qh)
        zb = s.z[y0:y1, x0:x1]; m = hit & (t > zb)
        if not m.any(): return
        nl = qh / r; nw = nl @ R.T; nw /= np.linalg.norm(nw, axis=-1, keepdims=True) + 1e-9
        nx, nu, nz = nw @ EX, nw @ EU, nw @ ED
        d = np.clip(nx * LIGHT[0] + nu * LIGHT[1] + nz * LIGHT[2], 0, 1) ** SHADE_POW * gain
        mats = matfn(qh) if matfn is not None else None
        for mname in ([mat] if mats is None else list(set(mats[m].ravel()))):
            mm = m if mats is None else (m & (mats == mname))
            if not mm.any(): continue
            dk, bs, lt, spec = MAT[mname]
            col = np.where((d < .5)[..., None], dk + (bs - dk) * (d / .5)[..., None], bs + (lt - bs) * ((d - .5) / .5).clip(0, 1)[..., None])
            if spec: col = col + (np.array([235, 230, 220]) - col) * ((d if spec >= .3 else np.clip(d, 0, 1)) ** 18 * spec)[..., None]   # 가죽·천은 밝기 배율로 하얗게 튀지 않게
            sub = s.cv.rgb[y0:y1, x0:x1]; sub[mm] = col[mm]; s.cv.a[y0:y1, x0:x1][mm] = 1
        zb[m] = t[m]; s.tag[y0:y1, x0:x1][m] = s.cur_tag

    def sphere(s, c, rad, mat, gain=1.0):
        s.ellipsoid(c, np.eye(3), (rad, rad, rad), mat, gain)

    def limb(s, p0, p1, r0, r1, mat, gain=1.0, step=.45):
        p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
        L = np.linalg.norm(p1 - p0); n = max(2, int(L / (min(r0, r1) * step)) + 1)
        R = frame_from(p1 - p0)
        for i in range(n):
            t = i / (n - 1); rr = r0 + (r1 - r0) * t
            s.ellipsoid(p0 + (p1 - p0) * t, R, (rr, rr, max(rr, L / (n - 1) * .8)), mat, gain)

def proj(p):
    p = np.asarray(p, float); return CX + p @ EX, FOOT - p @ EU

def ik(S, T, l1, l2, pole):
    S, T = np.asarray(S, float), np.asarray(T, float)
    v = T - S; d = np.linalg.norm(v); dc = min(max(d, abs(l1 - l2) + .05), l1 + l2 - .05)
    u = v / (d or 1); T = S + u * dc
    a = (l1 * l1 - l2 * l2 + dc * dc) / (2 * dc); h = math.sqrt(max(0, l1 * l1 - a * a))
    p = np.asarray(pole, float); p = p - u * (p @ u); p = nrm(p) if np.linalg.norm(p) > 1e-6 else frame_from(u)[:, 0]
    return S + u * a + p * h, T

# ------------------------------------------------------------------ 포즈
UP_A, FO_A, THIGH, SHIN = 7.6, 7.0, 11.6, 11.6
SHO_W, SHO_H, PEL_H = 5.3, 13.4, 25.0      # 컨셉: 두꺼운 누비 상의로 어깨 둥글고 육중(폭 19px)
TARGET = np.array([0.0, 20.0, 28.0])
TARGET_FAR = np.array([0.0, 150.0, 26.0])   # 활 조준점(멀리 정면, 가슴 높이)
# 활: h=반길이, ld=당김 길이(손잡이~입꼬리), al=화살 길이, rune=룬 장식
BOWS = {'bow': dict(ko='활', h=12.0, ld=16.0, al=19.0), 'longbow': dict(ko='장궁', h=20.0, ld=17.5, al=21.0),
        'runebow': dict(ko='룬활', h=14.0, ld=16.5, al=19.5, rune=True),
        'crossbow': dict(ko='석궁', xbow=True)}
# 무기: kind, len(손~끝), 칼날 굵기 w0→w1, 양손 여부
WEAPONS = {
 'arming':     dict(ko='철검', kind='sword', len=11.0, w0=.75, w1=.4),
 'shortsword': dict(ko='숏소드', kind='sword', len=8.0, w0=.85, w1=.45, guard=1.2),
 'longsword':  dict(ko='롱소드', kind='sword', len=14.0, w0=.75, w1=.35, guard=1.8, grip=2.2),
 'zweihander': dict(ko='쯔바이핸더', kind='sword', len=19.0, w0=.95, w1=.45, guard=2.6, grip=4.0, twohand=True, grip2=2.8),
 'rapier':     dict(ko='레이피어', kind='rapier', len=15.0, w0=.4, w1=.22, guard=1.3),
 'handaxe':    dict(ko='손도끼', kind='axe', len=9.0),
 'morningstar':dict(ko='모닝스타', kind='mace', len=10.0),
}
# 방패(앤암스): 폭, 길이(팔뚝 방향), 재질, 가운데 돌기
SHIELDS = {'round': (3.7, 4.9, 'chest', True), 'wood': (3.5, 4.5, 'coat', False), 'heater': (3.6, 6.0, 'chest', False),
           'tower': (4.6, 9.0, 'chest', False)}     # 공격 목표점(캐릭터 앞, 상대 가슴 높이) — 모든 타격이 이 점을 지남

def base_pose():
    return dict(root=(0.0, 0.0), drop=0.0, lean=0.0, side=0.0, twist=0.0, sr=0.0,
                fL=(-2.4, 0.0, 0.0), fR=(2.4, 0.0, 0.0),
                rh=(1.0, 2.0, -13.6), blade=(0.15, 0.55, -0.82), bk=1.0,
                lh=(-0.6, 4.5, -10.5), skirt=(0.0, 0.0), aim=0.0,
                draw=0.0, bind=0.0, arrow=0.0, carry=0.0, aimw=0.0, bowup=(0.0, 0.25, 1.0), sheath=0.0, elb=0.0,
                xb=(1.2, 1.0, -10.5), xd=(0.0, .45, -.89), xaim=0.0, span=1.0, bolt=1.0, xl=0.0, xpull=0.0,
                gpitch=0.0, groll=0.0, goff=(0.0, 0.0, 0.0), gpiv=(0.0, 0.0, 2.0), hdrop=0.0, hturn=0.0, vial=0.0)

def sheath_geo(P):
    """왼쪽 허리 칼집: (손잡이 잡는 점, 칼집 방향=칼끝 쪽, 칼집 입구) — 캐릭터 공간"""
    rx, ry = P['root']; pel = np.array([rx, ry, PEL_H - P['drop']]); Rp = rotz(math.radians(P['twist'] * .35))
    throat = pel + Rp @ np.array([-4.4, 1.0, 1.8]); d = nrm(Rp @ np.array([-.12, -.62, -.78]))
    return throat - d * 1.0, d, throat
BLADE_FIX = {'wrist': 0, 'body': 0}
WRIST_MAX = math.radians(105)          # 팔뚝 방향과 칼날 사이 최대 각(손목 한계)
def fix_blade(bd, hr, el, pel, neck, wp):
    """칼 방향 보정: 손목이 꺾일 수 없는 각도면 팔뚝 쪽으로 되돌리고, 칼날이 몸통을 관통하면 바깥으로 민다."""
    fo = nrm(hr - el); c = float(np.clip(bd @ fo, -1, 1)); ang = math.acos(c)
    if ang > WRIST_MAX:
        BLADE_FIX['wrist'] += 1
        ax = bd - c * fo; ax = nrm(ax) if np.linalg.norm(ax) > 1e-6 else nrm(np.cross(fo, [0, 0, 1.0]) + 1e-6)
        bd = nrm(math.cos(WRIST_MAX) * fo + math.sin(WRIST_MAX) * ax)
    L = wp.get('len', 11.0); a0, a1 = pel + np.array([0, 0, 2.0]), neck
    for _ in range(6):                                   # 몸통 캡슐(반지름 4.6)과 겹치면 바깥으로
        worst, push = 0.0, None
        for t in (.35, .55, .75, .95):
            p = hr + bd * L * t; u = a1 - a0; s = np.clip((p - a0) @ u / (u @ u), 0, 1); q = a0 + u * s
            d = p - q; dist = np.linalg.norm(d)
            if dist < 4.6 and 4.6 - dist > worst: worst, push = 4.6 - dist, nrm(d + 1e-6)
        if push is None: break
        BLADE_FIX['body'] += 1
        bd = nrm(bd + push * .35)
    return bd

def build(r, sp, P, facing):
    """캐릭터 공간(x=오른쪽, y=앞, z=위) → 월드(쿼터뷰 카메라 기준) 회전 후 그리기"""
    f = nrm((facing[0], facing[1], 0)); right = np.array([f[1], -f[0], 0.0])
    C = np.stack([right, f, [0, 0, 1.0]], 1) * SCALE     # 캐릭터→월드
    gp, gr, go = P.get('gpitch', 0.0), P.get('groll', 0.0), P.get('goff', (0.0, 0.0, 0.0))
    if gp or gr or any(go):                                 # 몸 전체 회전(쓰러짐): 발목 높이 축 기준 앞뒤(gpitch, +뒤로)·옆(groll, +오른쪽) 회전 후 이동(goff)
        Rg = rotx(math.radians(gp)) @ roty(math.radians(gr)); piv = np.asarray(P.get('gpiv', (0.0, 0.0, 2.0)), float); go = np.asarray(go, float)
        C0 = C; C = C0 @ Rg
        def W_(p): return C0 @ (Rg @ (np.asarray(p, float) - piv) + piv + go)
    else:
        def W_(p): return C @ np.asarray(p, float)
    sc = SCALE
    rx, ry = P['root']; pel = np.array([rx, ry, PEL_H - P['drop']])
    Rt = rotz(math.radians(P['twist'])) @ rotx(-math.radians(P['lean'])) @ roty(math.radians(P['side']))
    Rp = rotz(math.radians(P['twist'] * .35))
    bw = sp.get('build', 0.0); coat = sp.get('coat', 'coat')
    A = dict(ARMORS[sp.get('armor', 'coat')])
    if 'armor' not in sp: A['front'] = sp.get('chest'); A['coif'] = sp.get('mailcoif', False); A['skirt_front'] = 'chest' if sp.get('tabard', True) else None
    sho = {s: pel + Rt @ np.array([s * (SHO_W + bw * .6), 0, SHO_H + (P['sr'] if s > 0 else -P['sr'] * .4)]) for s in (-1, 1)}
    neck = pel + Rt @ np.array([0, .2, SHO_H + 1.6]); headc = pel + Rt @ np.array([0, .5, SHO_H + 5.2])
    # 다리
    legs = {}
    for s, key in ((-1, 'fL'), (1, 'fR')):
        hip = pel + Rp @ np.array([s * 2.4, 0, 0]); fx, fy, lift = P[key]
        ank = np.array([fx, fy, 2.0 + lift])
        kn, ank = ik(hip, ank, THIGH, SHIN, Rp @ np.array([s * .15, 1, 0]))
        legs[s] = (hip, kn, ank)
    def draw_legs():
        for s in (-1, 1):
            hip, kn, ank = legs[s]
            lm = sp.get('legmat', 'leg'); lk = 1.0 if lm != 'leg' else .85
            r.limb(W_(hip), W_(kn), 2.5 * sc, 1.9 * sc, lm, lk)
            r.limb(W_(kn), W_(ank), 1.9 * sc, 1.0 * sc, lm, lk)
            if sp.get('kneepad'): r.ellipsoid(W_(kn + Rp @ np.array([0, .6, .2])), C @ Rp / sc, (2.0 * sc, 1.6 * sc, 2.2 * sc), sp['kneepad'], 1.1)   # 무릎 가죽 보호대
            if sp.get('thighstrap'):                                                                                            # 허벅지 띠(가죽 바지 위)
                for tt in (.35, .7): r.limb(W_(hip + (kn - hip) * (tt - .03)), W_(hip + (kn - hip) * (tt + .03)), (2.5 - .6 * tt) * sc, (2.5 - .6 * tt) * sc, 'belt', 1.2)
            wr = sp.get('wrap')
            if wr:                                            # 각반: 정강이를 감은 띠(천은 줄무늬, 가죽·철은 한 덩어리)
                m2 = {'quilt': 'quilt2', 'leather': 'belt', 'plate': 'plate'}.get(wr, wr)
                for j in range(5):
                    t0, t1 = .12 + j * .14, .12 + (j + 1) * .14
                    r.limb(W_(kn + (ank - kn) * t0), W_(kn + (ank - kn) * t1), (1.95 - .12 * j) * sc, (1.83 - .12 * j) * sc, wr if j % 2 == 0 else m2, 1.3)
            if A['greave']: r.limb(W_(kn + (ank - kn) * .05), W_(kn + (ank - kn) * .8), 1.75 * sc, 1.15 * sc, 'plate', .9)
            r.ellipsoid(W_(ank + Rp @ np.array([0, .9, -1.0])), C @ Rp / sc, (1.6 * sc, 2.4 * sc, 1.1 * sc), 'boot', .9)
    draw_legs()
    # 코트 자락: 허리에서 무릎까지 원판 쌓기, 내딛은 다리 쪽으로 퍼짐
    knees_mid = (legs[-1][1] + legs[1][1]) / 2
    hem_z = sp.get('hem_z', 12.5)
    n = 12
    if sp.get('noskirt'):                                       # 치마(자락) 없음: 벨트 아래 짧은 상의 밑단만(엉덩이 덮는 3단)
        for i in range(3):
            t = i / 2; z = PEL_H + 1.5 - 4.0 * t
            r.ellipsoid(W_(pel + Rp @ np.array([0, 0, z - PEL_H])), C @ Rp / sc, ((6.0 - sp.get('taper', 0.0) + .5 * t + bw * .5) * sc, (4.4 - sp.get('taper', 0.0) * .3 + .6 * t) * sc, 1.5 * sc), A['skirt'], 1.0 - .1 * t,
                        matfn=(lambda q, t=t: np.where((q[..., 1] > .78) & (np.abs(q[..., 0]) < .38), A['skirt_front'], A['skirt'])) if A['skirt_front'] else None)
        n = 0
    for i in range(n):
        t = i / (n - 1); z = PEL_H + 2 - (PEL_H + 2 - hem_z) * t
        cxy = pel[:2] + (knees_mid[:2] - pel[:2]) * t * .55 + np.array(P['skirt']) * t
        rxx = 6.5 + bw * .5 + (sp.get('flare', 7.6) - 6.5) * t + abs(legs[-1][2][0] - legs[1][2][0]) * .12 * t
        ryy = 4.7 + 1.2 * t + abs(legs[-1][2][1] - legs[1][2][1]) * .18 * t
        Rd = C @ Rp / sc
        # 다리가 자락을 뚫지 않게: 이 높이에서 다리(허벅지·정강이·무릎)가 지나는 점을 모아 타원이 감싸도록 넓힘
        lp = []
        for s_ in (-1, 1):
            hip, kn, ank = legs[s_]
            for a_, b_ in ((hip, kn), (kn, ank)):
                if (a_[2] - z) * (b_[2] - z) <= 0 and abs(a_[2] - b_[2]) > 1e-6:
                    lp.append(a_ + (b_ - a_) * (z - a_[2]) / (b_[2] - a_[2]))
            if abs(kn[2] - z) < 2.2: lp.append(kn)
        if lp:
            Rz = Rp[:2, :2]; loc = [Rz.T @ (q[:2] - cxy) for q in lp]
            mg = 2.6
            x0 = min([-rxx] + [q[0] - mg for q in loc]); x1 = max([rxx] + [q[0] + mg for q in loc])
            y0 = min([-ryy] + [q[1] - mg for q in loc]); y1 = max([ryy] + [q[1] + mg for q in loc])
            grow = (x1 - x0) > 2 * rxx + 1e-6 or (y1 - y0) > 2 * ryy + 1e-6
            cxy = cxy + Rz @ np.array([(x0 + x1) / 2, (y0 + y1) / 2])
            k_ = 1.12 if grow else 1.0
            rxx, ryy = (x1 - x0) / 2 * k_, (y1 - y0) / 2 * k_
        def mf(q, t=t):
            m = np.full(q.shape[:-1], A['skirt'], dtype=object)
            if A['skirt_front']: m[(q[..., 1] > .78) & (np.abs(q[..., 0]) < .38) & (t > .08)] = A['skirt_front']
            return m
        r.ellipsoid(W_(np.array([cxy[0], cxy[1], z - P['drop'] * (1 - t) * 0])), Rd, (rxx * sc, ryy * sc, 1.6 * sc), A['skirt'], .95, matfn=mf)
    # 몸통
    for i in range(9):
        t = i / 8; h = 1.0 + (SHO_H - 1.0) * t
        Rr = rotz(math.radians(P['twist'] * (.35 + .65 * t))) @ rotx(-math.radians(P['lean'] * t)) @ roty(math.radians(P['side'] * t))
        c = pel + Rr @ np.array([0, 0, h]) if t > 0 else pel + np.array([0, 0, h])
        tw = sp.get('taper', 0.0)                                   # 허리 잘록(민첩형): 허리 좁고 어깨 쪽으로 벌어짐
        rxx = (5.1 - tw + (1.2 + tw * 1.6) * t) + bw * .6; ryy = 3.8 - tw * .4 + .8 * t
        def mf(q, t=t, i=i):
            m = np.full(q.shape[:-1], A['torso'] if i % 2 == 0 else A['torso2'], dtype=object)
            if A['front'] and .3 < t < .95: m[(q[..., 1] > .55) & (np.abs(q[..., 0]) < .62)] = A['front']
            return m
        r.ellipsoid(W_(c), C @ Rr / sc, (rxx * sc, ryy * sc, 2.6 * sc), A['torso'], 1.0, matfn=mf)
    r.ellipsoid(W_(pel + Rp @ np.array([0, 0, 2.0])), C @ Rp / sc, ((6.7 - sp.get('taper', 0.0) * 1.2 + bw) * sc, (5.1 - sp.get('taper', 0.0) * .4) * sc, .9 * sc), 'belt', 1.15)     # 허리 벨트: 띠가 읽히게
    if A['coif']: r.ellipsoid(W_(neck), C @ Rt / sc, (4.0 * sc, 3.5 * sc, 1.7 * sc), "chainm", 1.0)
    ck = sp.get('cloak')                                       # 긴 망토: 어깨에서 등 뒤로 늘어지는 넓은 천(끝 높이 z, 폭)
    if ck:
        cz, cw = ck
        n_ = 14
        for i in range(n_):
            t = i / (n_ - 1); z = SHO_H + 1.2 - (SHO_H + 1.2 - cz) * t
            yb = -3.6 - 1.6 * t - (0.6 * t * t)
            rxx = 4.2 + (cw - 4.2) * min(1, t * 1.4); ryy = 1.0 + .9 * t
            def cm(q, t=t):
                m = np.full(q.shape[:-1], 'cloak', dtype=object); m[(q[..., 1] > .3) | (q[..., 2] < -.5)] = 'cloak2'; return m
            r.ellipsoid(W_(pel + Rp @ np.array([0, yb, z - PEL_H])), C @ Rp / sc, (rxx * sc, ryy * sc, 1.5 * sc), 'cloak', .95 - .25 * t, matfn=cm)
        for i in range(4):                                     # 어깨 위 케이프 고리(목에서 어깨 끝까지)
            t = i / 3; zc = SHO_H + 2.4 - 2.0 * t
            r.ellipsoid(W_(pel + Rt @ np.array([0, -.9, zc])), C @ Rt / sc, ((3.8 + 3.0 * t) * sc, (3.3 + 1.5 * t) * sc, 1.1 * sc), 'cloak', 1.0 - .1 * t,
                        clip=(lambda q, t=t: q[..., 1] < .5 - .45 * t) if t > .3 else None)
    if sp.get('mantle'):                                       # 털 어깨걸이: 목둘레에서 어깨 끝까지 덩어리진 털
        rng = np.random.RandomState(7)
        for k_ in range(26):
            a = k_ / 26 * 2 * math.pi; rr = 1.0 if k_ % 2 == 0 else 1.35
            x = math.sin(a) * (5.9 * rr if abs(math.sin(a)) > .3 else 4.6); y = math.cos(a) * 3.6 * rr - .6
            z = SHO_H + 1.9 - abs(math.sin(a)) * 1.8 - (0.8 if rr > 1 else 0)
            r.sphere(W_(pel + Rt @ np.array([x, y, z])), (1.55 + .35 * rng.rand()) * sc, 'fur' if k_ % 3 else 'fur2', 1.0 + .25 * rng.rand())
        for s_ in (-1, 1):                                     # 어깨 끝에서 늘어진 털 가닥
            for j in range(3):
                r.sphere(W_(pel + Rt @ np.array([s_ * (6.6 - .4 * j), -.4 - .6 * j, SHO_H - 1.0 - 1.6 * j])), (1.3 - .2 * j) * sc, 'fur2' if j else 'fur', .9)
    if sp.get('beltarrows'):                                   # 허리띠에 꽂은 화살(왼쪽 뒤)
        for j in range(sp['beltarrows']):
            a0 = pel + Rp @ np.array([-3.4 - .5 * j, -2.2 + .7 * j, 1.5]); d_ = nrm(Rp @ np.array([-.15, -.35, -.92]))
            r.limb(W_(a0 - d_ * 4.5), W_(a0 + d_ * 5.5), .26 * sc, .26 * sc, 'wood', 1.3, step=.9)
            r.sphere(W_(a0 - d_ * 4.8), .45 * sc, 'chest', 1.2)
    if sp.get('hipquiver'):                                    # 허리 화살통: 오른쪽 허리에서 뒤·아래로 비스듬히
        q0 = pel + Rp @ np.array([4.3, -.8, -.4]); q1 = pel + Rp @ np.array([5.2, -6.2, -4.4])
        r.limb(W_(q0), W_(q1), 1.2 * sc, 1.35 * sc, 'belt', 1.0)
        r.ellipsoid(W_(q0 + Rp @ np.array([0, -.4, .3])), C @ Rp / sc, (1.5 * sc, 1.6 * sc, .7 * sc), 'leather2', 1.1)
        na = sp.get('arrows', 3); d_ = nrm(q0 - q1)
        for o in np.linspace(-.8, .8, na): r.sphere(W_(q0 + d_ * 1.6 + Rp @ np.array([o * .6, o * .5, .9 + .25 * abs(o)])), .45 * sc, 'chest', 1.1)
    # 팔
    def arm(s, tgt, pole, mat_hand='hand'):
        S = sho[s]; T = S + np.asarray(tgt, float)
        el, hd = ik(S, T, UP_A, FO_A, pole)
        r.sphere(W_(S + np.array([0, 0, -.2])), 2.3 * sc, A['arm'], 1.0)                # 둥근 어깨(넓은 소매)
        if A['paul']:
            if sp.get('bigpaul'):                              # 넓고 각진 가죽 견갑: 어깨 바깥으로 튀어나와 실루엣이 네모짐
                r.ellipsoid(W_(S + Rt @ np.array([s * 1.3, 0, 1.1])), C @ Rt @ roty(math.radians(s * 18)) / sc, (3.3 * sc, 2.9 * sc, 1.3 * sc), A['paul'], 1.05)
                r.ellipsoid(W_(S + Rt @ np.array([s * 2.0, 0, -.6])), C @ Rt @ roty(math.radians(s * 40)) / sc, (2.6 * sc, 2.7 * sc, 1.0 * sc), A['paul'], .9)
            else: r.ellipsoid(W_(S + Rt @ np.array([s * .6, 0, .9])), C @ Rt / sc, (2.5 * sc, 2.4 * sc, 1.4 * sc), A['paul'], .95)
        r.limb(W_(S), W_(el), 2.2 * sc, 1.9 * sc, A['arm'], .95)
        if sp.get('sleeve') == 'short':
            r.limb(W_(el), W_(el + (hd - el) * .25), 1.95 * sc, 1.9 * sc, A['arm'], .95); r.limb(W_(el + (hd - el) * .2), W_(hd), 1.45 * sc, 1.2 * sc, 'skin', .95)
        else: r.limb(W_(el), W_(hd), 1.85 * sc, 1.4 * sc, A['arm'], .95)
        br = sp.get('brace')
        if br:                                                 # 아대(팔뚝 보호대): 손목~팔뚝 중간
            r.limb(W_(el + (hd - el) * .3), W_(el + (hd - el) * .93), 1.85 * sc, 1.55 * sc, br, 1.05)
            if br == 'plate': r.limb(W_(el + (hd - el) * .88), W_(el + (hd - el) * .97), 1.75 * sc, 1.75 * sc, 'iron', .9)
        r.sphere(W_(hd), 1.2 * sc, mat_hand, 1.2)                                          # 손: 작은 밝은 점
        return el, hd
    if sp.get('xbow'):                                         # 석궁: 개머리(xb)·개머리→앞 방향(xd)·조준(xaim)·시위 걸림(span)·화살(bolt)·왼손(xl)·시위 당기기(xpull)
        B = sho[1] + Rt @ np.asarray(P['xb'], float)
        d = Rt @ nrm(P['xd']); xa = P['xaim']
        if xa > 0: d = nrm((1 - xa) * d + xa * nrm(TARGET_FAR - B))
        upw = np.array([0, 0, 1.0]); sd = np.cross(d, upw)
        sd = nrm(sd) if np.linalg.norm(sd) > .2 else nrm(Rt @ np.array([1.0, 0, 0]) - (Rt @ np.array([1.0, 0, 0]) @ d) * d)
        dn = nrm(np.cross(sd, d))                              # 석궁 기준 '위'
        P0 = B + d * 16.50; nut = B + d * (15.6 - 8.4 * P['span'])
        g_r = B + d * 5.10 - dn * .9; g_l = B + d * 12.30 - dn * .7
        pl = P['xpull']; n_r, n_l = nut + sd * 1.65 + dn * .4, nut - sd * 1.65 + dn * .4
        rt = (1 - pl) * g_r + pl * n_r
        lfree = sho[-1] + np.asarray(P['lh'], float)
        lt = (1 - pl) * ((1 - P['xl']) * lfree + P['xl'] * g_l) + pl * n_l
        el_l, hl = arm(-1, lt - sho[-1], Rt @ np.array([-1, -.4, -.6]))
        _, hr = arm(1, rt - sho[1], Rt @ (np.array([1, -.6, -.5]) * (1 - P.get('elb', 0)) + np.array([.2, -1, -.2]) * P.get('elb', 0)))
        r.limb(W_(B - dn * .2), W_(B + d * 4.50), .95 * sc, .7 * sc, 'leather', 1.25)                       # 개머리
        r.limb(W_(B + d * 3.90), W_(P0 + d * .9), .62 * sc, .55 * sc, 'wood', 1.1, step=.8)              # 몸통(나무)
        bend = P['span']
        tips = []
        for s_ in (-1, 1):                                     # 활대(철): 시위가 걸리면 뒤로 더 휨
            a = P0; b = P0 + sd * s_ * 4.50 - d * (.75 + .75 * bend); c = P0 + sd * s_ * 8.40 - d * (2.1 + 1.95 * bend)
            r.limb(W_(a), W_(b), .42 * sc, .38 * sc, 'iron', 1.0, step=.8); r.limb(W_(b), W_(c), .38 * sc, .3 * sc, 'iron', 1.0, step=.8)
            tips.append(c)
        for c in tips: r.limb(W_(c), W_(nut), .17 * sc, .17 * sc, 'quilt', 1.5, step=.8)                  # 시위
        r.limb(W_(P0 + d * .9 - sd * 1.35), W_(P0 + d * 2.40), .22 * sc, .22 * sc, 'iron', .9, step=.8)         # 등자(고리)
        r.limb(W_(P0 + d * .9 + sd * 1.35), W_(P0 + d * 2.40), .22 * sc, .22 * sc, 'iron', .9, step=.8)
        tip = P0 + d * 2.40
        if P['bolt'] > .5:
            bt = nut + dn * .35; tip = bt + d * 10.80
            r.limb(W_(bt), W_(tip), .26 * sc, .26 * sc, 'wood', 1.3, step=.8); r.sphere(W_(tip), .42 * sc, 'iron', 1.2)
        if sp.get('quiver'):                                    # 볼트 통: 오른쪽 허리
            q0 = pel + Rt @ np.array([4.6, -1.2, -1.0]); q1 = pel + Rt @ np.array([4.9, -1.8, 5.5])
            r.limb(W_(q0), W_(q1), 1.1 * sc, 1.2 * sc, 'belt', 1.0)
            for o in (-.4, 0, .4): r.sphere(W_(q1 + Rt @ np.array([o, 0, .7])), .38 * sc, 'chest', 1.1)
    elif sp.get('bowspec'):
        bs = sp['bowspec']; aw = P['aimw']; dr = P['draw']; bi = P['bind']
        anchor = headc + Rt @ np.array([.9, .7, -2.3])          # 입꼬리 기준점
        aimdir = nrm(TARGET_FAR - anchor)
        grip_aim = anchor + aimdir * bs['ld']                   # 화살선이 기준점→손잡이→목표점 일직선
        lt = (1 - aw) * (sho[-1] + np.asarray(P['lh'], float)) + aw * grip_aim
        el_l, hl = arm(-1, lt - sho[-1], Rt @ np.array([-1, -.4, -.6]))
        up = nrm((1 - aw) * (Rt @ nrm(P['bowup'])) + aw * np.array([.12, 0, 1.0]))
        fw = (1 - aw) * (Rt @ np.array([0, 1.0, 0])) + aw * aimdir; fw = nrm(fw - (fw @ up) * up)
        k = .9 + 1.8 * dr; h = bs['h']
        pts = [hl + up * h * s - fw * k * s * s for s in np.linspace(-1, 1, 13)]
        r.cur_tag = 1
        for i in range(12):
            rad = (.9 if 4 <= i <= 7 else .75) * sp.get('bowthick', 1.0)       # 도트 2px 규칙: 활대는 후처리에서 2px 격자선으로 굳힘
            r.limb(W_(pts[i]), W_(pts[i + 1]), rad * sc, rad * sc, 'bowwood', 2.1 if 4 <= i <= 7 else 1.9, step=.9)
        r.cur_tag = 0
        if bs.get('rune'):
            for s in (-.7, -.35, .35, .7): r.sphere(W_(hl + up * h * s - fw * k * s * s + fw * .3), .5 * sc, 'iron', 1.4)
        mid = (pts[0] + pts[-1]) / 2
        nock = (1 - dr) * mid + dr * anchor
        free = sho[1] + np.asarray(P['rh'], float)
        rt = (1 - bi) * free + bi * nock
        _, hr = arm(1, rt - sho[1], Rt @ np.array([1, -.6, -.5]))
        spt = hr if bi > .5 else mid
        r.limb(W_(pts[0]), W_(spt), .3 * sc, .3 * sc, 'quilt', 1.5, step=.9)       # 시위: 어두운 줄(쇠처럼 번쩍이지 않게)
        r.limb(W_(pts[-1]), W_(spt), .3 * sc, .3 * sc, 'quilt', 1.5, step=.9)
        tip = pts[-1]
        if P['arrow'] > .5 and bi > .5:
            ad = nrm(hl + up * .4 - spt); tip = spt + ad * bs['al']
            r.limb(W_(spt - ad * .4), W_(tip), .28 * sc, .28 * sc, 'wood', 1.3, step=.9)
            r.sphere(W_(tip), .5 * sc, 'iron', 1.3)
            r.sphere(W_(spt + ad * .9), .45 * sc, 'chest', 1.2)
        elif P['carry'] > .5:
            ad = nrm(Rt @ np.array([.1, .4, .9])); tip = hr + ad * 9
            r.limb(W_(hr - ad * 3), W_(tip), .28 * sc, .28 * sc, 'wood', 1.3, step=.9)
        if sp.get('quiver'):                                    # 화살통: 등 오른쪽, 위로 기울어짐
            qs = sp.get('qscale', 1.0)
            q0 = pel + Rt @ np.array([2.4, -4.6 - .6 * (qs - 1), 5.0 - 2.0 * (qs - 1)]); q1 = pel + Rt @ np.array([3.6, -5.2 - .6 * (qs - 1), 13.0 + 1.5 * (qs - 1)])
            r.limb(W_(q0), W_(q1), 1.3 * qs * sc, 1.5 * qs * sc, 'belt', 1.0)
            na = sp.get('arrows', 2)
            for o in np.linspace(-.7 * qs, .7 * qs, na) if na > 1 else [0.0]: r.sphere(W_(q1 + Rt @ np.array([o, (o * 1.7) % .5 - .25, 1.0 + .6 * ((o * 3) % 1)])), .45 * sc, 'chest', 1.1)
    else:
        wp = sp.get('weapon', WEAPONS['arming'])
        # 오른손 위치·무기 방향 먼저 계산(양손무기는 왼손이 손잡이를 잡음)
        el0, hr0 = ik(sho[1], sho[1] + np.asarray(P['rh'], float), UP_A, FO_A, Rt @ (np.array([1, -.6, -.5]) * (1 - P.get('elb', 0)) + np.array([.2, -1, -.2]) * P.get('elb', 0)))
        bd = nrm(P['blade']); bd = Rt @ bd if P.get('blade_local', True) else bd
        a = P.get('aim', 0.0)
        if a > 0: bd = nrm((1 - a) * bd + a * nrm(TARGET - hr0))
        bd = fix_blade(bd, hr0, el0, pel, neck, wp)
        lh_t = (hr0 - bd * wp.get('grip2', 2.6)) - sho[-1] if wp.get('twohand') else P['lh']
        el_l, hl = arm(-1, lh_t, Rt @ (np.array([-1, -.4, -.6]) * (1 - P.get('elb', 0)) + np.array([-.2, -1, -.2]) * P.get('elb', 0)))
        off = sp.get('offhand', 'round') if not wp.get('twohand') else None
        if off in SHIELDS:                   # 앤암스(enarmes): 팔뚝에 끈으로 고정, 방패 면이 팔뚝을 따라감
            rw, rl, mat, boss = SHIELDS[off]
            u = nrm(hl - el_l)
            n0 = Rt @ np.array([-.45, 1, .15]); n = nrm(n0 - (n0 @ u) * u)
            v = np.cross(u, n); M = np.stack([v, u, n], 1)
            ctr = el_l + (hl - el_l) * .62 + n * 1.5 + u * (rl - 4.9) * .35
            r.ellipsoid(W_(ctr), C @ M / sc, (rw * sc, rl * sc, .7 * sc), mat, 1.25)
            r.ellipsoid(W_(ctr + n * .05), C @ M / sc, ((rw + .2) * sc, (rl + .2) * sc, .55 * sc), 'iron', .85)
            if boss: r.sphere(W_(ctr + n * .7), .9 * sc, 'iron', 1.0)
        elif off == 'dagger':                # 패링대거: 왼손에 짧은 칼, 칼끝은 앞·위
            dd = nrm(Rt @ np.array([.2, .8, .55]))
            r.limb(W_(hl - nrm(np.cross(dd, [0, 0, 1.0]) + 1e-6) * 1.4), W_(hl + nrm(np.cross(dd, [0, 0, 1.0]) + 1e-6) * 1.4), .45 * sc, .45 * sc, 'iron', .8)
            r.limb(W_(hl + dd * .6), W_(hl + dd * 5.5), .6 * sc, .3 * sc, 'iron', 1.3, step=.9)
        _, hr = arm(1, P['rh'], Rt @ (np.array([1, -.6, -.5]) * (1 - P.get('elb', 0)) + np.array([.2, -1, -.2]) * P.get('elb', 0)))
        # 무기
        if P.get('sheath', 0) > .5 and wp['kind'] in ('sword', 'rapier'):    # 평상시: 왼쪽 허리 칼집에 꽂음
            hr, bd, throat = sheath_geo(P); hr = throat - bd * .3
            r.limb(W_(throat - bd * .2), W_(throat + bd * (wp['len'] * .95)), (wp['w0'] + .35) * sc, (wp['w1'] + .3) * sc, 'leather', 1.15)
            r.limb(W_(throat + bd * (wp['len'] * .9)), W_(throat + bd * wp['len']), (wp['w1'] + .4) * sc, (wp['w1'] + .3) * sc, 'iron', .9)
        L = wp['len'] * P['bk']; tip = hr + bd * L
        gd = nrm(np.cross(bd, Rt @ np.array([0, 0, 1.0])) + 1e-6)
        k = wp['kind']
        if k in ('sword', 'rapier'):
            g = wp.get('guard', 1.5)
            r.limb(W_(hr - gd * g), W_(hr + gd * g), .5 * sc, .5 * sc, 'iron', .8)
            if k == 'rapier': r.sphere(W_(hr + bd * .5), 1.2 * sc, 'iron', .9)
            if not (P.get('sheath', 0) > .5): r.limb(W_(hr + bd * .8), W_(tip), wp['w0'] * sc, wp['w1'] * sc, 'iron', 1.3, step=.9)
            r.limb(W_(hr - bd * wp.get('grip', 1.3)), W_(hr), .5 * sc, .5 * sc, 'wood', 1.0)
            if wp.get('twohand'): r.sphere(W_(hr - bd * (wp.get('grip', 1.3) + .4)), .7 * sc, 'iron', .9)
        elif k == 'axe':
            r.limb(W_(hr - bd * 1.0), W_(tip), .55 * sc, .5 * sc, 'wood', 1.0)
            e = nrm(np.cross(gd, bd))                     # 날이 휘두르는 쪽(앞)
            hc = tip - bd * 1.4 + e * 1.4
            r.ellipsoid(W_(hc), C @ np.stack([e, bd, gd], 1) / sc, (2.0 * sc, 1.7 * sc, .45 * sc), 'iron', 1.3)
        elif k == 'mace':
            r.limb(W_(hr - bd * 1.0), W_(tip - bd * 1.2), .55 * sc, .5 * sc, 'wood', 1.0)
            bc = tip
            r.sphere(W_(bc), 1.9 * sc, 'iron', 1.15)
            for sv in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                r.sphere(W_(bc + np.array(sv, float) * 2.0), .55 * sc, 'iron', 1.3)
    if P.get('vial', 0) > .5:                                  # 물약병: 활은 오른손, 석궁은 왼손에 쥔 작은 병
        hv = hl if sp.get('xbow') else hr
        r.ellipsoid(W_(hv + Rt @ np.array([0, .6, .9])), C @ Rt / sc, (.8 * sc, .8 * sc, 1.5 * sc), 'iron', 1.25)
        r.sphere(W_(hv + Rt @ np.array([0, .6, 2.3])), .45 * sc, 'wood', 1.0)
    # 머리·투구
    if P.get('hdrop', 0) or P.get('hturn', 0):                 # 머리만 숙임(hdrop +앞)·돌림(hturn): 목을 축으로
        Rt = Rt @ rotx(-math.radians(P['hdrop'])) @ rotz(math.radians(P['hturn'])); headc = neck + Rt @ np.array([0, .3, 3.6])
    def H_(v): return W_(headc + Rt @ np.array(v, float))
    Rh0 = C @ Rt / sc
    SK_ = 'skinsh' if sp.get('head') == 'clothhood' else 'skin'
    r.limb(W_(neck - Rt @ np.array([0, .2, 1.2])), H_((0, -.2, -1.6)), 1.35 * sc, 1.25 * sc, SK_, .8)          # 목
    r.ellipsoid(H_((0, -.7, .5)), Rh0, (2.3 * sc, 2.6 * sc, 2.65 * sc), SK_, 1.0)                              # 머리통: 뒤통수가 나온 긴 두개골
    r.ellipsoid(H_((0, 1.25, -.35)), Rh0, (1.75 * sc, 1.05 * sc, 2.0 * sc), SK_, 1.05)                         # 얼굴 앞판(평평한 면)
    for s in (-1, 1): r.ellipsoid(H_((s * 1.25, 1.45, -.15)), Rh0, (.65 * sc, .6 * sc, .55 * sc), SK_, 1.12)   # 광대
    def jaw(q):                                                                                                   # 턱: 아래·앞쪽은 수염 그늘
        m = np.full(q.shape[:-1], SK_, dtype=object); m[(q[..., 2] < -.2) & (q[..., 1] > -.2)] = 'hair'; return m
    r.ellipsoid(H_((0, .8, -1.55)), Rh0, (1.7 * sc, 1.7 * sc, 1.35 * sc), SK_, .9, matfn=jaw)                  # 턱선(좁게)
    r.ellipsoid(H_((0, 1.85, -2.15)), Rh0, (.75 * sc, .5 * sc, .5 * sc), SK_, .85, matfn=jaw)                   # 턱끝
    r.ellipsoid(H_((0, 2.05, .75)), Rh0, (1.9 * sc, .55 * sc, .42 * sc), SK_, 1.15)                           # 눈두덩(밝게 튀어나옴)
    for s in (-1, 1):
        r.ellipsoid(H_((s * .75, 2.1, .2)), Rh0, (.62 * sc, .4 * sc, .34 * sc), 'hair', .6)                       # 눈구멍 그늘(넓게)
        r.ellipsoid(H_((s * 2.45, -.1, -.1)), Rh0, (.4 * sc, .6 * sc, .8 * sc), SK_, .85)                      # 귀
    r.ellipsoid(H_((0, 2.45, -.35)), Rh0, (.42 * sc, .6 * sc, .95 * sc), SK_, 1.3)                            # 코(콧대)
    r.ellipsoid(H_((0, 2.15, -1.35)), Rh0, (.7 * sc, .3 * sc, .18 * sc), 'hair', .7)                           # 입 그늘
    hd_ = sp.get('head')
    Rh = C @ Rt / sc
    if hd_ in ('bare', 'leathercap', 'clothhood', 'hat', 'coif'):
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.5, .9])), Rh, (2.85 * sc, 2.9 * sc, 2.4 * sc), 'hair', 1.0, clip=lambda q: q[..., 1] < .35)
    if hd_ == 'leathercap':                                    # 가죽모자: 낮은 돔 + 테
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.1, .9])), Rh, (3.1 * sc, 3.1 * sc, 2.6 * sc), 'leather', 1.0, clip=lambda q: q[..., 2] > -.1)
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.1, .6])), Rh, (3.7 * sc, 3.7 * sc, .45 * sc), 'leather2', 1.0)
    if hd_ == 'clothhood':                                     # 천 후드: 얼굴을 깊게 감싸고 정수리가 뾰족, 등으로 꼬리, 어깨 망토
        def opening(q):                                        # 얼굴 앞 창(타원)만 뚫음
            return ~((q[..., 1] > .2) & ((q[..., 0] / .62) ** 2 + ((q[..., 2] + .12) / .62) ** 2 < 1))
        r.ellipsoid(H_((0, -.35, .3)), Rh, (3.35 * sc, 3.7 * sc, 3.6 * sc), 'hood', 1.0, clip=opening)
        r.ellipsoid(H_((0, -.9, 2.9)), C @ Rt @ rotx(math.radians(-35)) / sc, (1.5 * sc, 1.9 * sc, 1.6 * sc), 'hood', 1.0)   # 뾰족한 정수리
        r.limb(H_((0, -2.6, 1.6)), H_((0, -4.0, -4.0)), 1.1 * sc, .45 * sc, 'hood2', .9)                             # 등 꼬리(리리파이프)
        for i in range(4):                                     # 어깨 망토: 목에서 가슴 위까지 퍼지는 원뿔
            t = i / 3; zc = -3.4 - 2.2 * t
            def cape(q, t=t):
                m = np.full(q.shape[:-1], 'hood', dtype=object); m[q[..., 2] < -.3] = 'hood2'; return m
            r.ellipsoid(H_((0, -.3, zc)), Rh, ((3.6 + 2.0 * t) * sc, (3.3 + 1.2 * t) * sc, 1.2 * sc), 'hood', .95, matfn=cape)
        r.ellipsoid(H_((0, 1.6, -.1)), Rh, (1.9 * sc, .5 * sc, 2.0 * sc), 'coat', .6, clip=lambda q: q[..., 1] < 0)   # 두건 안 그늘(얼굴 뒤)
    if hd_ == 'deephood':                                      # 궁수 후드 망토: 머리보다 훨씬 큰 천 덩어리, 깊은 얼굴 구멍, 뒤로 처진 뾰족 끝, 어깨·팔 위까지 덮는 망토
        hm = sp.get('hoodmat', 'wool'); hm2 = 'wool2'
        def hole(q):                                           # 얼굴 앞 구멍: 앞쪽 좁은 세로 타원
            return ~((q[..., 1] > .15) & ((q[..., 0] / .56) ** 2 + ((q[..., 2] + .12) / .66) ** 2 < 1))
        def shade(q):                                          # 아래·뒤쪽은 접힌 그늘
            m = np.full(q.shape[:-1], hm, dtype=object); m[(q[..., 2] < -.45) | (q[..., 1] < -.6)] = hm2; return m
        r.ellipsoid(H_((0, -.8, .2)), Rh, (3.9 * sc, 4.6 * sc, 3.8 * sc), hm, 1.05, clip=hole, matfn=shade)         # 부푼 후드 몸체
        def rim(q): return ((q[..., 0] / .78) ** 2 + ((q[..., 2] + .02) / .86) ** 2 > .45)
        r.ellipsoid(H_((0, 2.25, .0)), Rh, (2.6 * sc, .6 * sc, 3.0 * sc), hm, 1.2, clip=rim)                       # 얼굴 둘레 테(밝은 접힘)
        r.ellipsoid(H_((0, -3.4, 2.4)), C @ Rt @ rotx(math.radians(35)) / sc, (1.7 * sc, 2.6 * sc, 1.5 * sc), hm, .95)       # 뒤로 처진 끝
        r.ellipsoid(H_((0, -4.9, .4)), C @ Rt @ rotx(math.radians(60)) / sc, (.9 * sc, 2.0 * sc, .8 * sc), hm2, .9)   # 뒤로 처진 뾰족 끝
        r.ellipsoid(H_((0, 1.3, 1.1)), Rh, (2.0 * sc, .6 * sc, 1.0 * sc), 'coat', .5, clip=lambda q: q[..., 1] < 0)        # 이마 위 그늘(얼굴 아래는 보임)
        for i in range(6):                                     # 망토: 목에서 어깨·팔 윗부분까지 퍼지며 등쪽이 더 길게
            t = i / 5; zc = -3.0 - 4.2 * t
            def cape(q, t=t):
                m = np.full(q.shape[:-1], hm, dtype=object); m[(q[..., 2] < -.2) | (q[..., 1] < -.75)] = hm2; return m
            c_ = H_((0, -.6 - 1.0 * t, zc))
            r.ellipsoid(c_, Rh, ((4.2 + 3.4 * t) * sc, (3.8 + 1.4 * t) * sc, 1.3 * sc), hm, 1.1 - .15 * t, matfn=cape,
                        clip=(lambda q, t=t: q[..., 1] < .55 - .5 * t) if t > .5 else None)                          # 아래쪽은 앞을 열어 가슴이 보임
    if hd_ == 'coif':                                          # 천 두건: 머리에 딱 붙고 귀·턱을 감쌈, 얼굴만 열림
        def op2(q): return ~((q[..., 1] > .25) & ((q[..., 0] / .66) ** 2 + ((q[..., 2] + .1) / .72) ** 2 < 1))
        r.ellipsoid(H_((0, -.45, .35)), Rh, (3.05 * sc, 3.3 * sc, 3.2 * sc), 'wool', 1.0, clip=op2)
        r.ellipsoid(H_((0, -.3, -3.2)), Rh, (3.6 * sc, 3.0 * sc, 1.0 * sc), 'wool2', .9)                                  # 목 덮개
    if hd_ == 'hat':                                           # 챙 넓은 펠트 모자: 낮은 둥근 크라운 + 앞이 살짝 숙은 넓은 챙
        Rb = C @ Rt @ rotx(math.radians(-7)) / sc
        def brim(q):
            m = np.full(q.shape[:-1], 'felt', dtype=object); m[q[..., 2] < -.2] = 'hood2'; return m
        r.ellipsoid(H_((0, .1, 1.05)), Rb, (6.2 * sc, 5.8 * sc, .4 * sc), 'felt', .95, matfn=brim)
        r.ellipsoid(H_((0, -.2, 2.1)), Rh, (2.9 * sc, 2.95 * sc, 2.8 * sc), 'felt', 1.0, clip=lambda q: q[..., 2] > -.2)
        r.ellipsoid(H_((0, -.2, 1.4)), Rh, (3.15 * sc, 3.2 * sc, .45 * sc), 'belt', .9)                                  # 모자 띠
    if hd_ == 'kettle':                                        # 삶은 가죽 챙투구(케틀 모양) + 안에 천 두건
        def op2(q): return ~((q[..., 1] > .25) & ((q[..., 0] / .66) ** 2 + ((q[..., 2] + .1) / .72) ** 2 < 1))
        r.ellipsoid(H_((0, -.45, .35)), Rh, (3.05 * sc, 3.3 * sc, 3.2 * sc), 'wool', 1.0, clip=op2)
        r.ellipsoid(H_((0, -.3, -3.2)), Rh, (3.6 * sc, 3.0 * sc, 1.0 * sc), 'wool2', .9)
        Rb = C @ Rt @ rotx(math.radians(-9)) / sc
        def brim(q):
            m = np.full(q.shape[:-1], 'leather2', dtype=object); m[q[..., 2] < -.2] = 'leather'; return m
        r.ellipsoid(H_((0, .0, 1.3)), Rb, (4.7 * sc, 4.6 * sc, .42 * sc), 'leather2', 1.15, matfn=brim)
        r.ellipsoid(H_((0, -.2, 1.5)), Rh, (3.25 * sc, 3.3 * sc, 2.5 * sc), 'leather2', 1.05, clip=lambda q: q[..., 2] > -.05)
        r.limb(H_((0, -3.2, 2.0)), H_((0, 3.1, 2.0)), .32 * sc, .32 * sc, 'belt', 1.0)                                     # 가운데 이음 띠
    if hd_ == 'bighood':                                       # 큰 후드(그림자 사수): deephood보다 크고 뾰족, 얼굴 아래 가리개
        hm = sp.get('hoodmat', 'cloak'); hm2 = 'cloak2'
        def hole(q): return ~((q[..., 1] > .15) & ((q[..., 0] / .5) ** 2 + ((q[..., 2] + .05) / .6) ** 2 < 1))
        def shade(q):
            m = np.full(q.shape[:-1], hm, dtype=object); m[(q[..., 2] < -.45) | (q[..., 1] < -.6)] = hm2; return m
        r.ellipsoid(H_((0, -1.0, .5)), Rh, (4.3 * sc, 5.0 * sc, 4.3 * sc), hm, 1.05, clip=hole, matfn=shade)
        def rim(q): return ((q[..., 0] / .78) ** 2 + ((q[..., 2] + .02) / .86) ** 2 > .45)
        r.ellipsoid(H_((0, 2.4, .1)), Rh, (2.8 * sc, .6 * sc, 3.2 * sc), hm, 1.2, clip=rim)
        r.ellipsoid(H_((0, -2.6, 3.6)), C @ Rt @ rotx(math.radians(40)) / sc, (1.8 * sc, 3.4 * sc, 1.6 * sc), hm, .95)       # 위로 솟은 뾰족 끝
        r.ellipsoid(H_((0, -4.6, 4.6)), C @ Rt @ rotx(math.radians(55)) / sc, (.9 * sc, 2.6 * sc, .8 * sc), hm2, .9)
        r.ellipsoid(H_((0, 1.6, -1.1)), Rh, (2.0 * sc, 1.0 * sc, 1.1 * sc), 'hood2', .8)                                   # 얼굴 아래 가리개(코·입 덮음)
        r.ellipsoid(H_((0, 1.3, 1.1)), Rh, (2.0 * sc, .6 * sc, 1.0 * sc), 'coat', .5, clip=lambda q: q[..., 1] < 0)
    if hd_ == 'greathelm':                                     # 전면투구: 머리 전체를 덮는 원통형, 눈구멍 띠
        def gm(q):
            m = np.full(q.shape[:-1], 'helm', dtype=object)
            m[(q[..., 1] > .55) & (np.abs(q[..., 2] - .15) < .1)] = 'coat'; return m
        r.ellipsoid(W_(headc + Rt @ np.array([0, 0, .5])), Rh, (3.3 * sc, 3.4 * sc, 3.6 * sc), 'helm', 1.0, matfn=gm)
        r.ellipsoid(W_(headc + Rt @ np.array([0, 0, 2.6])), Rh, (3.0 * sc, 3.1 * sc, 1.2 * sc), 'helm', 1.1)
    if sp.get('head') == 'hood':                               # 두건: 얼굴 앞은 열림, 어깨 덮개
        Rh = C @ Rt / sc
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.5, .4])), Rh, (3.3 * sc, 3.7 * sc, 3.4 * sc), 'hood', 1.0, clip=lambda q: q[..., 1] < .5)
        r.ellipsoid(W_(neck + Rt @ np.array([0, -.3, -.4])), Rh, (4.6 * sc, 3.9 * sc, 1.8 * sc), 'hood', 1.0)
    if sp.get('head') == 'helm':
        Rh = C @ Rt / sc
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.2, 1.0])), Rh, (3.2 * sc, 3.2 * sc, 2.9 * sc), 'helm', 1.0, clip=lambda q: q[..., 2] > -.05)
        r.ellipsoid(W_(headc + Rt @ np.array([0, -.2, 1.0])), Rh, (3.8 * sc, 3.8 * sc, .35 * sc), 'helm', .6)
    return W_(tip), W_(hr)

def render(sp, P, dname, trail=None):
    r = Raster()
    tip, _ = build(r, sp, P, DIRS[dname])
    im = r.cv.image()
    if getattr(r, 'tag', None) is not None and r.tag.any(): im = _solid_prop(r, im)
    if not trail: return _cap(im), tip
    if trail:                                    # 칼끝 잔상: 매끈한 곡선 띠(오래된 쪽일수록 가늘고 옅게)
        K = 4; pts = np.array([proj(p) for p in trail], float) * K
        keep = [pts[0]]                          # 경로가 되돌아가는 지점(쿠션 반동)에서 끊어 고리 방지
        for p in pts[1:]:
            if len(keep) >= 2:
                u = keep[-1] - keep[-2]; v = p - keep[-1]
                if np.dot(u, v) < -.2 * np.hypot(*u) * np.hypot(*v): break
            if np.hypot(*(p - keep[-1])) > .05: keep.append(p)
        pts = np.array(keep)
        if len(pts) < 3: return _cap(im), tip
        for _ in range(3):                       # Chaikin 곡선 다듬기
            q = [pts[0]]
            for a, b in zip(pts[:-1], pts[1:]): q += [a * .75 + b * .25, a * .25 + b * .75]
            q.append(pts[-1]); pts = np.array(q)
        n = len(pts); mask = Image.new('L', (W * K, H * K)); dr = ImageDraw.Draw(mask)
        def half(i): return K * 1.25 * (1 - i / (n - 1)) ** .8 + .3
        nor = []
        for i in range(n):
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]; L = np.hypot(*t) or 1
            nor.append(np.array([-t[1], t[0]]) / L)
        for i in range(n - 2, -1, -1):          # 오래된 쪽부터 그려 새 쪽이 덮음(이음매 없음)
            a, b = pts[i], pts[i + 1]; ha, hb = half(i), half(i + 1)
            poly = [tuple(a + nor[i] * ha), tuple(b + nor[i + 1] * hb), tuple(b - nor[i + 1] * hb), tuple(a - nor[i] * ha)]
            dr.polygon(poly, fill=int(95 * (1 - i / (n - 1)) ** 1.3))
        mask = mask.resize((W, H), Image.LANCZOS)
        layer = Image.new('RGBA', (W, H), (165, 160, 150, 0)); layer.putalpha(mask)
        layer.alpha_composite(im); im = layer
    return _cap(im), tip

BOW_COV, BOW_GAIN, BOW_ADD, BOW_MAX = .2, 1.05, 14, 118
def _solid_prop(r, im):
    """활대처럼 얇은 소품은 2x2 도트 칸 단위로 덮인 비율이 BOW_COV 이상이면 불투명한 한 도트로 굳힌다(컨셉 창대처럼 2px 선)."""
    B = 2 * SS; hh, ww = H // 2 * 2, W // 2 * 2
    tg = r.tag[:hh * SS, :ww * SS].reshape(hh // 2, B, ww // 2, B).astype(float)
    cov = tg.mean((1, 3))
    rgbw = (r.cv.rgb[:hh * SS, :ww * SS] * r.tag[:hh * SS, :ww * SS, None]).reshape(hh // 2, B, ww // 2, B, 3).sum((1, 3)) / np.maximum(tg.sum((1, 3)), 1e-6)[..., None]
    col = (rgbw * BOW_GAIN + BOW_ADD).clip(0, BOW_MAX)
    a = np.asarray(im).astype(np.float32).copy()
    m = cov >= BOW_COV
    mk = np.kron(m, np.ones((2, 2), bool)); ck = np.kron(col, np.ones((2, 2, 1)))
    sub = a[:hh, :ww]; sub[mk, :3] = ck[mk]; sub[mk, 3] = 255; a[:hh, :ww] = sub
    return Image.fromarray(a.round().astype(np.uint8), 'RGBA')

LMAX = 194                                       # 아트 바이블 v2: 최고 밝기 #c2c2bf, 넘는 픽셀은 색조 유지한 채 낮춤
def _cap(im):
    a = np.asarray(im).astype(np.float32); m = a[..., :3].max(-1, keepdims=True)
    a[..., :3] *= np.minimum(1.0, LMAX / np.maximum(m, 1)); return Image.fromarray(a.round().astype(np.uint8), 'RGBA')

def tip_of(sp, P, dname):
    class Null:
        def __getattr__(s, k): return lambda *a, **kw: None
    return build(Null(), sp, P, DIRS[dname])[0]
