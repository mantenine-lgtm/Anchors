import sys, os, json; sys.path.insert(0, '.')
from anim8 import *
OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)
BOWS['shortbow'] = dict(ko='단궁', h=10.5, ld=15.0, al=17.0)
BOWS['greatbow'] = dict(ko='룬 대궁', h=24.0, ld=18.0, al=22.0, rune=True)
# 단계, 이름, 몸통, 머리, 활, 추가 옵션 — 실루엣이 단계마다 다르게(맨머리·털 어깨·챙모자·챙투구+견갑·큰 후드+긴 망토)
AG = dict(noskirt=True, legmat='leather', brace='leather', taper=.8)          # 민첩형: 자락 없음, 가죽 바지
STAGES = [
 (1, '떠돌이 사냥꾼', 'n1', 'bare',   'shortbow', dict(AG, sleeve='short', beltarrows=2, quiver=False, build=-1.0, wrap=None)),
 (2, '숲 밀렵꾼',     'n2', 'coif',   'bow',      dict(AG, mantle=True, hipquiver=True, arrows=3, quiver=False, build=-.6, wrap='quilt', thighstrap=True)),
 (3, '순찰 궁수',     'n3', 'hat',    'longbow',  dict(AG, cloak=(14.0, 8.0), quiver=True, arrows=4, build=-.3, wrap='leather', kneepad='leather2')),
 (4, '장궁병',        'n4', 'leathercap', 'longbow',  dict(AG, quiver=True, arrows=6, qscale=1.45, bigpaul=True, build=.3, wrap='leather', kneepad='leather2', thighstrap=True)),
 (5, '그림자 사수',   'n5', 'bighood','greatbow', dict(AG, cloak=(10.0, 9.5), quiver=True, arrows=8, qscale=1.3, build=0.0, wrap='leather', kneepad='leather2', thighstrap=True)),
]
KO = {'n1': '아마 셔츠+짧은 가죽 조끼(소매 걷음)', 'n2': '짧은 천 상의+털 어깨걸이', 'n3': '짧은 누비 상의+허벅지 망토', 'n4': '가죽 흉갑·견갑', 'n5': '가죽 갑옷+무릎 망토',
      'bare': '맨머리', 'coif': '천 두건', 'hat': '챙 넓은 펠트 모자', 'leathercap': '가죽 모자', 'kettle': '가죽 챙투구', 'bighood': '큰 후드+얼굴 가리개'}
def offh(st):
    o = st[5]
    if o.get('beltarrows'): return f'허리띠 화살 {o["beltarrows"]}대'
    if o.get('hipquiver'): return f'허리 화살통 {o["arrows"]}대'
    return f'등 화살통 {o["arrows"]}대'
def spec(st):
    _, _, ar, hd, wp, o = st
    if wp == 'crossbow':                                   # 석궁: 석궁 전용 동작(set_weapon)과 xbow 렌더
        sp = set_weapon('crossbow'); sp.update(armor=ar, head=hd); sp.update(o); return sp
    set_weapon(wp if wp in ('bow', 'longbow', 'runebow') else 'bow'); sp = dict(fig4.CLASSES['archer']); sp.update(armor=ar, head=hd, bowspec=BOWS[wp]); sp.update(o); return sp
set_weapon('bow'); P0 = idle(0); P0.update(lh=(-5.4, 2.4, -13.2), bowup=(-.2, .1, .97), lean=3.0, fL=(-2.9, .6, 0.0), fR=(2.9, -.6, 0.0))   # 민첩형: 살짝 앞으로 숙이고 발을 벌림   # 활을 몸 밖으로 벌려 세움(실루엣에 보이게)
if len(sys.argv) > 2 and sys.argv[2] == 'test':
    Z = 4; ds = ['SSW', 'E', 'N']
    o = Image.new('RGBA', (W * Z * 5, H * Z * len(ds)), (42, 38, 35, 255))
    for j, st in enumerate(STAGES):
        sp = spec(st)
        for r_, d in enumerate(ds): o.alpha_composite(render(sp, P0, d)[0].resize((W * Z, H * Z), Image.NEAREST), (j * W * Z, r_ * H * Z))
    o.convert('RGB').save(f'{OUT}/test.png'); sys.exit()
meta = []
for st in STAGES:
    sp = spec(st); n = st[0]
    sh = Image.new('RGBA', (W * 16, H))
    for i, d in enumerate(DIRS): sh.alpha_composite(render(sp, P0, d)[0], (i * W, 0))
    sh.save(f'{OUT}/archer_stage{n}_16dir_idle.png')
    meta.append(dict(stage=n, name=st[1], armor=KO[st[2]], helmet=KO[st[3]], weapon=BOWS[st[4]]['ko'], offhand=offh(st), legs='가죽 바지' + {'quilt': '+천 각반', 'leather': '+가죽 각반', None: ''}[st[5]['wrap']] + ('+무릎 보호대' if st[5].get('kneepad') else ''), arms='가죽 아대'))
json.dump(dict(frameSize=[W, H], pivot=[CX, FOOT], directions=list(DIRS), stages=meta), open(f'{OUT}/archer_stages.json', 'w'), ensure_ascii=False, indent=1)
Z = 5; ds = ['SSW', 'SE', 'E', 'N']
o = Image.new('RGBA', (W * Z * 5, H * Z * len(ds)), (42, 38, 35, 255))
for j, st in enumerate(STAGES):
    sh = Image.open(f'{OUT}/archer_stage{st[0]}_16dir_idle.png')
    for r_, d in enumerate(ds):
        k = list(DIRS).index(d); o.alpha_composite(sh.crop((k * W, 0, k * W + W, H)).resize((W * Z, H * Z), Image.NEAREST), (j * W * Z, r_ * H * Z))
o.convert('RGB').save(f'{OUT}/archer_stages_compare.png')
D4 = ['S', 'N', 'E', 'W']
for st in STAGES:
    sh = Image.open(f'{OUT}/archer_stage{st[0]}_16dir_idle.png'); o4 = Image.new('RGBA', (W, H * 4))
    for r_, d in enumerate(D4):
        k = list(DIRS).index(d); o4.alpha_composite(sh.crop((k * W, 0, k * W + W, H)), (0, r_ * H))
    o4.save(f'{OUT}/archer_stage{st[0]}_4dir_idle.png')
