"""v5 8방향 애니메이션: 정지·걷기·3연타 콤보(캐릭터 공간 키포즈)."""
import sys, os, math, copy; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from fig8 import *

def ease(t): t = min(1, max(0, t)); return t * t * (3 - 2 * t)
def slerp(u, v, t):
    u, v = np.asarray(u, float), np.asarray(v, float)
    lu, lv = np.linalg.norm(u) or 1e-6, np.linalg.norm(v) or 1e-6
    du, dv = u / lu, v / lv; om = math.acos(max(-1, min(1, du @ dv)))
    if om < 1e-4: d = du
    else: d = (math.sin((1 - t) * om) * du + math.sin(t * om) * dv) / math.sin(om)
    return tuple(d / np.linalg.norm(d) * (lu + (lv - lu) * t))
def mix(a, b, t):
    o = {}
    for k in a:
        if k in ('rh', 'blade'): o[k] = slerp(a[k], b[k], t); continue   # 손·칼은 어깨 중심 호를 그리며 이동
        va, vb = a[k], b[k]
        if isinstance(va, (tuple, list)): o[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
        else: o[k] = va + (vb - va) * t
    return o
def P(**kw):
    p = base_pose(); p.update(kw); return p
def ext(d, reach=UP_A + FO_A - .2):            # 팔을 끝까지 뻗은 손 위치
    d = np.asarray(d, float); d = d / np.linalg.norm(d); return tuple(d * reach)

NF = 24
def idle(i):
    b = math.sin(2 * math.pi * i / NF)
    if GK[0] == 'AG':                    # 궁수 평상시: 활을 왼손에 세워 몸 바깥쪽으로 비스듬히(실루엣 밖으로 보이게)
        return P(drop=.25 * (1 - b) * .5, sr=.2 * b, rh=(1.0, 2.0, -13.6 + .3 * b), lh=(-5.4, 2.4, -13.2 + .3 * b), bowup=(-.2, .1, .97), lean=3.0, fL=(-2.9, .6, 0.0), fR=(2.9, -.6, 0.0))   # v3 민첩형 정지 자세와 동일   # 컨셉 창병처럼 팔은 옆에 늘어뜨리고 활은 세워 듦
    return P(drop=.25 * (1 - b) * .5, sr=.2 * b, rh=(1.0, 2.0, -13.6 + .3 * b), lh=(-.6, 4.5, -10.5 + .3 * b), sheath=SHEATHED[0])
GK = ['G']
SHEATHED = [0.0]                         # 평상시 칼을 허리 칼집에 차는지(검·레이피어)                               # 현재 준비자세 키(전사 G, 궁수 AG)
def combat_idle(i):                     # 전투 준비자세 숨쉬기(24f)
    b = math.sin(2 * math.pi * i / NF); c = math.cos(2 * math.pi * i / NF); G = K[GK[0]]
    p = dict(G); p.update(drop=G['drop'] + .35 * (1 - b) * .5, lean=G['lean'] + .8 * b, sr=G['sr'] + .2 * b,
        rh=(G['rh'][0] + .3 * c, G['rh'][1], G['rh'][2] + .4 * b), lh=(G['lh'][0], G['lh'][1], G['lh'][2] + .3 * b))
    return p
def combat_walk(i):                      # 준비자세 그대로 걷기(24f): 다리는 걷기, 상체·팔·무기는 준비자세
    w = walk(i); G = K[GK[0]]; ph = 2 * math.pi * i / NF
    p = dict(G); p.update(fL=(G['fL'][0], w['fL'][1] * .8, w['fL'][2] * .8), fR=(G['fR'][0], w['fR'][1] * .8, w['fR'][2] * .8),
        drop=G['drop'] * .7 + w['drop'], twist=G['twist'] + 3 * math.sin(ph), lean=G['lean'] + 1.5,
        rh=(G['rh'][0], G['rh'][1], G['rh'][2] + .5 * abs(math.sin(ph))), lh=(G['lh'][0], G['lh'][1], G['lh'][2] + .4 * abs(math.sin(ph))))
    return p
def walk(i):
    ph = 2 * math.pi * i / NF; s, c = math.sin(ph), math.cos(ph)
    fl = (-2.4, 4.2 * s, max(0, 2.0 * c)); fr = (2.4, -4.2 * s, max(0, -2.0 * c))
    return P(drop=.6 * abs(math.cos(ph)) - .2, fL=fl, fR=fr, twist=4 * s, lean=4,
             rh=(1.0, 2.0 - 3.0 * s, -13.4 + .6 * abs(s)), lh=(-.6, 4.5 + 1.5 * s, -10.5), sheath=SHEATHED[0])
NR = 16                                   # 뛰기 한 주기(24fps 기준 16프레임)
def run_soft(i):                          # 전투 뛰기용 다리(보폭 작게)
    ph = 2 * math.pi * i / NR; s, c = math.sin(ph), math.cos(ph)
    return dict(fL=(-2.2, 7.0 * s, max(0, 4.0 * c)), fR=(2.2, -7.0 * s, max(0, -4.0 * c)), drop=1.2 + 1.0 * abs(math.cos(ph)) - .6)
def _rfoot(i, off, x):
    """육상선수형 발: 발은 엉덩이 바로 앞에 닿고(멀리 뻗지 않음), 짧게 디딘 뒤 뒤꿈치를 엉덩이 아래로 접어 올렸다가 무릎을 앞으로 끌어냄.
    왼발 4f·오른발 12f 착지, 디딤 5f"""
    u = ((i - 4 - off) % NR) / NR; st = 5 / NR
    if u < st: t = u / st; return (x, 3.5 - 11.5 * t, 0.0), -1.0 + 2 * t
    t = (u - st) / (1 - st)
    e = t * t * (3 - 2 * t); y = -8.0 + 11.5 * e                         # 공중에서는 앞으로만 이동(뒤로 되돌아가지 않음)
    return (x, y, 5.8 * math.sin(math.pi * t ** .75)), 1.0 - 2 * t
def _rarm(side, a):
    """달리기 팔: 팔꿈치 약 90도, 몸 옆에서 앞뒤로만 흔듦(몸 가운데로 넘어오지 않음).
    a=+1 앞(손이 가슴 높이 앞), 0 지나감(손이 허리 옆), -1 뒤(손이 엉덩이 뒤)"""
    a = max(-1.0, min(1.0, a))
    y = .5 + 6.0 * a if a > 0 else .5 + 6.0 * a
    z = -9.0 + 4.0 * max(0, a) + 1.0 * max(0, -a)
    return (side * 1.3, y, z)
def _run_base(i):
    """평상시 뛰기(육상선수 자세): 발목부터 앞으로 기운 몸, 위아래 출렁임 작게, 팔꿈치 90도로 힘차게 앞뒤"""
    fl, aL = _rfoot(i, 0, -1.8); fr, aR = _rfoot(i, 8, 1.8)
    yb = math.cos(2 * math.pi * (i - 6) / 8)                                # 디딤 가운데 살짝 낮음
    sw = -math.cos(2 * math.pi * (i - 1.5) / NR)                            # 팔·몸통은 사인곡선으로 끊김 없이(+: 오른발 앞 → 왼팔 앞)
    return P(drop=1.1 + .45 * yb, fL=fl, fR=fr, twist=-7 * sw, lean=15, sr=.4 * sw,
             rh=_rarm(1, -sw), lh=_rarm(-1, sw),
             skirt=(0, -2.0 + .3 * yb), elb=1.0, sheath=SHEATHED[0])
def run(i):
    if GK[0] == 'XG': return _run_xbow(i)
    return _run_archer(i) if GK[0] == 'AG' else _run_base(i)
def _run_xbow(i):
    """석궁 뛰기: 낮은 자세, 양손으로 석궁을 가슴 앞에 가로로 들고 뜀"""
    p = _run_base(i); sw = -math.cos(2 * math.pi * (i - 1.5) / NR)
    p.update(drop=p['drop'] + 1.2, lean=p['lean'] + 4, twist=-3 * sw, xb=(-2.2, 2.6, -5.6 + .3 * sw), xd=(-.55, .6, .1), xl=1, elb=.4)
    return p
def _run_archer(i):
    """궁수 뛰기: 몸을 낮추고 더 숙임, 왼손 활은 허리 아래로 내려 앞으로 눕혀 듦(팔은 작게 흔듦)"""
    p = _run_base(i); sw = -math.cos(2 * math.pi * (i - 1.5) / NR)
    p.update(drop=p['drop'] + 1.4, lean=p['lean'] + 5, lh=(-2.2, 2.0 + 1.5 * sw, -12.2 + .5 * max(0, sw)), bowup=(-.15, .93, -.2), elb=.6)
    return p
def combat_run(i):                        # 칼을 든 채 뛰기: 다리는 뛰기, 상체는 준비자세를 앞으로 숙임
    w = run_soft(i); G = K[GK[0]]; ph = 2 * math.pi * i / NR
    p = dict(G); p.update(fL=w['fL'], fR=w['fR'], drop=w['drop'] + G['drop'] * .3, twist=G['twist'] + 5 * math.sin(ph), lean=G['lean'] + 8,
        rh=(G['rh'][0], G['rh'][1] - 1.0, G['rh'][2] + 1.2 * abs(math.sin(ph))), lh=(G['lh'][0], G['lh'][1] - .5, G['lh'][2] + 1.0 * abs(math.sin(ph))))
    return p

# 콤보 키포즈 (오른손 칼, 왼손 방패. 손 위치는 어깨 기준)
K = {
 'R':  P(),
 'G':  P(twist=-12, lean=9, sr=.3, drop=1.8, fL=(-2.9, 4.0, 0), fR=(2.9, -3.0, 0),     # 전투 준비자세: 칼끝 앞으로, 방패 앞, 무릎 굽힘
         rh=(.5, 7.0, -7.5), blade=(-.2, .5, .84), lh=(5.0, 6.0, -5.0), aim=.45, skirt=(0, .4)),
 'W1': P(twist=-35, lean=2, sr=-1.6, drop=-.4, fL=(-2.6, 2.5, 0), fR=(2.6, -2.5, 0),
         rh=(1.5, -2.0, 7.0), blade=(-.25, -.55, .8), lh=(1.5, 7.0, -5.0)),
 'S1': P(twist=40, lean=30, sr=1.2, drop=3.6, fL=(-3.0, 8.0, 0), fR=(2.6, -3.5, 0),
         rh=ext((-.55, .6, -.58)), blade=(-.55, .6, -.58), lh=(.5, 6.0, -7.0), skirt=(0, 1.0)),
 'W2': P(twist=55, lean=22, sr=.8, drop=2.8, fL=(-3.0, 8.0, 0), fR=(2.6, -3.5, 0),
         rh=(-12.0, 3.0, -3.5), blade=(-.75, -.6, .1), lh=(1.0, 6.0, -6.0)),
 'M2': P(twist=0, lean=26, sr=.5, drop=3.2, fL=(-3.0, 6.5, 0), fR=(3.0, 1.0, 0),
         rh=(-6.0, 8.0, -3.5), blade=(-.6, .8, -.05), lh=(.5, 5.5, -6.5)),
 'S2': P(twist=-50, lean=28, sr=.6, drop=3.0, fL=(-2.8, 2.0, 0), fR=(3.4, 7.0, 0),
         rh=ext((.78, .55, -.2)), blade=(.8, .55, -.15), lh=(.5, 6.0, -6.0), skirt=(.8, .5)),
 'W3': P(twist=-15, lean=-2, sr=-2.2, drop=-1.2, fL=(-2.6, 3.0, 0), fR=(2.6, -2.0, 0),
         rh=(.5, -1.5, 13.0), blade=(0, -.55, .83), lh=(1.0, 6.5, -4.0)),
 'S3': P(twist=20, lean=40, sr=1.8, drop=5.0, fL=(-3.6, 8.5, 0), fR=(3.6, -4.5, 0),
         rh=ext((-.05, .82, -.57)), blade=(-.05, .7, -.71), lh=(.5, 5.0, -8.0), skirt=(0, 1.5)),
 'W4': P(twist=45, lean=8, sr=-.6, drop=2.6, fL=(-3.0, 6.0, 0), fR=(3.0, -2.0, 0),
         rh=(-7.0, 2.5, -10.0), blade=(-.5, -.4, -.75), lh=(1.0, 6.0, -6.0)),
 'S4': P(twist=-35, lean=18, sr=1.6, drop=1.2, fL=(-3.0, 2.0, 0), fR=(3.4, 7.5, 0),
         rh=ext((.6, .55, .55)), blade=(.55, .45, .7), lh=(.5, 6.0, -6.0), skirt=(.6, .6)),
 'W5': P(twist=-45, lean=6, sr=-.4, drop=2.0, fL=(-3.0, 3.0, 0), fR=(3.0, -1.0, 0),
         rh=(4.0, -7.0, -5.0), blade=(-.55, .83, .05), lh=(.5, 6.5, -6.0)),
 'S5': P(twist=35, lean=32, sr=.8, drop=5.2, fL=(-3.4, 9.5, 0), fR=(3.0, -5.0, 0),
         rh=ext((.05, 1.0, -.12)), blade=(.5, .82, .3), lh=(-1.0, 4.0, -8.0), skirt=(0, 1.6)),
 'W7': P(twist=-30, lean=14, sr=-.5, drop=3.5, fL=(-2.8, 2.0, 0), fR=(2.8, -4.0, 0),          # 방패 차징: 웅크려 방패를 가슴에
         rh=(3.0, -3.0, -8.5), blade=(.1, .3, -.95), lh=(5.5, 4.5, -3.0)),
 'R7a': P(twist=-35, lean=24, sr=-.5, drop=2.6, fL=(-2.8, 5.0, 2.0), fR=(2.8, -5.0, 0),
         rh=(3.0, -4.0, -8.5), blade=(.1, .2, -.97), lh=(5.5, 6.0, -2.5), skirt=(0, 1.0)),
 'R7b': P(twist=-35, lean=26, sr=-.5, drop=2.2, fL=(-2.8, -4.0, 0), fR=(2.8, 6.0, 2.0),
         rh=(3.0, -4.0, -8.5), blade=(.1, .2, -.97), lh=(5.5, 6.5, -2.5), skirt=(0, 1.2)),
 'S7': P(twist=-45, lean=30, sr=-.8, drop=3.2, fL=(-3.0, 8.0, 0), fR=(2.8, -5.0, 0),
         rh=(3.0, -4.5, -8.0), blade=(.1, .1, -.99), lh=(5.0, 8.5, -2.0), skirt=(0, 1.6)),
 'W6': P(twist=50, lean=6, side=-4, sr=1.8, drop=.6, fL=(-3.0, 3.0, 0), fR=(2.6, -2.5, 0),
         rh=(-9.0, 1.0, 8.0), blade=(-.5, -.4, .75), lh=(2.0, 5.0, -3.0)),
 'S6': P(twist=-55, lean=30, side=6, sr=-.6, drop=6.0, fL=(-3.2, -4.0, 0), fR=(3.8, 9.0, 0),
         rh=ext((.55, .6, -.58)), blade=(.6, .55, -.58), lh=(-1.5, 3.0, -4.0), skirt=(.8, 1.4)),
}
CONTACT = {'1': (-1.5, 9.0, -1.5), '2': (-4.0, 9.5, -4.0), '3': (-1.2, 11.6, -5.8),      # 타격 순간 손 위치(오른어깨 기준)
           '4': (-1.5, 8.5, -8.5), '5': (-3.5, 11.5, -5.5), '6': (-4.5, 9.0, 0.0)}
for i in '123456':                      # S=목표점 통과(타격), C=끝까지 뻗은 마무리, S~=유지
    Wk, Fk = K['W' + i], K['S' + i]
    X = mix(Wk, Fk, .6); X.update(rh=Wk['rh'], blade=Wk['blade'], aim=0.0); K['X' + i] = X
    S = dict(Fk); S.update(twist=Fk['twist'] * .8, lean=Fk['lean'] * .9, drop=Fk['drop'] * .9, rh=CONTACT[i], aim=1.0); K['S' + i] = S
    if i == '3': S.update(aim=0.0)
    C = dict(Fk); C.update(twist=Fk['twist'] * 1.1, lean=Fk['lean'] * 1.05, drop=Fk['drop'] * 1.05); K['C' + i] = C
    Sd = dict(Fk); Sd.update(twist=Fk['twist'] * .85, lean=Fk['lean'] * .85, drop=Fk['drop'] * .85); K['S' + i + '~'] = Sd
def _hand(Pk):
    """키포즈의 오른손 위치·몸통 회전(fig8.build와 같은 계산)"""
    rx, ry = Pk['root']; pel = np.array([rx, ry, PEL_H - Pk['drop']])
    Rt = rotz(math.radians(Pk['twist'])) @ rotx(-math.radians(Pk['lean'])) @ roty(math.radians(Pk['side']))
    sho = pel + Rt @ np.array([SHO_W, 0, SHO_H + Pk['sr']])
    el, hr = ik(sho, sho + np.asarray(Pk['rh'], float), UP_A, FO_A, Rt @ np.array([1, -.6, -.5]))
    return hr, Rt
def _bake(Pk):
    """aim(목표점 조준)을 몸통 기준 칼 방향으로 미리 굳힘 → 보간이 한 좌표계에서만 일어나 칼이 뒤집히지 않음"""
    a = Pk.get('aim', 0.0)
    if a <= 0: return Pk
    hr, Rt = _hand(Pk); bd = Rt @ nrm(Pk['blade']); bd = nrm((1 - a) * bd + a * nrm(TARGET - hr))
    Pk = dict(Pk); Pk['blade'] = tuple(Rt.T @ bd); Pk['aim'] = 0.0; return Pk
def _ang(u, v): return math.degrees(math.acos(float(np.clip(nrm(u) @ nrm(v), -1, 1))))
def _limit(src, dst, mx):
    """src에서 dst 쪽으로 최대 mx도까지만 돌린 방향"""
    g = _ang(src, dst); return tuple(dst) if g <= mx else slerp(nrm(src), nrm(dst), mx / g)
def _along_arm(Pk, down):
    """칼을 팔뚝 연장선에서 아래로 조금만 꺾은 방향(몸통 기준)으로 — 손목이 비틀려 보이지 않게"""
    rx, ry = Pk['root']; pel = np.array([rx, ry, PEL_H - Pk['drop']])
    Rt = rotz(math.radians(Pk['twist'])) @ rotx(-math.radians(Pk['lean'])) @ roty(math.radians(Pk['side']))
    sho = pel + Rt @ np.array([SHO_W, 0, SHO_H + Pk['sr']])
    el, hr = ik(sho, sho + np.asarray(Pk['rh'], float), UP_A, FO_A, Rt @ np.array([1, -.6, -.5]))
    Pk['blade'] = tuple(Rt.T @ nrm(nrm(hr - el) + np.array([0, 0, -down])))
for k, dn in (('S3', .2), ('C3', .4), ('S3~', .35)): _along_arm(K[k], dn)   # 내려찍기: 팔 연장선 그대로 내리침
K['G'] = _bake(K['G'])
for i in '123456':
    K['S' + i] = _bake(K['S' + i]); Sb = K['S' + i]['blade']
    for k in ('C' + i, 'S' + i + '~'):              # 마무리는 타격 방향에서 60도 이내로만 더 진행
        K[k]['blade'] = _limit(Sb, K[k]['blade'], 60)
    src = 'M2' if i == '2' else 'X' + i
    g = _ang(K[src]['blade'], Sb)
    if g > 75:                                      # 크게 도는 베기: 중간 키로 정해진 경로(머리 위·앞쪽)를 지나게
        b0, b1 = np.asarray(K[src]['blade']), np.asarray(Sb)
        h = nrm(b0 + b1) if np.linalg.norm(b0 + b1) >= .35 else nrm((0, .5, .87))
        n = 3 if g > 140 else 2                     # 구간당 회전 60~80도 이내
        for j in range(1, n):
            t = j / n; XM = mix(K[src], K['S' + i], t)
            XM['blade'] = slerp(b0, h, t * 2) if t <= .5 else slerp(h, b1, t * 2 - 1)
            K['XM%s_%d' % (i, j)] = XM
# 찌르기: 칼끝은 처음부터 끝까지 목표점을 겨누고, 손만 허리에서 일직선으로 뻗음(칼이 휘청이지 않게)
for k in [k for k in K if k.startswith('XM5_')]: del K[k]
K['W5'].update(rh=(3.0, 2.0, -8.0))
K['X5'] = mix(K['W5'], K['S5'], .35); K['X5'].update(rh=(2.5, 3.5, -7.5))
K['C5'].update(rh=(-3.0, 12.5, -4.5)); K['S5~'].update(rh=(-2.0, 11.0, -5.5))
for k in ('S5', 'C5', 'S5~'): K[k]['aim'] = 0.0
_d5 = nrm(_hand(K['C5'])[0] - _hand(K['X5'])[0]); _d5 = nrm(_d5 * np.array([.35, 1, .4]))   # 찌르는 선(거의 수평)
for k in ('W5', 'X5', 'S5', 'C5', 'S5~'): K[k]['blade'] = tuple(_hand(K[k])[1].T @ _d5)
# 베기(사선·역사선·횡·올려): 휘두르는 동안 칼은 팔뚝 연장선을 따라감 → 손목이 비틀려 보이지 않음
_DN = {'2': (0.0, .1), '4': (-.25, -.35)}   # (타격, 마무리) 아래로 꺾는 정도
for i, (dS, dC) in _DN.items():
    xs = sorted(k for k in K if k.startswith('XM%s_' % i)); n = len(xs) + 1
    for j, k in enumerate(xs, 1): _along_arm(K[k], dS * j / n)
    _along_arm(K['S' + i], dS); _along_arm(K['C' + i], dC); _along_arm(K['S' + i + '~'], (dS + dC) / 2)
# 사선·역사선: 손이 대각선으로 몸 앞을 가로지르고, 칼끝은 손 뒤에 끌려오듯 따라감(채찍처럼 늦게 따라와 타격 때 일직선)
def _sho(Pk):
    rx, ry = Pk['root']; pel = np.array([rx, ry, PEL_H - Pk['drop']])
    Rt = rotz(math.radians(Pk['twist'])) @ rotx(-math.radians(Pk['lean'])) @ roty(math.radians(Pk['side']))
    return pel + Rt @ np.array([SHO_W, 0, SHO_H + Pk['sr']]), Rt
_DIAG = {'1': [(7.0, 1.0, 44.0), (5.0, 8.5, 41.5), (2.0, 13.0, 37.5), (-1.0, 15.5, 33.0), (-9.0, 12.5, 24.0)],
         '6': [(-5.0, 4.0, 44.0), (-2.0, 9.5, 40.0), (1.0, 12.5, 36.0), (3.5, 14.0, 32.0), (12.0, 8.0, 22.0)]}
_LAG = [1.1, .8, .55, .25, -.25]                     # 손 진행 반대쪽으로 칼이 처지는 정도(음수=마무리에서 앞서 나감)
for i, path in _DIAG.items():
    for k in [k for k in K if k.startswith('XM%s_' % i)]: del K[k]
    ks = ['X' + i, 'XM%s_1' % i, 'XM%s_2' % i, 'S' + i, 'C' + i]
    for j, k in enumerate(ks[1:3], 1): K[k] = mix(K['X' + i], K['S' + i], j / 3)
    sh = [_sho(K[k]) for k in ks]
    for k, (so, Rt), h in zip(ks, sh, path): K[k]['rh'] = tuple(np.array(h) - so)
    P_ = [np.array(h) for h in path]
    for j, (k, (so, Rt)) in enumerate(zip(ks, sh)):
        v = nrm(P_[min(j + 1, 4)] - P_[max(j - 1, 0)]); out = nrm(P_[j] - so)
        K[k]['blade'] = tuple(Rt.T @ nrm(out - _LAG[j] * v)); K[k]['aim'] = 0.0
    K['W' + i]['rh'] = K['X' + i]['rh']; K['W' + i]['blade'] = tuple(_sho(K['W' + i])[1].T @ (sh[0][1] @ np.array(K['X' + i]['blade'])))
    K['S' + i + '~'].update(rh=K['C' + i]['rh'], blade=K['C' + i]['blade'])
WIND = {'1': 5, '2': 5, '3': 6, '4': 5, '5': 5, '6': 6}   # 준비동작 길이(프레임)
def chain(hits, sp=1.0):
    """타격 목록 → 준비자세(G)에서 시작해 G로 끝나는 독립 콤보 클립. sp: 무기 무게에 따른 시간 배율"""
    R_ = lambda x: max(1, int(round(x * sp)))
    segs, f, prev, hf = [], 0, 'G', []
    st = 2 if sp >= 1.3 else 1                       # 무거운 무기는 베는 구간도 2프레임
    for h in hits:
        f += R_(WIND[h]); segs.append((f, prev, 'W' + h, 'io', 0))
        f += R_(2); segs.append((f, 'W' + h, 'X' + h, 'io', 0))
        src = 'X' + h
        if h == '2': f += 1; segs.append((f, 'X2', 'M2', 'lin', 1)); src = 'M2'
        j = 1
        while 'XM%s_%d' % (h, j) in K:
            f += 1; segs.append((f, src, 'XM%s_%d' % (h, j), 'lin', 1)); src = 'XM%s_%d' % (h, j); j += 1
        f += st; segs.append((f, src, 'S' + h, 'lin', 1))
        hf.append(f)
        f += 2; segs.append((f, 'S' + h, 'C' + h, 'out', 1))
        f += R_(5); segs.append((f, 'C' + h, 'S' + h + '~', 'io', 0)); prev = 'S' + h + '~'
    f += R_(9); segs.append((f, prev, 'G', 'io', 0))
    return (f + 1, segs), hf
HIT_KO = {'1': '사선', '2': '횡베기', '3': '내려찍기', '4': '올려베기', '5': '찌르기', '6': '역사선'}
C7 = dict(K['S7']); C7.update(lean=34, drop=3.6, lh=(5.0, 9.0, -2.2)); K['C7'] = C7
S7s = dict(K['S7']); S7s.update(lean=22, drop=2.6, lh=(5.0, 7.5, -2.5)); K['S7~'] = S7s
CHARGE = (27, [(5, 'G', 'W7', 'io', 0), (7, 'W7', 'R7a', 'io', 0), (9, 'R7a', 'R7b', 'io', 0), (10, 'R7b', 'S7', 'lin', 0),
               (11, 'S7', 'C7', 'out', 0), (17, 'C7', 'S7~', 'io', 0), (26, 'S7~', 'G', 'io', 0)])
# 무기별: 시간 배율, 보조장비, 콤보(타격 문자열). 콤보는 독립, 전투 중 무작위 선택
WSET = {
 'arming':      (1.0,  'round',  {'combo_a': '12', 'combo_b': '46', 'combo_c': '613', 'combo_d': '25', 'combo_e': '5', 'combo_f': '3'}),
 'shortsword':  (.8,   'wood',   {'combo_a': '12', 'combo_b': '15', 'combo_c': '25', 'combo_d': '5', 'combo_e': '61'}),
 'longsword':   (1.15, 'heater', {'combo_a': '12', 'combo_b': '46', 'combo_c': '613', 'combo_d': '3'}),
 'zweihander':  (1.4,  None,     {'combo_a': '12', 'combo_b': '46', 'combo_c': '62', 'combo_d': '3'}),
 'rapier':      (.85,  'dagger', {'combo_a': '5', 'combo_b': '55', 'combo_c': '15', 'combo_d': '25'}),
 'handaxe':     (1.1,  'round',  {'combo_a': '3', 'combo_b': '12', 'combo_c': '63', 'combo_d': '46'}),
 'morningstar': (1.25, 'heater', {'combo_a': '3', 'combo_b': '63', 'combo_c': '12'}),
}
COMBOS, COMBO_DESC, MOVES, HITS, MOVE_FORWARD = {}, {}, {}, {}, {}
# ---- 궁수: 활 키포즈 (aimw=조준 정렬, draw=당김, bind=오른손이 시위에, arrow=화살 걸림, carry=손에 화살)
_AF = dict(fL=(-1.2, 4.5, 0), fR=(3.4, -2.8, 0))
K.update({
 'AG':  P(twist=-40, lean=5, sr=0, drop=1.5, lh=(1.5, 7.0, -7.0), rh=(-1.0, 4.0, -8.0), bowup=(-.2, .5, .85), bind=1, arrow=1, **_AF),
 'AD1': P(twist=-62, lean=3, sr=.3, drop=1.2, lh=(1.5, 9.0, -2.0), rh=(-1.0, 4.0, -4.0), bowup=(-.1, .3, .95), aimw=.7, draw=.35, bind=1, arrow=1, **_AF),
 'AD2': P(twist=-75, lean=4, sr=.5, drop=1.3, lh=(1.5, 9.0, -2.0), rh=(-1.0, 4.0, -4.0), aimw=1, draw=1, bind=1, arrow=1, **_AF),
 'AH':  P(twist=-76, lean=5, sr=.4, drop=1.5, lh=(1.5, 9.0, -2.0), rh=(-1.0, 4.0, -4.0), aimw=1, draw=1, bind=1, arrow=1, **_AF),
 'AR':  P(twist=-78, lean=5, sr=.2, drop=1.5, lh=(1.5, 9.0, -2.0), rh=(.8, 3.0, 3.2), aimw=1, draw=0, bind=0, arrow=0, **_AF),
 'AF':  P(twist=-74, lean=6, sr=0, drop=1.7, lh=(1.5, 9.0, -2.0), rh=(1.2, 2.5, 2.4), aimw=.9, draw=0, bind=0, arrow=0, **_AF),
 'AQ':  P(twist=-50, lean=4, sr=.6, drop=1.4, lh=(1.5, 7.0, -6.0), rh=(0.2, -2.5, 4.5), bowup=(-.2, .5, .85), aimw=.1, carry=1, **_AF),
})
def _scale(segs, sp):
    out, prev = [], 0
    for t, a, b, m, tr in segs:
        tt = max(prev + 1, int(round(t * sp))); out.append((tt, a, b, m, tr)); prev = tt
    return (prev + 1, out)
SHOTS = {   # 기준 시간(프레임 끝), 시작·끝은 준비자세 AG
 'shot_quick':  ([(3, 'AG', 'AD1', 'io', 0), (6, 'AD1', 'AD2', 'io', 0), (8, 'AD2', 'AH', 'io', 0), (9, 'AH', 'AR', 'lin', 0),
                  (13, 'AR', 'AF', 'out', 0), (18, 'AF', 'AQ', 'io', 0), (22, 'AQ', 'AG', 'io', 0), (25, 'AG', 'AG', 'io', 0)], [9], '속사'),
 'shot_aimed':  ([(4, 'AG', 'AD1', 'io', 0), (9, 'AD1', 'AD2', 'io', 0), (20, 'AD2', 'AH', 'io', 0), (21, 'AH', 'AR', 'lin', 0),
                  (26, 'AR', 'AF', 'out', 0), (31, 'AF', 'AQ', 'io', 0), (35, 'AQ', 'AG', 'io', 0), (38, 'AG', 'AG', 'io', 0)], [21], '조준 사격'),
 'shot_double': ([(3, 'AG', 'AD1', 'io', 0), (6, 'AD1', 'AD2', 'io', 0), (7, 'AD2', 'AH', 'io', 0), (8, 'AH', 'AR', 'lin', 0),
                  (12, 'AR', 'AQ', 'io', 0), (15, 'AQ', 'AD1', 'io', 0), (18, 'AD1', 'AD2', 'io', 0), (19, 'AD2', 'AR', 'lin', 0),
                  (23, 'AR', 'AF', 'out', 0), (28, 'AF', 'AQ', 'io', 0), (32, 'AQ', 'AG', 'io', 0), (35, 'AG', 'AG', 'io', 0)], [8, 19], '연사(2발)'),
}

# ---- 석궁: xb=개머리(오른어깨 기준), xd=앞 방향, xaim=목표 정렬, span=시위 걸림, bolt=볼트, xl=왼손 받침, xpull=양손 시위 당김
_XF = dict(fL=(-2.0, 4.0, 0), fR=(2.8, -2.6, 0))
K.update({
 'XG':  P(twist=-18, lean=6, drop=1.4, xb=(-1.2, 2.2, -2.2), xd=(0, .9, -.42), xaim=0, xl=1, span=1, bolt=1, **_XF),
 'XA':  P(twist=-22, lean=8, drop=1.6, xb=(-1.6, 1.6, -.6), xd=(0, 1, 0), xaim=1, xl=1, span=1, bolt=1, **_XF),
 'XF':  P(twist=-16, lean=3, drop=1.4, xb=(-1.4, .4, .2), xd=(0, 1, .12), xaim=.7, xl=1, span=0, bolt=0, **_XF),
 'XR1': P(twist=-5, lean=24, drop=2.6, xb=(-2.2, 9.0, -4.0), xd=(0, .72, -.69), xaim=0, xl=1, span=0, bolt=0,
          fL=(-2.6, -2.5, 0), fR=(1.0, 7.2, 1.4), skirt=(0, 1.2)),
 'XR2': P(twist=-5, lean=16, drop=1.6, xb=(-2.2, 9.0, -4.0), xd=(0, .72, -.69), xaim=0, xl=1, span=1, bolt=0, xpull=1,
          fL=(-2.6, -2.5, 0), fR=(1.0, 7.2, 1.4), skirt=(0, 1.0)),
 'XL':  P(twist=-12, lean=12, drop=2.0, xb=(-1.0, 3.2, -5.0), xd=(0, .7, -.72), xaim=0, xl=0, lh=(2.6, 3.5, -6.0), span=1, bolt=1, **_XF),
})
_XR0 = dict(K['XR1']); _XR0.update(span=0, bolt=0, xpull=1, drop=3.4, lean=32); K['XR1p'] = _XR0     # 시위 잡으러 숙임
XSHOTS = {
 'shot_xbow':  ([(5, 'XG', 'XA', 'io', 0), (11, 'XA', 'XA', 'io', 0), (12, 'XA', 'XF', 'lin', 0), (16, 'XF', 'XA', 'out', 0),
                 (23, 'XA', 'XR1', 'io', 0), (27, 'XR1', 'XR1p', 'io', 0), (34, 'XR1p', 'XR2', 'io', 0), (40, 'XR2', 'XL', 'io', 0),
                 (46, 'XL', 'XG', 'io', 0)], '조준 사격 후 재장전'),
 'shot_xsnap': ([(3, 'XG', 'XA', 'io', 0), (4, 'XA', 'XF', 'lin', 0), (8, 'XF', 'XA', 'out', 0),
                 (15, 'XA', 'XR1', 'io', 0), (19, 'XR1', 'XR1p', 'io', 0), (26, 'XR1p', 'XR2', 'io', 0), (32, 'XR2', 'XL', 'io', 0),
                 (38, 'XL', 'XG', 'io', 0)], '빠른 사격 후 재장전'),
}
BSET = {'bow': 1.0, 'longbow': 1.25, 'runebow': 1.1}
def _transitions():
    K['I'] = idle(0)
    if GK[0] == 'XG':
        MOVES['ready_in'] = (12, [(11, 'I', 'XG', 'io', 0)]); MOVES['ready_out'] = (12, [(11, 'XG', 'I', 'io', 0)])
    elif GK[0] == 'AG':
        MOVES['ready_in'] = (14, [(6, 'I', 'AQ', 'io', 0), (13, 'AQ', 'AG', 'io', 0)])     # 화살 꺼내 걸고 준비
        MOVES['ready_out'] = (12, [(11, 'AG', 'I', 'io', 0)])
    else:
        X = mix(K['I'], K['G'], .55); X.update(drop=K['G']['drop'] * 1.2, lean=K['G']['lean'] * .5); K['GI'] = X   # 무릎 먼저 굽히며 들어감
        if SHEATHED[0] > .5:                       # 칼 뽑기: 오른손을 왼허리 손잡이로 → 뽑아 올림 → 준비자세
            D1 = mix(K['I'], K['G'], .3); D1.update(twist=-28, lean=7, drop=1.0, sr=-.4, sheath=1.0, aim=0.0)
            grip, d, _ = sheath_geo(D1); so, Rt = _sho(D1); D1['rh'] = tuple(grip - so); D1['blade'] = tuple(Rt.T @ d)
            D2 = dict(D1); D2['sheath'] = 0.0
            D3 = mix(D1, K['G'], .6); D3.update(sheath=0.0, aim=0.0, twist=8, rh=(2.5, 5.0, 1.5), blade=(-.35, .55, .76))
            K['D1'], K['D2'], K['D3'] = D1, D2, D3
            MOVES['ready_in'] = (17, [(6, 'I', 'D1', 'io', 0), (7, 'D1', 'D2', 'lin', 0), (11, 'D2', 'D3', 'out', 0), (16, 'D3', 'G', 'io', 0)])
            MOVES['ready_out'] = (19, [(6, 'G', 'D3', 'io', 0), (11, 'D3', 'D2', 'io', 0), (12, 'D2', 'D1', 'lin', 0), (18, 'D1', 'I', 'io', 0)])
        else:
            MOVES['ready_in'] = (12, [(5, 'I', 'GI', 'io', 0), (11, 'GI', 'G', 'io', 0)])
            MOVES['ready_out'] = (12, [(11, 'G', 'I', 'io', 0)])
def set_weapon(name):
    if name == 'crossbow':
        for d in (COMBOS, COMBO_DESC, MOVES, HITS, MOVE_FORWARD): d.clear()
        GK[0] = 'XG'; SHEATHED[0] = 0.0
        for k, (segs, ko) in XSHOTS.items():
            MOVES[k] = (segs[-1][0] + 1, segs); HITS[k] = [t for t, a, b, m, tr in segs if b == 'XF']; COMBOS[k] = k; COMBO_DESC[k] = ko
        sp = dict(fig4.CLASSES['archer']); sp.update(bowspec=BOWS[name], xbow=True, quiver=True); _transitions()
        return sp
    if name in BSET:
        for d in (COMBOS, COMBO_DESC, MOVES, HITS, MOVE_FORWARD): d.clear()
        spd = BSET[name]; GK[0] = 'AG'; SHEATHED[0] = 0.0
        for k, (segs, rel, ko) in SHOTS.items():
            MOVES[k] = _scale(segs, spd); HITS[k] = [max(1, int(round(r_ * spd))) for r_ in rel]
            # 해제 프레임이 스케일 후 실제 AR 도착 프레임과 같도록
            HITS[k] = [t for t, a, b, m, tr in MOVES[k][1] if b == 'AR']
            COMBOS[k] = k; COMBO_DESC[k] = ko
        sp = dict(fig4.CLASSES['archer']); sp.update(bowspec=BOWS[name]); _transitions()
        return sp
    GK[0] = 'G'
    spd, off, cmb = WSET[name]
    SHEATHED[0] = 1.0 if WEAPONS[name]['kind'] in ('sword', 'rapier') and not WEAPONS[name].get('twohand') else 0.0
    for d in (COMBOS, COMBO_DESC, MOVES, HITS, MOVE_FORWARD): d.clear()
    for k, v in cmb.items():
        COMBOS[k] = v; COMBO_DESC[k] = '→'.join(HIT_KO[c] for c in v); MOVES[k], HITS[k] = chain(v, spd)
    if off in SHIELDS:
        COMBOS['combo_g'] = '7'; COMBO_DESC['combo_g'] = '방패 차징(돌진, 5~10f 동안 앞으로 이동)'
        MOVES['combo_g'] = CHARGE; HITS['combo_g'] = [10]; MOVE_FORWARD['combo_g'] = [5, 10]
    sp = dict(fig4.CLASSES['warrior']); sp.update(weapon=WEAPONS[name], offhand=off, shield=off in SHIELDS); _transitions()
    return sp
set_weapon('arming')
def ez(t, m):
    return ease(t) if m == 'io' else (1 - (1 - t) ** 2 if m == 'out' else (t * t if m == 'in' else t))
def pose_at(move, f):
    n, segs = MOVES[move]; f0 = 0
    for f1, a, b, m, tr in segs:
        if f <= f1:
            t = 0 if f1 == f0 else (f - f0) / (f1 - f0)
            return mix(K[a], K[b], ez(t, m)), tr, f0
        f0 = f1
    return K[segs[-1][2]], 0, None
def blend_blade(p):                       # 칼 방향 보간 후 정규화
    b = np.asarray(p['blade'], float); p = dict(p); p['blade'] = tuple(b / (np.linalg.norm(b) or 1)); return p

def attack_frame(sp, move, f, d):
    p, tr, f0 = pose_at(move, f); p = blend_blade(p)
    trail = None
    if tr:
        segs, fs, a0 = MOVES[move][1], 0, 0           # 베기 구간(tr 연속) 시작 프레임
        for f1, a, b, m, t_ in segs:
            if f <= f1: break
            if t_ and fs is None: pass
            a0 = f1
        st, prev = None, 0
        for f1, a, b, m, t_ in segs:
            if t_ and st is None: st = prev
            if not t_: st = None
            if f <= f1: break
            prev = f1
        fs = st if st is not None else f0
        if f > fs:
            tb = max(fs, f - 2.5)
            trail = [tip_of(sp, blend_blade(pose_at(move, t)[0]), d) for t in np.linspace(f, tb, 18)]
    return render(sp, p, d, trail)[0]

def all_anims(sp):
    F = {}
    for d in DIRS:
        F['idle_' + d] = [render(sp, idle(i), d)[0] for i in range(NF)]
        F['walk_' + d] = [render(sp, walk(i), d)[0] for i in range(NF)]
        F['combat_idle_' + d] = [render(sp, combat_idle(i), d)[0] for i in range(NF)]
        F['combat_walk_' + d] = [render(sp, combat_walk(i), d)[0] for i in range(NF)]
        F['run_' + d] = [render(sp, run(i), d)[0] for i in range(NR)]
        F['combat_run_' + d] = [render(sp, combat_run(i), d)[0] for i in range(NR)]
        for mv, (n, _) in MOVES.items():
            F[f'{mv}_{d}'] = [attack_frame(sp, mv, i, d) for i in range(n)]
    return F
