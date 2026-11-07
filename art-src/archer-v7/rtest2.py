import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from setload import *
from react8 import *
import anim8
WN, OUT = sys.argv[1], sys.argv[2]; sp = load_set(WN); build_react()
items = [(nm, int(f)) for nm, f in (x.split(':') for x in sys.argv[3].split(','))]
dirs = sys.argv[4].split(',') if len(sys.argv) > 4 else ['S', 'SE', 'E', 'N']
Z = 5
o = Image.new('RGBA', (W * Z * len(dirs), H * Z * len(items)), (42, 38, 35, 255))
from PIL import ImageDraw; dr = ImageDraw.Draw(o)
for r, (nm, f) in enumerate(items):
    inf = RINFO[nm]
    for c, d in enumerate(dirs):
        if 'fn' in inf: im = render(sp, inf['fn'](f), d)[0]
        else: anim8.MOVES[nm] = RMOVES[nm]; im = render(sp, blend_blade(pose_at(nm, f)[0]), d)[0]; del anim8.MOVES[nm]
        x, y = c * W * Z, r * H * Z
        o.alpha_composite(im.resize((W * Z, H * Z), Image.NEAREST), (x, y))
        dr.line([(x, y + FOOT * Z), (x + W * Z, y + FOOT * Z)], fill=(90, 70, 60)); dr.line([(x + W * Z // 2, y), (x + W * Z // 2, y + H * Z)], fill=(70, 70, 90))
        dr.text((x + 3, y + 3), f'{nm} {f} {d}', fill=(200, 200, 200))
o.save(OUT); print(o.size)
