"""피격·사망·상황 동작 16방향 출력: python3 exportr.py <set> <outdir>  → <set>_16dir_react_sheet.png/json"""
import sys, os, json, time; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from setload import *
from react8 import *
WN, OUT = sys.argv[1], sys.argv[2]; os.makedirs(OUT, exist_ok=True)
sp = load_set(WN); build_react()
t0 = time.time(); F = {}
REUSE = os.environ.get('REUSE'); old = None
if REUSE and os.path.exists(f'{REUSE}/{WN}_16dir_react_sheet.json'):          # 바뀌지 않은 동작은 이전 시트 행을 재사용
    old = json.load(open(f'{REUSE}/{WN}_16dir_react_sheet.json')); oim = Image.open(f'{REUSE}/{WN}_16dir_react_sheet.png')
OLDNAME = {'bandage': 'heal'}; KEEP = {'stun', 'death_front', 'death_back', 'death_side', 'potion', 'bandage', 'victory', 'rest'}
for nm in REACT_ORDER:
    on = OLDNAME.get(nm, nm)
    if old and nm in KEEP and on in old['frames'] and old['frames'][on] == react_len(nm):
        for d in DIRS:
            ri = old['rows'].index(f'{on}_{d}'); F[f'{nm}_{d}'] = [oim.crop((i * W, ri * H, i * W + W, ri * H + H)) for i in range(old['frames'][on])]
        print(nm, 'reused', flush=True); continue
    for d in DIRS: F[f'{nm}_{d}'] = react_frames(sp, nm, d)
    print(nm, round(time.time() - t0), flush=True)
rows = [f'{a}_{d}' for a in REACT_ORDER for d in DIRS]; NMAX = max(react_len(a) for a in REACT_ORDER)
sh = Image.new('RGBA', (W * NMAX, H * len(rows)))
for r, k in enumerate(rows):
    for i, f in enumerate(F[k]): sh.alpha_composite(f, (i * W, r * H))
sh.save(f'{OUT}/{WN}_16dir_react_sheet.png')
info = {a: dict(frames=react_len(a), ko=RINFO[a]['ko'], loop=bool(RINFO[a].get('loop')), hold=bool(RINFO[a].get('hold')), **({'moveBack': RINFO[a]['moveBack']} if 'moveBack' in RINFO[a] else {})) for a in REACT_ORDER}
json.dump({'weapon': WN, 'kind': 'react', 'frameSize': [W, H], 'pivot': [CX, FOOT], 'fps': 24, 'directions': list(DIRS), 'rows': rows,
           'frames': {a: react_len(a) for a in REACT_ORDER}, 'react': info,
           'groups': {'hit': ['hit_front', 'hit_back', 'hit_side'], 'hit_heavy': ['hit_heavy'], 'death': ['death_front', 'death_back', 'death_side', 'death_sit'], 'knockback': ['knockback'], 'stun': ['stun'], 'downed': ['downed'], 'revive': ['revive'], 'bandage': ['bandage'], 'potion': ['potion'], 'victory': ['victory'], 'rest': ['rest'], 'recall': ['recall']},
           'fx': {'recall': ['recall_fx_back', 'recall_fx_front']},
           'note': '영웅 공통 16종. 피격 앞/뒤/옆구리는 맞은 방향(모르면 무작위), 강한 피격은 큰 데미지. 피격·넉백은 전투 준비자세에서 시작해 준비자세로 복귀. death 4종 무작위·끝 유지(hold), stun·downed·rest 반복(loop). knockback은 moveBack 구간 동안 게임이 캐릭터를 뒤로 이동. revive는 downed 자세에서 시작. recall은 24~35f 알파 페이드, 발밑 빛 recall_fx_back(캐릭터 뒤)/front(앞) 36f 공용 시트.'},
          open(f'{OUT}/{WN}_16dir_react_sheet.json', 'w'), indent=1, ensure_ascii=False)
# 검수 gif: SSW 방향 전체 동작 연속
Z = 5; g = []
for a in REACT_ORDER:
    for f in F[f'{a}_SSW'] + [F[f'{a}_SSW'][-1]] * 6:
        bg = Image.new('RGBA', (W, H), (42, 38, 35, 255)); bg.alpha_composite(f); g.append(bg.resize((W * Z, H * Z), Image.NEAREST).convert('RGB'))
g[0].save(f'{OUT}/{WN}_16dir_react_preview.gif', save_all=True, append_images=g[1:], duration=42, loop=0)
print('DONE', WN, round(time.time() - t0))
