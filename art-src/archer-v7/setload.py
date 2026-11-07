"""WN(a{n}_{bow} | xstage{n}) → sp 로드 (exportw.py와 같은 규칙)"""
import os
from anim8 import *
def load_set(WN):
    _src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'astages7.py')).read().split("set_weapon('bow'); P0 = idle(0)")[0].replace("OUT = sys.argv[1] if len(sys.argv) > 1 else 'stg'; os.makedirs(OUT, exist_ok=True)", '')
    _g = {}; exec(_src, _g)
    if WN.startswith('xstage'):
        _st = list(_g['STAGES'][int(WN[6:]) - 1]); _st[4] = 'crossbow'
        sp = _g['spec'](tuple(_st)); sp.update(xbow=True); BOWS[WN] = dict(BOWS['crossbow'])
    else:
        _n, _bw = int(WN[1]), WN.split('_', 1)[1]; _st = list(_g['STAGES'][_n - 1]); _st[4] = _bw
        sp = _g['spec'](tuple(_st)); BOWS[WN] = dict(BOWS[_bw])
    return sp
