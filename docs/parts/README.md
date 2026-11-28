# 부품 그림 (뽑기)

Nick 11-28: "부품 이미지 GPT로 생성", "300종 다 생성하지 말고 ... 색 필터를 덧씌워서", "애셋 크기 고려 ... 색 필터 바꿔서 애셋 사용을 줄여줘",
"아예 새로 이미지 다시 생성해서 다시 적용해볼것", "뽑기 아이콘은 캡슐 아이콘 말고 적당한 아이콘 알아서 생각해서 생성".

## 부품 180종 = 모양 30개 × 색

- `raw/<종류>_<1~5>.png`: GPT(ChatGPT 앱)가 그린 원본. 종류마다 모양 5개 (일반 1·2, 희귀 3, 영웅 4, 전설 5).
  열쇠 색으로 그림: 금속 회색, 칠 빨강(#FF0000), 빛 초록(#00FF00), 바탕 파랑(#0000FF). 글은 `prompts.txt`.
- `make_icons.py raw <출력 폴더>`: 바탕을 빼고 금속·칠·빛 3층(흑백+알파)으로 나눠 종류마다 `parts_<종류>.png` 한 장
  (1024×1024, 256 칸 4×4, 칸 번호 = (모양-1)×3 + 층).
- 게임(`src/client/PartIcon.luau`)은 같은 자리에 ImageLabel 3장을 겹쳐 금속 = 흰색(조금 Accent), 칠 = Main, 빛 = Glow 로 칠함.
  부품마다 색(`src/shared/Catalog.luau` 의 Look)만 달라서 그림 6장으로 180종을 그림.

## 뽑기 그림

- `gacha_icon.png` (512×512, 투명 바탕): 부품이 삐져나온 금색 우주 보급 상자. 뽑기 버튼·뽑기 칸·결과 연출에 씀.
  원본 `raw/gacha_icon_1.png` (바탕 자홍 #FF00FF, 글은 `gacha_icon_prompt.txt`), `key_icon.py raw/gacha_icon_1.png gacha_icon.png` 로 바탕을 뺌.

## 올린 Id

`Catalog.IconImages` (종류마다 하나)와 `Catalog.GachaIcon`. 비어 있으면 예전처럼 Frame 으로 그림.
