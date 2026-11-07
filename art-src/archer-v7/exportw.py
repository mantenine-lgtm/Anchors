import sys, json, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anim8 import *
WN = sys.argv[1]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
CON = '/mnt/project-files/uploads/hearth/38583abb-cda9-472c-a251-0fc247d7965d'
if WN.startswith('xstage'):                      # 궁수 단계 복장 + 석궁
    _src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'astages7.py')).read().split("set_weapon('bow'); P0 = idle(0)")[0].replace("OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)", '')
    _g = {}; exec(_src, _g); _st = list(_g['STAGES'][int(WN[6:]) - 1]); _st[4] = 'crossbow'
    sp = _g['spec'](tuple(_st)); sp.update(xbow=True); BOWS[WN] = dict(BOWS['crossbow'])
elif WN[0] == 'a' and '_' in WN and WN[1].isdigit():   # a{n}_{bow}: 궁수 n단계 복장 + 지정 활(단궁·활·장궁·룬활)
    _src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'astages7.py')).read().split("set_weapon('bow'); P0 = idle(0)")[0].replace("OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)", '')
    _g = {}; exec(_src, _g); _n, _bw = int(WN[1]), WN.split('_', 1)[1]; _st = list(_g['STAGES'][_n - 1]); _st[4] = _bw
    sp = _g['spec'](tuple(_st)); BOWS[WN] = dict(BOWS[_bw])
elif WN.startswith('astage'):                      # 궁수 단계별 장비(astages.py STAGES)
    _src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'astages7.py')).read().split("set_weapon('bow'); P0 = idle(0)")[0].replace("OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)", '')
    _g = {}; exec(_src, _g); _st = _g['STAGES'][int(WN[6:]) - 1]
    sp = _g['spec'](_st); BOWS[WN] = dict(BOWS[_st[4]])
elif WN.startswith('stage'):                       # 전사 단계별 장비(stages.py STAGES)
    import importlib.util as _iu
    _src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'stages.py')).read().split('P0 = idle(0)')[0].replace("OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)", '')
    _g = {}; exec(_src, _g); _st = _g['STAGES'][int(WN[5:]) - 1]
    sp = set_weapon(_st[4]); sp.update(_g['spec'](_st)); WEAPONS[WN] = dict(WEAPONS[_st[4]]); WSET[WN] = (WSET[_st[4]][0], _st[5], WSET[_st[4]][2])
else:
    sp = set_weapon(WN)
F = all_anims(sp)
anims = ['idle', 'walk', 'run', 'combat_idle', 'combat_walk'] + (['combat_run'] if 'combat_run_S' in F else []) + list(MOVES)
rows = [f'{a}_{d}' for a in anims for d in DIRS]
NMAX = max([24] + [MOVES[m][0] for m in MOVES])
sh = Image.new('RGBA', (W * NMAX, H * len(rows)))
for r, k in enumerate(rows):
    for i, f in enumerate(F[k]): sh.alpha_composite(f, (i * W, r * H))
sh.save(f'{OUT}/{WN}_16dir_sheet.png')
json.dump({'weapon': WN, 'weaponKo': (WEAPONS.get(WN) or BOWS[WN])['ko'], 'offhand': WSET[WN][1] if WN in WSET else None, 'releaseIsProjectile': WN in BOWS, 'frameSize': [W, H], 'pivot': [CX, FOOT], 'fps': 24, 'cameraPitchDeg': PITCH, 'directions': list(DIRS), 'rows': rows,
           'frames': {a: (24 if a in ('idle', 'walk', 'combat_idle', 'combat_walk') else NR if a in ('run', 'combat_run') else MOVES[a][0]) for a in anims},
           'footContactFrames': {k: v for k, v in {'walk': {'L': 6, 'R': 18}, 'combat_walk': {'L': 6, 'R': 18}, 'run': {'L': 4, 'R': 12}, 'combat_run': {'L': 4, 'R': 12}}.items() if k in anims}, 'hitFrames': HITS, 'moveForwardFrames': MOVE_FORWARD, 'attackPool': [{'anim': k, 'hits': COMBO_DESC[k], 'weight': 1} for k in COMBOS], 'attackSelection': 'random (같은 콤보 연속 금지 권장)'},
          open(f'{OUT}/{WN}_16dir_sheet.json', 'w'), indent=1)
S = 3
import math as _m
order = list(DIRS); pos = []
for _i, _d in enumerate(order):               # 5x5 테두리 16칸에 방향대로 배치
    _a = _m.atan2(-DIRS[_d][1], DIRS[_d][0]); _x, _y = _m.cos(_a), _m.sin(_a); _k = 2 / max(abs(_x), abs(_y))
    pos.append((int(round(2 + _x * _k)), int(round(2 + _y * _k))))
def grid(seqs, n, name, label_center=None):
    fr = []
    for i in range(n):
        o = Image.new('RGBA', (W * S * 5, H * S * 5), (42, 38, 35, 255))
        for d, (gx, gy) in zip(order, pos):
            sq = seqs[d]; o.alpha_composite(sq[min(i, len(sq) - 1)].resize((W * S, H * S), Image.NEAREST), (gx * W * S, gy * H * S))
        fr.append(o.convert('RGB'))
    fr[0].save(f'{OUT}/{name}', save_all=True, append_images=fr[1:], duration=42, loop=0)
grid({d: F['walk_' + d] for d in DIRS}, 24, f'{WN}_16dir_walk.gif')
grid({d: F['idle_' + d] for d in DIRS}, 24, f'{WN}_16dir_idle.gif')
grid({d: F['combat_idle_' + d] for d in DIRS}, 24, f'{WN}_16dir_combat_idle.gif')
for _k in COMBOS: grid({d: F[f'{_k}_' + d] for d in DIRS}, MOVES[_k][0], f'{WN}_16dir_{_k}.gif')
# 미리보기: 캐릭터만 크게 — 전투 준비자세 → 무작위 콤보 → 준비자세
import random as _r; _r.seed(5); _pk, _last = [], None
for _ in range(9):
    _c = _r.choice([c for c in COMBOS if c != _last]); _pk.append(_c); _last = _c
seq = F['idle_SSW'][:12] + F['ready_in_SSW'] + F['combat_walk_SSW'] + F['combat_idle_SSW'] * 2
for c in _pk: seq += F[f'{c}_SSW'] + F['combat_idle_SSW'][:12]
Z = 6; g = []
for f in seq:
    bg = Image.new('RGBA', (W, H), (42, 38, 35, 255)); bg.alpha_composite(f); g.append(bg.resize((W * Z, H * Z), Image.NEAREST).convert('RGB'))
g[0].save(f'{OUT}/{WN}_16dir_preview.gif', save_all=True, append_images=g[1:], duration=42, loop=0)
json.dump(_pk, open(f'{OUT}/{WN}_16dir_preview_order.json', 'w'), ensure_ascii=False)
