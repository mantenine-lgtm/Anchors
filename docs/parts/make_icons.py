"""부품 아이콘: GPT 그림(바탕 파랑, 금속 회색, 칠 빨강, 빛 초록) -> 층 3장(금속·칠·빛, 흑백+알파) -> 종류마다 1024x1024 그림 1장.

게임에서는 같은 자리에 ImageLabel 3개를 겹쳐 ImageColor3 로 칠함: 금속 = 흰색(조금 Accent), 칠 = Main, 빛 = Glow.
한 칸 256x256, 4x4 격자. 모양 i(1~5)의 층 L(0 금속, 1 칠, 2 빛) 칸 번호 = (i-1)*3 + L, 칸 (번호 % 4, 번호 // 4).

쓰는 법: python3 make_icons.py <원본 폴더(<종류>_<1~5>.png)> <출력 폴더> [종류 ...]
"""
import os
import sys
import numpy as np
from PIL import Image

TYPES = ["engine", "heat", "fuel", "sail", "nav", "core"]
SHAPES = 5
TILE = 256
FIT = 228          # 물체의 긴 변 (칸 안 여백 14px: 이웃 칸이 번지지 않게)
GRID = 4


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def layers(path):
    P = np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255.0
    h, w, _ = P.shape
    border = np.concatenate([P[:4].reshape(-1, 3), P[-4:].reshape(-1, 3), P[:, :4].reshape(-1, 3), P[:, -4:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    R, G, B = P[..., 0], P[..., 1], P[..., 2]
    # 파란 화면 빼기: (파랑 - 빨강·초록 중 큰 값) 이 바탕만큼이면 투명. 회색과 섞인 가장자리는 정확히 비율이 나옴
    blue = B - np.maximum(R, G)
    bg_blue = max(bg[2] - max(bg[0], bg[1]), 0.2)
    alpha = np.clip(1.0 - blue / bg_blue, 0.0, 1.0)
    alpha = np.where(alpha < 0.04, 0.0, np.where(alpha > 0.96, 1.0, alpha))
    # 가장자리 색 되살리기 + 파랑 번짐 빼기
    a3 = np.maximum(alpha, 1e-3)[..., None]
    F = np.clip((P - (1.0 - alpha)[..., None] * bg) / a3, 0.0, 1.0)
    F[..., 2] = np.minimum(F[..., 2], np.maximum(F[..., 0], F[..., 1]))
    mx = F.max(axis=2)
    mn = F.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    # 색상: 빨강(칠) vs 초록(빛)
    r, g, b = F[..., 0], F[..., 1], F[..., 2]
    redness = r - np.maximum(g, b)
    greenness = g - np.maximum(r, b)
    s = smooth(sat, 0.22, 0.55)
    paint = s * smooth(redness - greenness, 0.02, 0.15)
    glow = s * smooth(greenness - redness, 0.02, 0.15)
    value = mx
    # 금속 층: 전체 모양(밝기), 칠·빛 층: 그 자리의 밝기 (게임에서 색을 곱함)
    base_v = value
    paint_v = np.clip(value * 1.05, 0, 1)
    glow_v = np.clip(0.35 + 0.75 * value, 0, 1)
    out = []
    for v, a in ((base_v, alpha), (paint_v, alpha * paint), (glow_v, alpha * glow)):
        g8 = (v * 255).round().astype(np.uint8)
        a8 = (a * 255).round().astype(np.uint8)
        out.append(Image.fromarray(np.dstack([g8, g8, g8, a8]), "RGBA"))
    stats = dict(bg=(bg * 255).round().tolist(), cover=float((alpha > 0.5).mean()),
                 paint=float((alpha * paint > 0.5).mean()), glow=float((alpha * glow > 0.5).mean()))
    return out, stats


def fit_tiles(imgs):
    """세 층을 같은 자리로 잘라 긴 변 FIT, 가운데 맞춤."""
    a = np.asarray(imgs[0])[..., 3]
    ys, xs = np.nonzero(a > 20)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    side = max(x1 - x0, y1 - y0)
    scale = FIT / side
    tiles = []
    for im in imgs:
        c = im.crop((x0, y0, x1, y1))
        nw, nh = max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))
        c = c.convert("RGBa").resize((nw, nh), Image.LANCZOS).convert("RGBA")
        t = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
        t.paste(c, ((TILE - nw) // 2, (TILE - nh) // 2))
        tiles.append(bleed(t))
    return tiles


def bleed(tile, steps=8):
    """투명한 곳의 색을 옆 불투명 칸 색으로 채움 (게임에서 가장자리를 섞을 때 검은 테두리가 생기지 않게)"""
    arr = np.asarray(tile).astype(np.float32)
    rgb, al = arr[..., :3].copy(), arr[..., 3]
    known = al > 0
    if not known.any():
        return tile
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(al.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            k = np.roll(known, (dy, dx), axis=(0, 1))
            acc += np.roll(rgb, (dy, dx), axis=(0, 1)) * k[..., None]
            cnt += k
        new = (~known) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        known |= new
    rgb[~known] = rgb[known].mean(axis=0)
    out = np.dstack([rgb, al]).round().clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def tint(tile, color):
    """미리보기용: ImageColor3 곱하기."""
    arr = np.asarray(tile).astype(np.float64)
    arr[..., :3] = arr[..., :3] * np.array(color, dtype=np.float64)[None, None, :] / 255.0
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def atlas_for(src, kind):
    sheet = Image.new("RGBA", (TILE * GRID, TILE * GRID), (0, 0, 0, 0))
    info = []
    for i in range(1, SHAPES + 1):
        path = os.path.join(src, f"{kind}_{i}.png")
        ls, st = layers(path)
        tiles = fit_tiles(ls)
        for L, t in enumerate(tiles):
            n = (i - 1) * 3 + L
            sheet.paste(t, ((n % GRID) * TILE, (n // GRID) * TILE))
        info.append((i, st))
    return sheet, info


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    kinds = sys.argv[3:] or TYPES
    os.makedirs(out, exist_ok=True)
    for kind in kinds:
        sheet, info = atlas_for(src, kind)
        path = os.path.join(out, f"parts_{kind}.png")
        sheet.save(path, optimize=True)
        print(kind, os.path.getsize(path), "bytes")
        for i, st in info:
            print("  ", i, st)
