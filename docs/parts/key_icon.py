"""뽑기 아이콘: GPT 그림(바탕 자홍 #FF00FF) -> 투명 바탕 RGBA, 물체를 가운데 맞춰 SIZE 정사각형.
  python3 key_icon.py <원본.png> <저장.png> [크기=512] [여백=12]"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 512
MARGIN = int(sys.argv[4]) if len(sys.argv) > 4 else 12
P = np.asarray(Image.open(src).convert("RGB")).astype(np.float64) / 255.0
h, w, _ = P.shape
border = np.concatenate([P[:4].reshape(-1, 3), P[-4:].reshape(-1, 3), P[:, :4].reshape(-1, 3), P[:, -4:].reshape(-1, 3)])
K = np.median(border, axis=0)
R, G, B = P[..., 0], P[..., 1], P[..., 2]
m = (np.minimum(R, B) - G) / max(min(K[0], K[2]) - K[1], 0.2)   # 자홍다움 (바탕 1)
fg = m < 0.12
bg = m > 0.92
# 물체 색을 바깥으로 번지게 해서 가장자리 픽셀마다 가까운 물체 색 O 를 구함
O = np.where(fg[..., None], P, 0.0)
known = fg.copy()
for _ in range(12):
    acc = np.zeros_like(O)
    cnt = np.zeros(known.shape)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        k2 = np.roll(np.roll(known, dy, 0), dx, 1)
        o2 = np.roll(np.roll(O, dy, 0), dx, 1)
        acc += o2 * k2[..., None]
        cnt += k2
    new = (~known) & (cnt > 0)
    O[new] = acc[new] / cnt[new][..., None]
    known |= new
# P = a*O + (1-a)*K 를 a 에 대해 풂 (가장자리), 물체 안은 1, 바탕은 0
d = O - K
a = np.sum((P - K) * d, axis=2) / np.maximum(np.sum(d * d, axis=2), 1e-6)
a = np.clip(a, 0.0, 1.0)
a = np.where(fg, 1.0, np.where(bg | ~known, 0.0, a))
F = np.where(fg[..., None], P, O)
F[..., 2] = np.minimum(F[..., 2], np.maximum(F[..., 1], F[..., 0] * 0.0 + F[..., 1]))  # 자홍 번짐(파랑) 빼기
rgba = np.dstack([np.clip(F, 0, 1) * 255, a * 255]).round().astype(np.uint8)
im = Image.fromarray(rgba, "RGBA")
ys, xs = np.nonzero(a > 0.08)
box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
crop = im.crop(box)
side = SIZE - 2 * MARGIN
scale = side / max(crop.size)
nw, nh = max(1, round(crop.size[0] * scale)), max(1, round(crop.size[1] * scale))
crop = crop.convert("RGBa").resize((nw, nh), Image.LANCZOS).convert("RGBA")
out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
out.paste(crop, ((SIZE - nw) // 2, (SIZE - nh) // 2))
out.save(dst, optimize=True)
print("saved", dst, out.size, "bg", (K * 255).round().tolist(), "box", box, "cover", round(float((a > 0.5).mean()), 3))
