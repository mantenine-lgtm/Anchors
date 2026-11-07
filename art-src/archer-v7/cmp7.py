import sys; from PIL import Image
con = Image.open('/mnt/project-files/uploads/hearth/38583abb-cda9-472c-a251-0fc247d7965d').convert('RGBA')
W, H, CX, FOOT = 56, 64, 28, 60
Z = int(sys.argv[1]) if len(sys.argv) > 1 else 4
d = 'SSW'; k = ['S','SSE','SE','ESE','E','ENE','NE','NNE','N','NNW','NW','WNW','W','WSW','SW','SSW'].index(d)
cw = 54
bg = con.crop((1000, 280, 1700, 380)).copy()      # 컨셉 경비병(원본 x=1382 → 382)은 그대로 두고 좌우에 배치
xs = [382 - cw * (5 - i) for i in range(5)] + [382 + cw * (i + 1) for i in range(5)]
sheets = [f'../astg6/archer_stage{n}_16dir_idle.png' for n in range(1, 6)] + [f'astg7/archer_stage{n}_16dir_idle.png' for n in range(1, 6)]
for x, s in zip(xs, sheets):
    f = Image.open(s).crop((k * W, 0, k * W + W, H))
    bg.alpha_composite(f, (int(x - CX), int(81 - FOOT)))
bg.resize((bg.width * Z, bg.height * Z), Image.NEAREST).convert('RGB').save('astg7/archer_v3_compare.png')
