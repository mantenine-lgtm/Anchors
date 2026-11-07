"""피격·사망·상황 동작(궁수·석궁): idle(0) 기준 키포즈 + 구간 보간. 모든 클립은 서 있는 자세 I에서 시작(쓰러진 뒤 유지 클립은 예외)."""
import math, copy
from anim8 import *
import anim8

RMOVES, RINFO = {}, {}     # name -> (n, segs) / {'ko', 'loop', 'hold', 'moveBack'}

def _mk(**kw):
    p = dict(K['I']); p.update(kw); return p

def build_react():
    """set_weapon()·_transitions() 뒤에 호출(K['I']가 있어야 함). 활(AG)·석궁(XG) 공용."""
    xb = GK[0] == 'XG'; G_ = GK[0]
    I = K['I']
    clutch = dict(lh=(-3.5, 4.5, -7.5), xl=0) if xb else dict(rh=(0.5, 5.0, -6.5))          # 손으로 맞은 곳 감싸기(석궁은 왼손)
    G = K[GK[0]]                                                     # 전투 준비자세(AG/XG): 피격·넉백은 여기서 시작해 여기로 복귀
    def _mg(**kw):
        p = dict(G); p.update(kw); return p
    gl, gd, gt = G['lean'], G['drop'], G['twist']
    # ---- 피격 앞(앞에서 맞아 뒤로 젖힘) 12f: 무기는 그대로 쥠
    hf_arm = dict(xd=(0, .8, -.1)) if xb else dict(lh=(1.5, 6.0, -5.5))
    K['HF1'] = _mg(lean=gl - 13, drop=gd + .8, twist=gt + 10, sr=-.3, hdrop=-10, fR=(G['fR'][0], G['fR'][1] - 1.8, 0), **hf_arm)
    K['HF2'] = _mg(lean=gl - 4, drop=gd + .3, twist=gt + 3, hdrop=-3)
    RMOVES['hit_front'] = (12, [(3, G_, 'HF1', 'out', 0), (7, 'HF1', 'HF2', 'io', 0), (11, 'HF2', G_, 'io', 0)])
    RINFO['hit_front'] = dict(ko='피격(앞)')
    # ---- 피격 뒤(뒤에서 맞아 앞으로 고꾸라질 듯) 12f
    hk_arm = dict(xd=(0, .85, -.55)) if xb else dict(lh=(1.5, 8.0, -9.5), bowup=(-.2, .6, .78))
    K['HK1'] = _mg(lean=gl + 15, drop=gd + 1.6, twist=gt + 6, sr=.4, hdrop=14, fL=(G['fL'][0], G['fL'][1] + 2.0, 0), **hk_arm)
    K['HK2'] = _mg(lean=gl + 5, drop=gd + .6, twist=gt + 2, hdrop=4)
    RMOVES['hit_back'] = (12, [(3, G_, 'HK1', 'out', 0), (7, 'HK1', 'HK2', 'io', 0), (11, 'HK2', G_, 'io', 0)])
    RINFO['hit_back'] = dict(ko='피격(뒤)')
    # ---- 옆구리 피격(옆으로 접히며 고개 돌림) 12f: 석궁은 왼손으로 옆구리 감쌈
    if xb: hs1 = dict(side=-12, twist=gt - 8, hturn=22, lh=(-4.5, 1.5, -8.5), xl=0); hs2 = dict(side=-4, twist=gt - 3, hturn=8, lh=(-3.5, 2.5, -7.0), xl=0)
    else:  hs1 = dict(side=12, twist=gt + 12, hturn=-22); hs2 = dict(side=4, twist=gt + 4, hturn=-8)
    K['HS1'] = _mg(drop=gd + 1.2, lean=gl + 2, sr=.5, hdrop=5, fR=(G['fR'][0], G['fR'][1] + 1.2, 0), **hs1)
    K['HS2'] = _mg(drop=gd + .4, lean=gl + 1, hdrop=2, **hs2)
    RMOVES['hit_side'] = (12, [(3, G_, 'HS1', 'out', 0), (7, 'HS1', 'HS2', 'io', 0), (11, 'HS2', G_, 'io', 0)])
    RINFO['hit_side'] = dict(ko='옆구리 피격')
    # ---- 강한 피격: 뒷발 물러나며 크게 젖힘, 웅크려 버틴 뒤 준비자세 복귀 18f (활은 손을 시위에서 떼었다가 다시 걺)
    hh_arm = dict(xd=(0, .7, -.7)) if xb else dict(bind=0, lh=(0.5, 5.5, -9.0), bowup=(-.3, .3, .9))
    K['HH1'] = _mg(lean=gl - 20, drop=gd + 1.6, sr=-.5, twist=gt + 18, hdrop=-16, fL=(G['fL'][0], G['fL'][1] - 2.5, 0), fR=(G['fR'][0], G['fR'][1] - 3.8, 0), **clutch, **hh_arm)
    K['HH2'] = _mg(lean=gl + 6, drop=gd + 3.0, twist=gt + 8, hdrop=4, fL=(G['fL'][0], G['fL'][1] - 2.0, 0), fR=(G['fR'][0], G['fR'][1] - 3.0, 0), **clutch, **hh_arm)
    K['HH3'] = _mg(lean=gl + 3, drop=gd + 1.2, twist=gt + 2, fL=(G['fL'][0], G['fL'][1] - .8, 0), fR=(G['fR'][0], G['fR'][1] - 1.0, 0))
    RMOVES['hit_heavy'] = (18, [(4, G_, 'HH1', 'out', 0), (9, 'HH1', 'HH2', 'io', 0), (13, 'HH2', 'HH3', 'io', 0), (17, 'HH3', G_, 'io', 0)])
    RINFO['hit_heavy'] = dict(ko='강한 피격')
    # ---- 넉백: 뒤로 떠서 날아가 웅크려 착지, 준비자세 복귀 20f (게임이 0~7f 동안 캐릭터를 뒤로 이동)
    arms_up = dict(lh=(-3.5, 3.5, -2.5), xl=0) if xb else dict(bind=0, rh=(2.5, 4.0, -2.0), lh=(-3.5, 3.5, -3.0), bowup=(-.4, .3, .85))
    K['KB1'] = _mg(gpitch=28, goff=(0, 0, 3.2), lean=gl - 6, drop=gd + .5, twist=gt * .6, fL=(-2.4, 4.5, 3.0), fR=(2.4, 3.5, 2.4), hdrop=-10, **arms_up)
    K['KB2'] = _mg(gpitch=6, goff=(0, 0, .3), lean=gl + 12, drop=gd + 4.8, twist=gt * .5, fL=(-3.2, -2.5, 0), fR=(3.0, 2.5, 0), hdrop=8, **clutch, **hh_arm)
    K['KB3'] = _mg(lean=gl + 7, drop=gd + 2.8, twist=gt * .8, fL=(-3.0, -1.5, 0), fR=(2.9, 1.0, 0), hdrop=3)
    RMOVES['knockback'] = (20, [(3, G_, 'KB1', 'out', 0), (7, 'KB1', 'KB2', 'lin', 0), (12, 'KB2', 'KB3', 'io', 0), (19, 'KB3', G_, 'io', 0)])
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
    # ---- 사망 4: 주저앉음 30f — 무릎 풀려 털썩 앉고 상체가 무릎 위로 꺾여 늘어짐(휴식의 바른 앉음과 구분)
    SIT = PEL_H - 3.2
    dt_arm = (dict(lh=(-4.5, 5.0, -12.0), xl=0, xb=(1.5, 4.5, -12.0), xd=(.3, .9, -.3)) if xb else dict(rh=(3.5, 4.0, -12.5), lh=(-4.0, 5.0, -12.0), bowup=(.7, .4, .6)))
    K['DT1'] = _mk(lean=-6, drop=1.0, hdrop=-6, sr=-.3, **clutch)
    K['DT2'] = _mk(lean=10, drop=9.0, hdrop=12, fL=(-3.0, 2.5, 0), fR=(3.2, 2.0, 0), **clutch)
    K['DT3'] = _mk(lean=16, drop=SIT - .2, hdrop=18, fL=(-3.6, 8.5, 0), fR=(3.8, 8.0, .3), **clutch)
    K['DT4'] = _mk(lean=36, drop=SIT + .2, hdrop=32, side=6, hturn=10, fL=(-4.0, 9.0, 0), fR=(4.0, 8.5, .3), **dt_arm)
    K['DT5'] = _mk(lean=40, drop=SIT + .4, hdrop=36, side=9, hturn=14, fL=(-4.0, 9.2, 0), fR=(4.0, 8.7, .3), **dt_arm)
    RMOVES['death_sit'] = (30, [(5, 'I', 'DT1', 'out', 0), (11, 'DT1', 'DT2', 'io', 0), (17, 'DT2', 'DT3', 'in', 0), (21, 'DT3', 'DT4', 'out', 0), (25, 'DT4', 'DT5', 'io', 0), (29, 'DT5', 'DT5', 'lin', 0)])
    RINFO['death_sit'] = dict(ko='사망(주저앉음)', hold=True)
    # ---- 쓰러짐(기절·행동불능, 반복 24f): 네발로 엎드려 고개 떨구고 숨 몰아쉼 — 누운 사망 3종과 구분
    dn_arm = (dict(rh=(0.2, 0.6, -12.0), lh=(-0.2, 0.6, -12.0), xl=0, xb=(-1.2, -4.0, -12.2), xd=(.25, .95, 0)) if xb else dict(rh=(0.2, 0.6, -12.0), lh=(-0.2, 0.6, -12.0), bowup=(-.9, .1, .35)))
    def downed(i):
        ph = 2 * math.pi * i / 24; b = .5 * (1 + math.sin(ph))
        p = _mk(drop=PEL_H - 12.9 + .4 * b, lean=80 - 2.5 * b, hdrop=30 + 4 * b, sr=.3 * b, fL=(-2.4, -15.6, 0), fR=(2.6, -15.6, 0), **dn_arm)
        return p
    RINFO['downed'] = dict(ko='쓰러짐(반복)', loop=True, fn=downed, n=24)
    # ---- 구조되어 일어남 36f: 네발 → 무릎 꿇고 상체 세움 → 한무릎 → 기립
    K['GU0'] = downed(0)
    K['GU1'] = _mk(drop=PEL_H - 13.6, lean=12, hdrop=8, fL=(-2.4, -11.6, 0), fR=(2.6, -11.6, 0),
                   **(dict(lh=(-3.0, 5.0, -11.5), xl=0, xb=(.5, 3.5, -12.0), xd=(.2, .9, -.3)) if xb else dict(rh=(2.5, 3.0, -11.0), lh=(-3.0, 5.0, -12.0), bowup=(-.1, .1, .99))))
    K['GU2'] = _mk(drop=7.5, lean=20, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=6,
                   **(dict(lh=(-2.0, 5.5, -9.0), xl=0, xb=(.8, 2.0, -10.0)) if xb else dict(rh=(1.0, 5.0, -9.5), lh=(-4.5, 4.0, -11.0), bowup=(-.25, .4, .88))))
    K['GU3'] = _mk(drop=3.2, lean=12, fL=(-2.6, 1.5, 0), fR=(2.6, -2.5, 0), hdrop=2)
    RMOVES['revive'] = (36, [(10, 'GU0', 'GU1', 'io', 0), (19, 'GU1', 'GU2', 'io', 0), (28, 'GU2', 'GU3', 'io', 0), (35, 'GU3', 'I', 'io', 0)])
    RINFO['revive'] = dict(ko='구조되어 일어남')
    # ---- 치료(붕대) 36f: 한무릎 꿇고 왼팔뚝 감기
    hb = (dict(lh=(-2.0, 5.5, -8.5), xl=0, xb=(.8, 2.0, -10.0)) if xb else dict(rh=(-2.6, 5.5, -7.0), lh=(-1.5, 4.5, -9.5), bowup=(-.35, .2, .9)))
    K['HB1'] = _mk(drop=7.5, lean=16, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=14, **hb)
    hb2 = dict(hb); hb2.update(dict(lh=(-2.5, 6.5, -6.5)) if xb else dict(rh=(-3.2, 4.5, -5.0)))
    K['HB2'] = _mk(drop=7.5, lean=17, fL=(-2.4, 3.0, 0), fR=(2.4, -6.0, 0), hdrop=16, **hb2)
    RMOVES['bandage'] = (36, [(6, 'I', 'HB1', 'io', 0), (11, 'HB1', 'HB2', 'io', 0), (16, 'HB2', 'HB1', 'io', 0), (21, 'HB1', 'HB2', 'io', 0), (25, 'HB2', 'HB1', 'io', 0), (30, 'HB1', 'GU3', 'io', 0), (35, 'GU3', 'I', 'io', 0)])
    RINFO['bandage'] = dict(ko='붕대')
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
    # ---- 귀환 36f: 무기 내리고 고개 들어 하늘 보며 떠오름, 끝에 사라짐(발밑 빛 이펙트는 별도 시트 recall_fx)
    rc1 = (dict(lh=(-5.5, 2.0, -12.5), xl=0, xb=(2.0, 1.5, -12.5), xd=(.2, .4, -.9)) if xb else dict(rh=(3.5, 2.0, -12.0), lh=(-5.5, 2.0, -12.5), bowup=(-.2, .1, .97)))
    rc2 = (dict(lh=(-6.5, 2.0, -11.5), xl=0, xb=(2.5, 1.5, -11.5), xd=(.2, .4, -.9)) if xb else dict(rh=(5.0, 2.0, -11.0), lh=(-6.5, 2.0, -11.5), bowup=(-.25, .1, .96)))
    K['RC1'] = _mk(lean=-4, drop=.4, hdrop=-12, fL=(-2.6, .3, 0), fR=(2.6, -.3, 0), **rc1)
    K['RC2'] = _mk(lean=-6, drop=0, hdrop=-18, sr=.4, goff=(0, 0, 5.0), fL=(-2.6, .3, .6), fR=(2.6, -.3, .6), **rc2)
    K['RC3'] = _mk(lean=-6, drop=0, hdrop=-18, sr=.4, goff=(0, 0, 9.0), fL=(-2.6, .3, .6), fR=(2.6, -.3, .6), **rc2)
    RMOVES['recall'] = (36, [(8, 'I', 'RC1', 'io', 0), (24, 'RC1', 'RC2', 'io', 0), (35, 'RC2', 'RC3', 'lin', 0)])
    RINFO['recall'] = dict(ko='귀환', fade=[24, 35], fx='recall_fx')

def react_frames(sp, name, d):
    inf = RINFO[name]
    if 'fn' in inf: return [render(sp, inf['fn'](i), d)[0] for i in range(inf['n'])]
    n, segs = RMOVES[name]
    saved = dict(anim8.MOVES); anim8.MOVES[name] = (n, segs)
    try: fr = [render(sp, blend_blade(pose_at(name, i)[0]), d)[0] for i in range(n)]
    finally: anim8.MOVES.clear(); anim8.MOVES.update(saved)
    if 'fade' in inf:
        a, b = inf['fade']
        for i in range(a, n):
            k = 1.0 - (i - a + 1) / (b - a + 1); im = fr[i].copy(); al = im.getchannel('A').point(lambda v: int(v * k)); im.putalpha(al); fr[i] = im
    return fr

def react_len(name): return RINFO[name]['n'] if 'fn' in RINFO[name] else RMOVES[name][0]
REACT_ORDER = ['hit_front', 'hit_back', 'hit_side', 'hit_heavy', 'knockback', 'stun', 'death_front', 'death_back', 'death_side', 'death_sit', 'downed', 'revive', 'potion', 'bandage', 'victory', 'rest', 'recall']
