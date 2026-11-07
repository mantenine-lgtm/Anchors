"""귀환 발밑 빛 이펙트(공용, 방향 무관): recall_fx_back.png / recall_fx_front.png — 36f, 칸 104×96 피벗(52,82), 2px 도트, 16행(모두 동일) """
import sys, os, math, random
import numpy as np
from PIL import Image
W, H, CX, FY, N = 104, 96, 52, 82, 36
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
rnd = random.Random(7)
streaks = []   # (x, phase_start, speed, length, bright)
for k in range(26):
    a = rnd.uniform(0, 2 * math.pi); r = math.sqrt(rnd.uniform(.15, 1.0))
    streaks.append((r * math.cos(a), r * math.sin(a), rnd.uniform(4, 26), rnd.uniform(2.2, 3.4), rnd.randint(6, 16), rnd.uniform(.6, 1.0)))
def dot(buf, x, y, v, a):           # 2px 격자 스냅
    x = int(x) // 2 * 2; y = int(y) // 2 * 2
    if 0 <= x < W - 1 and 0 <= y < H - 1:
        old = buf[y:y + 2, x:x + 2]; na = np.maximum(old[..., 3], a * 255)
        old[..., 0:3] = np.where(old[..., 3:4] < a * 255, v, old[..., 0:3]); old[..., 3] = na
back = [np.zeros((H, W, 4), np.uint8) for _ in range(N)]; front = [np.zeros((H, W, 4), np.uint8) for _ in range(N)]
for f in range(N):
    g = min(1.0, f / 7.0); fade = 1.0 if f < 24 else max(0.0, 1 - (f - 23) / 12.0)
    rx = 4 + 12 * (1 - (1 - g) ** 2); ry = rx * .45
    # 바닥 고리(위쪽 절반은 뒤, 아래쪽은 앞) + 안쪽 은은한 빛
    for i in range(72):
        a = 2 * math.pi * i / 72; x = CX + rx * math.cos(a); y = FY + ry * math.sin(a)
        v = int(150 + 40 * (.5 + .5 * math.sin(f * .6 + i * .3))); al = (.75 + .2 * math.sin(f * .5 + i * .4)) * fade
        dot(back[f] if y < FY else front[f], x, y, v, al)
    for i in range(40):
        a = 2 * math.pi * i / 40; r = rnd.uniform(.2, .85); x = CX + rx * r * math.cos(a); y = FY + ry * r * math.sin(a)
        dot(back[f] if y < FY else front[f], x, y, 120, .22 * fade * g)
    # 솟는 빛줄기
    for (ux, uy, ph, sp, ln, br) in streaks:
        t = f - 6 - ph * .35
        if t < 0: continue
        x = CX + ux * rx * .9; y0 = FY + uy * ry * .9; rise = (t * sp) % 46
        layer = back[f] if uy < 0 else front[f]
        for s in range(ln):
            yy = y0 - rise + s * 2
            if yy > y0: continue
            hv = max(0.0, 1 - (y0 - yy) / 46.0); al = br * hv * (1 - s / ln) * fade * .95
            dot(layer, x, yy, int(160 + 50 * hv), al)
def save(frames, name):
    sh = Image.new('RGBA', (W * N, H * 16))
    for i, b in enumerate(frames):
        im = Image.fromarray(b, 'RGBA')
        for r in range(16): sh.paste(im, (i * W, r * H))
    sh.save(f'{OUT}/{name}.png')
save(back, 'recall_fx_back'); save(front, 'recall_fx_front')
# 검수 gif: 뒤+앞 합성
g = []
for i in range(N):
    bg = Image.new('RGBA', (W, H), (42, 38, 35, 255)); bg.alpha_composite(Image.fromarray(back[i], 'RGBA')); bg.alpha_composite(Image.fromarray(front[i], 'RGBA'))
    g.append(bg.resize((W * 4, H * 4), Image.NEAREST).convert('RGB'))
g[0].save(f'{OUT}/recall_fx_preview.gif', save_all=True, append_images=g[1:], duration=42, loop=0)
sheet = Image.new('RGB', (W * 9 * 3, H * 3), (42, 38, 35))
for i in range(9):
    f = i * 4; bg = Image.new('RGBA', (W, H), (42, 38, 35, 255)); bg.alpha_composite(Image.fromarray(back[f], 'RGBA')); bg.alpha_composite(Image.fromarray(front[f], 'RGBA'))
    sheet.paste(bg.resize((W * 3, H * 3), Image.NEAREST).convert('RGB'), (i * W * 3, 0))
sheet.save(f'{OUT}/recall_fx_check.png'); print('ok')
