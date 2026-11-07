"""피격·사망·상황 동작(궁수·석궁): idle(0) 기준 키포즈 + 구간 보간. 모든 클립은 서 있는 자세 I에서 시작(쓰러진 뒤 유지 클립은 예외)."""
import math, copy
from anim8 import *
import anim8

RMOVES, RINFO = {}, {}     # name -> (n, segs) / {'ko', 'loop', 'hold', 'moveBack'}

def _mk(**kw):
    p = dict(K['I']); p.update(kw); return p

def build_react():
    """set_weapon()·_transitions() 뒤에 호출(K['I']가 있어야 함). 활(AG)·석궁(XG) 공용."""
    xb = GK[0] == 'XG'
    I = K['I']
    clutch = dict(lh=(-3.5, 4.5, -7.5), xl=0) if xb else dict(rh=(0.5, 5.0, -6.5))          # 손으로 맞은 곳 감싸기(석궁은 왼손)
    # ---- 피격(가벼움): 상체가 뒤로 튕기고 복귀 12f
    K['HL'] = _mk(lean=-7, drop=.8, sr=-.3, twist=9, hdrop=-9, **clutch)
    K['HL2'] = _mk(lean=-2, drop=.4, twist=3, hdrop=-3, **clutch)
    RMOVES['hit_light'] = (12, [(3, 'I', 'HL', 'out', 0), (7, 'HL', 'HL2', 'io', 0), (11, 'HL2', 'I', 'io', 0)])
    RINFO['hit_light'] = dict(ko='피격(약)')
    # ---- 피격(강함): 뒷발 물러나며 크게 젖힘, 웅크려 버틴 뒤 복귀 18f
    K['HH1'] = _mk(lean=-16, drop=1.6, sr=-.5, twist=16, hdrop=-16, fL=(-2.9, -3.8, .0), fR=(2.9, .8, 0), **clutch)
    K['HH2'] = _mk(lean=6, drop=3.0, twist=8, hdrop=4, fL=(-2.9, -3.0, 0), fR=(2.9, .6, 0), **clutch)
    K['HH3'] = _mk(lean=3, drop=1.2, twist=2, fL=(-2.9, -1.0, 0), fR=(2.9, 0, 0))
    RMOVES['hit_heavy'] = (18, [(4, 'I', 'HH1', 'out', 0), (9, 'HH1', 'HH2', 'io', 0), (13, 'HH2', 'HH3', 'io', 0), (17, 'HH3', 'I', 'io', 0)])
    RINFO['hit_heavy'] = dict(ko='피격(강)')
    # ---- 넉백: 뒤로 떠서 날아가 웅크려 착지 20f (게임이 0~7f 동안 캐릭터를 뒤로 이동)
    arms_up = dict(lh=(-3.5, 3.5, -2.5), xl=0) if xb else dict(rh=(2.5, 4.0, -2.0), lh=(-3.5, 3.5, -3.0), bowup=(-.4, .3, .85))
    K['KB1'] = _mk(gpitch=28, goff=(0, 0, 3.2), lean=-6, drop=.5, fL=(-2.4, 4.5, 3.0), fR=(2.4, 3.5, 2.4), hdrop=-10, **arms_up)
    K['KB2'] = _mk(gpitch=6, goff=(0, 0, .3), lean=12, drop=4.8, fL=(-3.2, -2.5, 0), fR=(3.0, 2.5, 0), hdrop=8, **clutch)
    K['KB3'] = _mk(lean=7, drop=2.8, fL=(-3.0, -1.5, 0), fR=(2.9, 1.0, 0), hdrop=3)
    RMOVES['knockback'] = (20, [(3, 'I', 'KB1', 'out', 0), (7, 'KB1', 'KB2', 'lin', 0), (12, 'KB2', 'KB3', 'io', 0), (19, 'KB3', 'I', 'io', 0)])
    RINFO['knockback'] = dict(ko='넉백', moveBack=[0, 7])
    # ---- 기절(반복 24f): 휘청이며 머리 떨굼
    def stun(i):
        ph = 2 * math.pi * i / 24
        p = _mk(lean=3 + 3 * math.sin(ph), side=4.5 * math.sin(ph * .5 + .4), twist=5 * math.sin(ph + 1), drop=1.6 + .3 * math.cos(ph),
                hdrop=13 + 4 * math.sin(ph + .8), hturn=12 * math.cos(ph * .5), sr=.2 * math.sin(ph))
        if xb: p.update(xb=(1.2, .6, -10.8), xl=0, lh=(-1.0, 3.5, -12.0))
        else: p.update(rh=(1.4, 1.2, -13.6), lh=(-5.0, 2.0, -13.3), bowup=(-.35, .15, .92))
        return p
    RINFO['stun'] = dict(ko='기절(반복)', loop=True, fn=stun, n=24)
    # ---- 사망 1: 뒤로 쓰러짐 30f(마지막 유지)
    K['DB1'] = _mk(lean=-11, drop=1.0, hdrop=-11, sr=-.3, **clutch)
    K['DB2'] = _mk(gpitch=18, gpiv=(0, 0, 18.5), lean=-6, drop=5.0, hdrop=-8, fL=(-2.6, -1.0, 0), fR=(2.6, .5, 0), **clutch)
    K['DB3'] = _mk(gpitch=78, gpiv=(0, 0, 18.5), goff=(0, 0, -12.5), lean=0, drop=6.5, fL=(-2.6, 2.5, 1.8), fR=(2.8, 3.5, 1.2), hdrop=-6,
                   **(dict(lh=(-4.5, -1.0, -8.5), xl=0, xb=(2.0, .5, -9.0)) if xb else dict(rh=(4.5, -1.0, -8.5), lh=(-4.5, -1.0, -9.0), bowup=(-.5, .2, .8))))
    K['DB4'] = _mk(gpitch=93, gpiv=(0, 0, 18.5), goff=(0, 0, -14.6), drop=6.5, fL=(-2.6, 3.5, 1.2), fR=(2.8, 4.5, .8), hdrop=-10,
                   **(dict(lh=(-5.5, -2.5, -10.5), xl=0, xb=(2.4, -.5, -9.5)) if xb else dict(rh=(5.5, -2.5, -10.5), lh=(-5.5, -2.0, -10.5), bowup=(-.6, .1, .78))))
    K['DB5'] = _mk(gpitch=90, gpiv=(0, 0, 18.5), goff=(0, 0, -15.0), drop=6.5, fL=(-2.8, 4.0, .9), fR=(3.0, 5.0, .4), hdrop=-12, hturn=22,
                   **(dict(lh=(-6.0, -3.0, -11.0), xl=0, xb=(2.6, -.8, -9.8)) if xb else dict(rh=(6.0, -3.0, -11.0), lh=(-6.0, -2.5, -11.0), bowup=(-.65, .1, .75))))
    RMOVES['death_back'] = (30, [(5, 'I', 'DB1', 'out', 0), (9, 'DB1', 'DB2', 'io', 0), (16, 'DB2', 'DB3', 'in', 0), (19, 'DB3', 'DB4', 'out', 0), (23, 'DB4', 'DB5', 'io', 0), (29, 'DB5', 'DB5', 'lin', 0)])
    RINFO['death_back'] = dict(ko='사망(뒤로)', hold=True)
    # ---- 사망 2: 무릎 꿇고 앞으로 엎어짐 30f
    K['DF1'] = _mk(lean=13, drop=2.0, hdrop=10, **clutch)
    K['DF2'] = _mk(lean=26, drop=9.5, hdrop=18, fL=(-2.4, -6.5, 0), fR=(2.4, -6.0, 0), gpitch=-8, gpiv=(0, 0, 15.5), **clutch)
    K['DF3'] = _mk(lean=14, drop=9.5, hdrop=10, fL=(-2.4, -6.5, 0), fR=(2.4, -6.0, 0), gpitch=-68, gpiv=(0, 0, 15.5), goff=(0, 0, -10.5),
                   **(dict(lh=(-4.0, 6.0, -3.0), xl=0, xb=(1.0, 5.5, -4.0)) if xb else dict(rh=(4.0, 6.0, -3.0), lh=(-4.0, 6.0, -3.5), bowup=(-.3, .7, .65))))
    K['DF4'] = _mk(lean=6, drop=9.5, hdrop=4, hturn=28, fL=(-2.6, -6.0, .3), fR=(2.6, -5.5, 0), gpitch=-91, gpiv=(0, 0, 15.5), goff=(0, 0, -12.0),
                   **(dict(lh=(-5.0, 4.0, -7.5), xl=0, xb=(1.6, 4.0, -8.0)) if xb else dict(rh=(5.0, 4.0, -7.5), lh=(-5.5, 3.5, -8.0), bowup=(-.5, .4, .75))))
    K['DF5'] = _mk(lean=4, drop=9.5, hdrop=2, hturn=30, fL=(-2.6, -6.0, .3), fR=(2.6, -5.5, 0), gpitch=-89, gpiv=(0, 0, 15.5), goff=(0, 0, -12.4),
                   **(dict(lh=(-5.5, 3.5, -8.5), xl=0, xb=(1.8, 3.5, -8.5)) if xb else dict(rh=(5.5, 3.5, -8.5), lh=(-6.0, 3.0, -9.0), bowup=(-.55, .35, .75))))
    RMOVES['death_front'] = (30, [(4, 'I', 'DF1', 'out', 0), (10, 'DF1', 'DF2', 'io', 0), (16, 'DF2', 'DF3', 'in', 0), (20, 'DF3', 'DF4', 'out', 0), (23, 'DF4', 'DF5', 'io', 0), (29, 'DF5', 'DF5', 'lin', 0)])
    RINFO['death_front'] = dict(ko='사망(앞으로)', hold=True)
    # ---- 사망 3: 옆으로 구겨짐 28f (오른쪽으로)
    K['DS1'] = _mk(side=9, drop=1.5, hdrop=6, hturn=-10, **clutch)
    K['DS2'] = _mk(side=14, groll=22, gpiv=(0, 0, 19.0), drop=4.5, fL=(-2.4, .5, 0), fR=(3.6, -.5, 1.8), hdrop=10, **clutch)
    K['DS3'] = _mk(side=6, groll=78, gpiv=(0, 0, 19.0), goff=(0, 0, -13.0), drop=6.0, fL=(-2.2, 2.5, 1.0), fR=(2.6, 1.0, 0), hdrop=10, hturn=-15,
                   **(dict(lh=(-3.0, 3.0, -9.5), xl=0, xb=(1.0, 2.0, -9.5)) if xb else dict(rh=(2.5, 3.5, -9.0), lh=(-3.5, 2.5, -10.0), bowup=(-.3, .3, .9))))
    K['DS4'] = _mk(side=2, groll=92, gpiv=(0, 0, 19.0), goff=(0, 0, -15.2), drop=6.0, fL=(-2.0, 4.0, .8), fR=(2.6, 1.5, 0), hdrop=12, hturn=-22,
                   **(dict(lh=(-3.5, 4.0, -9.0), xl=0, xb=(1.2, 2.5, -9.8)) if xb else dict(rh=(2.0, 4.5, -9.0), lh=(-4.0, 3.5, -9.5), bowup=(-.35, .3, .88))))
    K['DS5'] = _mk(side=0, groll=89, gpiv=(0, 0, 19.0), goff=(0, 0, -15.6), drop=6.0, fL=(-2.0, 4.5, .8), fR=(2.6, 2.0, 0), hdrop=14, hturn=-25,
                   **(dict(lh=(-3.5, 4.5, -9.0), xl=0, xb=(1.2, 2.5, -9.8)) if xb else dict(rh=(1.8, 5.0, -9.0), lh=(-4.0, 4.0, -9.5), bowup=(-.35, .3, .88))))
    RMOVES['death_side'] = (28, [(4, 'I', 'DS1', 'out', 0), (9, 'DS1', 'DS2', 'io', 0), (15, 'DS2', 'DS3', 'in', 0), (19, 'DS3', 'DS4', 'out', 0), (22, 'DS4', 'DS5', 'io', 0), (27, 'DS5', 'DS5', 'lin', 0)])
    RINFO['death_side'] = dict(ko='사망(옆으로)', hold=True)
    # ---- 쓰러짐(기절·행동불능, 반복 24f): 옆으로 누워 웅크린 채 숨쉬기
    def downed(i):
        ph = 2 * math.pi * i / 24; b = .5 * (1 + math.sin(ph))
        p = dict(K['DS5']); p.update(fL=(-2.0, 5.5, 1.0), fR=(2.6, 3.0, 0), sr=.25 * b, drop=6.0 - .25 * b, hdrop=16 + 1.5 * b, hturn=-25)
        return p
    RINFO['downed'] = dict(ko='쓰러짐(반복)', loop=True, fn=downed, n=24)
    # ---- 일어나기(구조·회복 후) 36f: 옆으로 누움 → 엎드려 짚음 → 한무릎 → 기립
    K['GU0'] = downed(0)
    K['GU1'] = _mk(groll=35, gpitch=-28, gpiv=(0, 0, 16.5), goff=(0, 0, -8.5), drop=8.5, lean=18, fL=(-2.4, -3.0, 0), fR=(2.6, -4.5, 0), hdrop=8,
                   **(dict(lh=(-3.0, 6.0, -12.5), xl=0, xb=(.5, 4.0, -12.0)) if xb else dict(rh=(3.0, 6.0, -12.5), lh=(-3.5, 6.0, -12.5), bowup=(-.2, .9, .35))))
    K['GU2'] = _mk(drop=7.5, lean=20, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=6,
                   **(dict(lh=(-2.0, 5.5, -9.0), xl=0, xb=(.8, 2.0, -10.0)) if xb else dict(rh=(1.0, 5.0, -9.5), lh=(-4.5, 4.0, -11.0), bowup=(-.25, .4, .88))))
    K['GU3'] = _mk(drop=3.2, lean=12, fL=(-2.6, 1.5, 0), fR=(2.6, -2.5, 0), hdrop=2)
    RMOVES['get_up'] = (36, [(10, 'GU0', 'GU1', 'io', 0), (19, 'GU1', 'GU2', 'io', 0), (28, 'GU2', 'GU3', 'io', 0), (35, 'GU3', 'I', 'io', 0)])
    RINFO['get_up'] = dict(ko='일어나기')
    # ---- 치료(붕대) 36f: 한무릎 꿇고 왼팔뚝 감기
    hb = (dict(lh=(-2.0, 5.5, -8.5), xl=0, xb=(.8, 2.0, -10.0)) if xb else dict(rh=(-2.6, 5.5, -7.0), lh=(-1.5, 4.5, -9.5), bowup=(-.35, .2, .9)))
    K['HB1'] = _mk(drop=7.5, lean=16, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=14, **hb)
    hb2 = dict(hb); hb2.update(dict(lh=(-2.5, 6.5, -6.5)) if xb else dict(rh=(-3.2, 4.5, -5.0)))
    K['HB2'] = _mk(drop=7.5, lean=17, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=16, **hb2)
    RMOVES['heal'] = (36, [(6, 'I', 'HB1', 'io', 0), (11, 'HB1', 'HB2', 'io', 0), (16, 'HB2', 'HB1', 'io', 0), (21, 'HB1', 'HB2', 'io', 0), (25, 'HB2', 'HB1', 'io', 0), (30, 'HB1', 'GU3', 'io', 0), (35, 'GU3', 'I', 'io', 0)])
    RINFO['heal'] = dict(ko='치료(붕대)')
    # ---- 물약 30f: 병을 입으로, 고개 젖혀 마심
    po = (dict(lh=(2.0, 3.0, 3.2), xl=0, vial=1) if xb else dict(rh=(-2.2, 3.0, 3.2), vial=1))
    po2 = (dict(lh=(2.2, 2.5, 4.2), xl=0, vial=1) if xb else dict(rh=(-2.4, 2.5, 4.2), vial=1))
    K['PO1'] = _mk(lean=-3, drop=.6, hdrop=-14, **po)
    K['PO2'] = _mk(lean=-6, drop=.4, hdrop=-24, **po2)
    K['PO3'] = _mk(lean=2, drop=.9, hdrop=-2, **(dict(lh=(-1.5, 4.0, -9.0), xl=0, vial=1) if xb else dict(rh=(1.5, 4.0, -8.5), vial=1)))
    RMOVES['potion'] = (30, [(6, 'I', 'PO1', 'io', 0), (10, 'PO1', 'PO2', 'io', 0), (18, 'PO2', 'PO2', 'lin', 0), (24, 'PO2', 'PO3', 'io', 0), (29, 'PO3', 'I', 'io', 0)])
    RINFO['potion'] = dict(ko='물약')
    # ---- 승리 36f: 활(석궁)을 머리 위로 치켜듦
    v1 = (dict(lh=(-1.5, 2.0, 1.0), xl=0, xb=(0.5, 1.5, 12.5), xd=(.2, .3, .93)) if xb else dict(lh=(-1.0, 2.0, 13.5), bowup=(.15, 0, 1), rh=(3.0, 2.0, 7.5)))
    v2 = (dict(lh=(-1.5, 2.0, 1.0), xl=0, xb=(0.5, 1.0, 13.5), xd=(.2, .25, .94)) if xb else dict(lh=(-1.0, 1.5, 14.2), bowup=(.1, 0, 1), rh=(3.5, 1.5, 9.0)))
    K['V1'] = _mk(lean=-4, drop=.6, hdrop=-12, **v1)
    K['V2'] = _mk(lean=-7, drop=0, hdrop=-16, fL=(-3.2, .6, 0), fR=(3.2, -.6, 0), **v2)
    K['V3'] = _mk(lean=-5, drop=.8, hdrop=-13, **v1)
    RMOVES['victory'] = (36, [(6, 'I', 'V1', 'io', 0), (10, 'V1', 'V2', 'out', 0), (16, 'V2', 'V3', 'io', 0), (21, 'V3', 'V2', 'io', 0), (28, 'V2', 'PO3' if False else 'V1', 'io', 0), (35, 'V1', 'I', 'io', 0)])
    RINFO['victory'] = dict(ko='승리')
    # ---- 휴식(반복 24f): 땅에 앉아 활을 무릎 위에
    def rest(i):
        ph = 2 * math.pi * i / 24; b = .5 * (1 + math.sin(ph))
        p = _mk(drop=PEL_H - 3.2 - .2 * b, lean=9 + 1.2 * b, fL=(-3.2, 9.5, 0), fR=(3.4, 10.0, .4), hdrop=10 + 1.5 * b, sr=.25 * b)
        if xb: p.update(xl=1, xb=(-1.5, 8.5, -11.5), xd=(-.95, .25, 0), lh=(-1.0, 8.0, -11.5))
        else: p.update(lh=(-2.5, 8.5, -11.5), rh=(2.5, 8.5, -11.0), bowup=(.96, .05, .27))
        return p
    RINFO['rest'] = dict(ko='휴식(반복)', loop=True, fn=rest, n=24)

def react_frames(sp, name, d):
    inf = RINFO[name]
    if 'fn' in inf: return [render(sp, inf['fn'](i), d)[0] for i in range(inf['n'])]
    n, segs = RMOVES[name]
    saved = dict(anim8.MOVES); anim8.MOVES[name] = (n, segs)
    try: return [render(sp, blend_blade(pose_at(name, i)[0]), d)[0] for i in range(n)]
    finally: anim8.MOVES.clear(); anim8.MOVES.update(saved)

def react_len(name): return RINFO[name]['n'] if 'fn' in RINFO[name] else RMOVES[name][0]
REACT_ORDER = ['hit_light', 'hit_heavy', 'knockback', 'stun', 'death_back', 'death_front', 'death_side', 'downed', 'get_up', 'heal', 'potion', 'victory', 'rest']
