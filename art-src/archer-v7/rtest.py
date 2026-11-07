import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('CELL_W','104'); os.environ.setdefault('CELL_H','96'); os.environ.setdefault('CELL_FOOT','82')
from setload import *
from react8 import *
WN, OUT, D = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else 'SE')
sp = load_set(WN); build_react()
names = sys.argv[4].split(',') if len(sys.argv) > 4 else REACT_ORDER
Z = 3; rows = []
for nm in names:
    n = react_len(nm); idx = sorted(set([0, n // 6, n // 3, n // 2, 2 * n // 3, 5 * n // 6, n - 1]))
    inf = RINFO[nm]
    if 'fn' in inf: fr = [render(sp, inf['fn'](i), D)[0] for i in idx]
    else:
        import anim8; anim8.MOVES[nm] = RMOVES[nm]; fr = [render(sp, blend_blade(pose_at(nm, i)[0]), D)[0] for i in idx]; del anim8.MOVES[nm]
    rows.append((nm, idx, fr))
o = Image.new('RGBA', (W * Z * 7 + 160, H * Z * len(rows)), (42, 38, 35, 255))
from PIL import ImageDraw; dr = ImageDraw.Draw(o)
for r, (nm, idx, fr) in enumerate(rows):
    dr.text((4, r * H * Z + 4), nm, fill=(200, 200, 200))
    for j, f in enumerate(fr):
        o.alpha_composite(f.resize((W * Z, H * Z), Image.NEAREST), (160 + j * W * Z, r * H * Z)); dr.text((160 + j * W * Z + 2, r * H * Z + 2), str(idx[j]), fill=(150, 150, 150))
o.save(OUT); print(OUT, o.size)
