--!strict
-- 부품 도감 (Nick 11-28 "부품 종류도 다양화", "총 300종 수준"): 부품 종류(엔진 등 6종)마다 50개, 모두 300개.
-- 종류마다 일반 15 · 희귀 15 · 영웅 12 · 전설 8. 능력치(파워)는 레어도와 레벨만 정하고, 같은 레어도 안에서는 이름과 모양만 다릅니다.
--   1) 종류마다 따로 지은 부품 11개 (일반 3 · 희귀 3 · 영웅 3 · 전설 2. 기획서 '부품 목록'의 42개에 24개를 더함)
--   2) 세트 39개 × 6종류 = 234개: 세트 하나가 6종류를 모두 가짐 (예: 태양 엔진 · 태양 방열판 · … · 태양 코어).
--      세트는 일반 12 · 희귀 12 · 영웅 9 · 전설 6. 이름 = 세트 이름 + 종류 이름, 설명 = 세트의 빛 + 종류의 이펙트.
-- 모양(Look)은 화면 아이콘에만 씁니다 (클라이언트 PartIcon.luau). 로켓에는 부품 모델을 따로 두지 않습니다 (부품은 이펙트로만, 기획).
--   그림(Shape): 종류마다 GPT 로 만든 모양 5개 중 하나 (Nick 11-28 "부품 이미지 GPT로 생성", "모든걸 새로 만들지 말고
--   색 필터 바꿔서 애셋 사용을 줄여줘"). 희귀할수록 화려한 모양: 일반 1·2, 희귀 2·3, 영웅 3·4, 전설 4·5.
--   같은 그림을 칠 색(Main)·빛 색(Glow)·금속 색조(Accent)와 뒤에 까는 빛 무늬(Aura)로 다르게 보이게 함.
--   그림은 종류마다 한 장(IconImages, 1024x1024 안에 모양 5개 × 층 3장: 금속·칠·빛). 그림 Id 가 비어 있으면
--   예전처럼 Frame 몇 개로 그림 (몸통 Body, 종류마다 4가지).
-- Id 는 따로 지은 부품 "<종류>_<레어도 글자><번호>" (예: engine_l2), 세트 부품 "<종류>_<세트 Id>" (예: core_sun).
-- 저장·신호에 쓰므로 한 번 정하면 바꾸지 않습니다.

local Config = require(script.Parent.Config)

local Catalog = {}

export type Look = { Body: string, Shape: number, Aura: string, Main: Color3, Accent: Color3, Glow: Color3 }
export type Variant = { Id: string, Type: string, Rarity: number, Name: string, Desc: string, Look: Look, Set: string? }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- 레어도 색 (일반 회색, 희귀 파랑, 영웅 보라, 전설 주황금: 기획서 '부품 목록'). '머리 뒤 희귀도 구' 작업이 같은 표를
-- Config.Parts.RarityColors 에 { R, G, B } 숫자로 넣으면 그것을 쓰고, 없으면 같은 값 (Config 는 Roblox 자료형 없이 숫자만 둠)
local RARITY_RGB: { { number } } = ((Config.Parts :: any).RarityColors :: { { number } }?) or {
	{ 130, 138, 150 },
	{ 40, 130, 255 },
	{ 140, 60, 255 },
	{ 255, 130, 0 },
}
Catalog.RarityColors = {} :: { Color3 }
for index, c in ipairs(RARITY_RGB) do
	Catalog.RarityColors[index] = rgb(c[1], c[2], c[3])
end
Catalog.RarityLetters = { "c", "r", "e", "l" }

-- 어두운 화면 위 글자에 쓰는 레어도 색 (조금 밝게)
function Catalog.rarityText(rarity: number): Color3
	local color = Catalog.RarityColors[math.clamp(math.floor(rarity), 1, #Catalog.RarityColors)]
	return color:Lerp(Color3.new(1, 1, 1), 0.3)
end

local function look(body: string, aura: string, main: Color3, accent: Color3, glow: Color3): Look
	return { Body = body, Shape = 1, Aura = aura, Main = main, Accent = accent, Glow = glow } -- Shape 는 아래에서 정함
end

-- 부품 그림 (종류마다 한 장, Roblox 에 올린 이미지 Id). 칸 하나 IconTile 픽셀, 한 줄 IconGrid 칸.
-- 모양 s(1~5)의 층 L(0 금속, 1 칠, 2 빛) 칸 번호 = (s - 1) * 3 + L → (번호 % IconGrid, 번호 // IconGrid) 칸.
-- 원본·만드는 법: 프로젝트 파일 gacha/icons (make_icons.py), 저장소 docs/parts/.
Catalog.IconImages = {
	engine = "",
	heat = "",
	fuel = "",
	sail = "",
	nav = "",
	core = "",
} :: { [string]: string }
Catalog.IconTile = 256
Catalog.IconGrid = 4
Catalog.Shapes = 5

-- 레어도마다 쓰는 그림 두 가지 (번갈아): 희귀할수록 화려한 모양
local SHAPES_BY_RARITY = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 5, 5, 4 } }

-- 종류마다 몸통 4가지 (PartIcon 이 그림). 빛 무늬: none · ring · rings · orbit · wings · burst · bolt · dots · grid · flame
-- 종류 Id -> { 이름, 이펙트 낱말, 몸통 4가지 }
local TYPE_WORDS: { [string]: { Noun: string, Effect: string, Bodies: { string } } } = {
	engine = { Noun = "엔진", Effect = "불꽃", Bodies = { "standard", "twin", "pillar", "wide" } },
	heat = { Noun = "방열판", Effect = "냉기", Bodies = { "fins", "fan", "panels", "coil" } },
	fuel = { Noun = "연료탱크", Effect = "연료", Bodies = { "tank", "twin", "sphere", "drum" } },
	sail = { Noun = "돛", Effect = "막", Bodies = { "diamond", "square", "dome", "double" } },
	nav = { Noun = "항법기", Effect = "홀로그램", Bodies = { "screen", "dish", "chip", "antenna" } },
	core = { Noun = "코어", Effect = "파동", Bodies = { "orb", "battery", "crystal", "atom" } },
}

-- 1) 종류마다 따로 지은 부품: 종류 Id -> { 레어도, 이름, 설명(이펙트), 모양 }
local RAW: { [string]: { { any } } } = {
	engine = {
		{ 1, "깡통 엔진", "회색 연기가 섞인 작은 불꽃", look("standard", "none", rgb(150, 156, 170), rgb(96, 100, 112), rgb(255, 150, 70)) },
		{ 1, "고물 부스터", "덜컹거리며 튀는 주황 불티", look("wide", "dots", rgb(168, 120, 84), rgb(110, 84, 64), rgb(255, 170, 60)) },
		{ 1, "폭죽 엔진", "탁탁 터지는 빨간 불꽃", look("pillar", "burst", rgb(220, 70, 70), rgb(250, 240, 220), rgb(255, 210, 90)) },
		{ 2, "블루 버너", "곧게 뻗는 파란 불꽃", look("standard", "none", rgb(120, 150, 200), rgb(70, 90, 140), rgb(80, 170, 255)) },
		{ 2, "쌍발 터빈", "나란히 뻗는 파란 불꽃 두 줄", look("twin", "dots", rgb(140, 160, 200), rgb(70, 90, 140), rgb(90, 190, 255)) },
		{ 2, "제트 노즐", "고리 모양으로 뿜는 하늘색 바람", look("standard", "rings", rgb(200, 210, 230), rgb(80, 120, 190), rgb(140, 220, 255)) },
		{ 3, "플라즈마 드라이브", "보라 플라즈마 기둥과 스파크", look("pillar", "flame", rgb(120, 70, 200), rgb(60, 30, 120), rgb(210, 120, 255)) },
		{ 3, "펄스 엔진", "보라 고리가 연달아 터지는 불꽃", look("standard", "rings", rgb(140, 90, 210), rgb(70, 40, 130), rgb(230, 150, 255)) },
		{ 3, "이온 스러스터", "푸른 보라 이온 빛줄기", look("wide", "bolt", rgb(90, 80, 190), rgb(40, 40, 110), rgb(150, 140, 255)) },
		{ 4, "초신성 엔진", "금빛 불기둥과 별가루", look("pillar", "burst", rgb(255, 200, 70), rgb(170, 110, 20), rgb(255, 240, 160)) },
		{ 4, "용의 숨결", "용 머리 모양의 금빛 화염", look("pillar", "wings", rgb(220, 150, 40), rgb(140, 60, 20), rgb(255, 220, 100)) },
	},
	heat = {
		{ 1, "철판 방열판", "옅은 흰 김", look("fins", "none", rgb(150, 158, 172), rgb(100, 106, 120), rgb(230, 240, 255)) },
		{ 1, "청동 핀", "따뜻한 청동빛 김", look("fins", "dots", rgb(190, 140, 80), rgb(120, 86, 50), rgb(255, 210, 150)) },
		{ 1, "선풍기 팬", "빙글빙글 도는 바람", look("fan", "ring", rgb(170, 200, 190), rgb(90, 110, 104), rgb(220, 255, 240)) },
		{ 2, "서리 핀", "파란 서리 결정", look("fins", "burst", rgb(150, 200, 255), rgb(70, 120, 200), rgb(200, 240, 255)) },
		{ 2, "냉각 코일", "고리 모양의 파란 냉기", look("coil", "rings", rgb(90, 160, 240), rgb(40, 80, 160), rgb(160, 220, 255)) },
		{ 2, "얼음 격자", "격자 틈으로 새는 하늘색 냉기", look("panels", "grid", rgb(120, 190, 240), rgb(50, 100, 170), rgb(190, 240, 255)) },
		{ 3, "빙결 라디에이터", "보라 얼음 날개와 냉기", look("panels", "wings", rgb(160, 120, 240), rgb(80, 50, 160), rgb(220, 190, 255)) },
		{ 3, "증기 벤트", "양옆으로 뿜는 보라 증기", look("fins", "dots", rgb(130, 100, 200), rgb(70, 50, 120), rgb(230, 210, 255)) },
		{ 3, "극저온 펌프", "보라 액체가 도는 냉각 관", look("coil", "orbit", rgb(110, 80, 210), rgb(50, 30, 110), rgb(200, 160, 255)) },
		{ 4, "절대영도 날개", "금빛 얼음 결정 날개와 눈보라", look("panels", "wings", rgb(255, 220, 120), rgb(180, 130, 40), rgb(255, 250, 210)) },
		{ 4, "불사조 깃", "금빛 깃털 불꽃", look("fan", "wings", rgb(255, 170, 60), rgb(200, 70, 30), rgb(255, 230, 120)) },
	},
	fuel = {
		{ 1, "드럼통 탱크", "희미한 불빛", look("drum", "none", rgb(150, 110, 90), rgb(90, 70, 60), rgb(255, 210, 140)) },
		{ 1, "가스통", "작게 새는 초록 불빛", look("tank", "dots", rgb(110, 160, 110), rgb(60, 100, 60), rgb(180, 255, 170)) },
		{ 1, "보온병 탱크", "따뜻한 은빛 김", look("tank", "ring", rgb(190, 196, 206), rgb(120, 126, 140), rgb(255, 240, 220)) },
		{ 2, "압축 탱크", "맥박처럼 뛰는 파란 빛", look("drum", "none", rgb(90, 140, 220), rgb(40, 70, 140), rgb(130, 210, 255)) },
		{ 2, "이중 탱크", "파란 빛 띠 두 줄", look("twin", "dots", rgb(100, 150, 230), rgb(40, 70, 140), rgb(150, 220, 255)) },
		{ 2, "캡슐 탱크", "알약 모양의 파란 연료", look("tank", "orbit", rgb(80, 170, 240), rgb(230, 240, 255), rgb(170, 230, 255)) },
		{ 3, "반물질 셀", "보라 구체", look("sphere", "ring", rgb(140, 70, 220), rgb(60, 20, 120), rgb(230, 160, 255)) },
		{ 3, "게이지 저장고", "차오르는 보라 눈금", look("drum", "grid", rgb(110, 60, 190), rgb(50, 30, 100), rgb(255, 120, 230)) },
		{ 3, "핵융합 셀", "안에서 소용돌이치는 보라 불", look("sphere", "rings", rgb(150, 90, 230), rgb(70, 30, 140), rgb(255, 180, 255)) },
		{ 4, "별의 샘", "금빛 액체가 솟는 샘", look("tank", "burst", rgb(255, 200, 80), rgb(170, 110, 30), rgb(255, 245, 180)) },
		{ 4, "은하수 탱크", "금빛 은하수 띠", look("sphere", "orbit", rgb(60, 40, 120), rgb(255, 200, 80), rgb(255, 230, 150)) },
	},
	sail = {
		{ 1, "은박 돛", "작은 은회색 빛 막", look("diamond", "none", rgb(196, 202, 214), rgb(120, 126, 140), rgb(240, 245, 255)) },
		{ 1, "비닐 돛", "반투명하게 펄럭이는 막", look("square", "grid", rgb(180, 220, 210), rgb(100, 130, 124), rgb(230, 255, 250)) },
		{ 1, "우산 돛", "둥글게 펼친 빨간 막", look("dome", "ring", rgb(220, 80, 80), rgb(120, 60, 60), rgb(255, 200, 200)) },
		{ 2, "푸른 빛 돛", "파란 반투명 막", look("diamond", "none", rgb(90, 160, 255), rgb(40, 80, 170), rgb(170, 220, 255)) },
		{ 2, "연 꼬리 돛", "길게 늘어진 파란 빛 리본", look("double", "dots", rgb(80, 140, 250), rgb(40, 70, 160), rgb(160, 210, 255)) },
		{ 2, "부채 돛", "접었다 펴는 파란 부채", look("dome", "ring", rgb(100, 170, 240), rgb(40, 80, 150), rgb(190, 230, 255)) },
		{ 3, "오로라 돛", "보라 오로라 커튼", look("square", "wings", rgb(160, 100, 240), rgb(60, 200, 180), rgb(220, 180, 255)) },
		{ 3, "프리즘 돛", "무지개로 갈라지는 보라 막", look("diamond", "burst", rgb(170, 120, 255), rgb(255, 120, 180), rgb(200, 255, 255)) },
		{ 3, "나비 날개 돛", "보라 무늬 날개 두 쌍", look("double", "wings", rgb(150, 80, 230), rgb(255, 160, 220), rgb(230, 190, 255)) },
		{ 4, "태양왕의 망토", "금빛 망토", look("square", "flame", rgb(255, 190, 60), rgb(200, 60, 50), rgb(255, 240, 170)) },
		{ 4, "천사 날개 돛", "금빛 날개 한 쌍", look("double", "wings", rgb(255, 230, 150), rgb(220, 170, 60), rgb(255, 250, 220)) },
	},
	nav = {
		{ 1, "나침반 컴퓨터", "회색 점선 조준선", look("dish", "ring", rgb(170, 176, 190), rgb(220, 70, 70), rgb(240, 245, 255)) },
		{ 1, "주판 컴퓨터", "딸깍거리는 나무 구슬", look("chip", "grid", rgb(170, 120, 80), rgb(220, 180, 120), rgb(255, 230, 180)) },
		{ 1, "무전기", "치직거리는 초록 신호", look("antenna", "bolt", rgb(110, 130, 110), rgb(60, 70, 60), rgb(150, 255, 150)) },
		{ 2, "별지도 컴퓨터", "파란 별자리 홀로그램", look("screen", "burst", rgb(40, 70, 140), rgb(120, 200, 255), rgb(200, 240, 255)) },
		{ 2, "레이더 돔", "퍼지는 파란 레이더 파동", look("dish", "rings", rgb(70, 130, 220), rgb(30, 60, 120), rgb(140, 220, 255)) },
		{ 2, "위성 안테나", "하늘로 쏘는 파란 신호", look("antenna", "dots", rgb(200, 210, 230), rgb(70, 120, 200), rgb(140, 210, 255)) },
		{ 3, "양자 항법기", "보라 격자 홀로그램", look("screen", "grid", rgb(60, 30, 120), rgb(190, 130, 255), rgb(230, 200, 255)) },
		{ 3, "예언자 칩", "앞길을 그리는 보라 궤적선", look("chip", "orbit", rgb(90, 60, 170), rgb(210, 160, 255), rgb(240, 210, 255)) },
		{ 3, "홀로 큐브", "빙글 도는 보라 빛 상자", look("chip", "rings", rgb(130, 80, 220), rgb(230, 180, 255), rgb(240, 220, 255)) },
		{ 4, "은하 길잡이", "금빛 별길", look("screen", "burst", rgb(60, 40, 100), rgb(255, 210, 90), rgb(255, 245, 190)) },
		{ 4, "시간의 눈", "금빛 눈 문양과 톱니 빛", look("dish", "rings", rgb(255, 200, 70), rgb(120, 60, 20), rgb(255, 245, 190)) },
	},
	core = {
		{ 1, "건전지 코어", "약한 회색 깜빡임", look("battery", "none", rgb(160, 166, 180), rgb(80, 84, 96), rgb(220, 255, 160)) },
		{ 1, "전구 코어", "노랗게 깜빡이는 필라멘트", look("orb", "burst", rgb(240, 220, 150), rgb(130, 130, 140), rgb(255, 240, 140)) },
		{ 1, "자석 코어", "끌어당기는 빨강·파랑 빛", look("battery", "dots", rgb(220, 70, 70), rgb(200, 205, 215), rgb(255, 200, 200)) },
		{ 2, "번개 코어", "파란 전기 아크", look("crystal", "bolt", rgb(60, 110, 220), rgb(255, 240, 120), rgb(160, 220, 255)) },
		{ 2, "메아리 코어", "퍼지는 파란 음파 고리", look("atom", "rings", rgb(70, 140, 240), rgb(30, 70, 150), rgb(160, 220, 255)) },
		{ 2, "용암 코어", "갈라진 틈으로 새는 붉은 빛", look("orb", "flame", rgb(80, 60, 70), rgb(255, 110, 40), rgb(255, 180, 80)) },
		{ 3, "울림 수정", "보라 수정 빛", look("crystal", "burst", rgb(170, 110, 255), rgb(90, 40, 170), rgb(240, 210, 255)) },
		{ 3, "폭풍 코어", "보라 소용돌이 번개", look("atom", "bolt", rgb(110, 70, 200), rgb(220, 200, 255), rgb(200, 160, 255)) },
		{ 3, "중력 코어", "기울어진 고리를 두른 보라 구", look("orb", "orbit", rgb(120, 70, 210), rgb(230, 180, 255), rgb(210, 170, 255)) },
		{ 4, "별의 심장", "금빛 박동 파동", look("orb", "ring", rgb(255, 190, 60), rgb(255, 120, 90), rgb(255, 240, 170)) },
		{ 4, "빅뱅 코어", "콤보 5단계에서 터지는 금빛 폭발 고리", look("atom", "burst", rgb(255, 210, 90), rgb(255, 120, 40), rgb(255, 250, 210)) },
	},
}

-- 2) 세트: { 레어도, 세트 Id, 세트 이름, 빛(설명 앞말), 몸통 색, 장식 색, 빛 색, 빛 무늬 }
local SERIES: { { any } } = {
	-- 일반 12
	{ 1, "scrap", "고철", "덜컹거리는 고철빛", rgb(128, 132, 140), rgb(92, 84, 76), rgb(255, 160, 90), "dots" },
	{ 1, "wood", "나무", "나뭇결 무늬의 따뜻한", rgb(170, 118, 72), rgb(110, 76, 46), rgb(255, 214, 150), "none" },
	{ 1, "copper", "구리", "반짝이는 구리빛", rgb(196, 116, 70), rgb(120, 70, 40), rgb(255, 190, 130), "ring" },
	{ 1, "rust", "녹슨", "녹이 번진 주황빛", rgb(160, 90, 60), rgb(90, 60, 50), rgb(255, 140, 70), "dots" },
	{ 1, "toy", "장난감", "알록달록한 장난감", rgb(236, 72, 72), rgb(60, 120, 230), rgb(255, 230, 80), "dots" },
	{ 1, "paper", "종이", "종이접기 모양의 하얀", rgb(232, 228, 214), rgb(170, 160, 140), rgb(255, 255, 240), "grid" },
	{ 1, "brick", "벽돌", "벽돌 무늬의 붉은", rgb(178, 86, 62), rgb(220, 200, 180), rgb(255, 170, 120), "grid" },
	{ 1, "rubber", "고무", "말랑한 노란", rgb(60, 60, 66), rgb(240, 200, 40), rgb(255, 230, 120), "ring" },
	{ 1, "desert", "사막", "모래바람이 섞인", rgb(214, 180, 120), rgb(170, 120, 70), rgb(255, 220, 150), "flame" },
	{ 1, "jungle", "정글", "덩굴이 감긴 초록", rgb(70, 140, 70), rgb(110, 80, 50), rgb(170, 255, 140), "wings" },
	{ 1, "choco", "초콜릿", "달콤한 초콜릿빛", rgb(110, 66, 46), rgb(240, 150, 180), rgb(255, 200, 220), "dots" },
	{ 1, "jelly", "젤리", "말랑말랑한 젤리빛", rgb(120, 220, 180), rgb(255, 140, 200), rgb(210, 255, 240), "ring" },
	-- 희귀 12
	{ 2, "ocean", "바다", "파도치는 푸른", rgb(40, 110, 200), rgb(230, 240, 255), rgb(110, 210, 255), "rings" },
	{ 2, "ice", "얼음", "얼어붙은 하늘색", rgb(170, 220, 255), rgb(90, 150, 220), rgb(230, 250, 255), "burst" },
	{ 2, "thunder", "천둥", "번쩍이는 노란", rgb(60, 70, 140), rgb(255, 220, 60), rgb(255, 245, 150), "bolt" },
	{ 2, "neon", "네온", "형광 분홍", rgb(40, 30, 60), rgb(255, 60, 200), rgb(80, 255, 255), "grid" },
	{ 2, "chrome", "크롬", "거울처럼 매끈한 은빛", rgb(200, 210, 225), rgb(90, 110, 140), rgb(180, 230, 255), "ring" },
	{ 2, "cyber", "사이버", "초록 코드가 흐르는", rgb(20, 40, 30), rgb(60, 255, 120), rgb(160, 255, 190), "grid" },
	{ 2, "coral", "산호", "산호빛 분홍", rgb(255, 120, 110), rgb(255, 210, 190), rgb(255, 180, 170), "dots" },
	{ 2, "sapphire", "사파이어", "깊은 푸른 보석빛", rgb(30, 70, 190), rgb(150, 190, 255), rgb(120, 170, 255), "burst" },
	{ 2, "emerald", "에메랄드", "초록 보석빛", rgb(20, 150, 100), rgb(170, 255, 210), rgb(110, 255, 190), "burst" },
	{ 2, "pirate", "해적", "해골 깃발의 검붉은", rgb(40, 36, 40), rgb(200, 40, 50), rgb(255, 210, 120), "wings" },
	{ 2, "robot", "로봇", "빨간 눈이 깜빡이는", rgb(150, 160, 175), rgb(70, 76, 90), rgb(255, 70, 70), "grid" },
	{ 2, "blossom", "벚꽃", "꽃잎이 흩날리는", rgb(255, 190, 210), rgb(255, 255, 255), rgb(255, 150, 190), "dots" },
	-- 영웅 9
	{ 3, "nebula", "성운", "소용돌이치는 성운빛", rgb(110, 60, 190), rgb(255, 120, 200), rgb(200, 160, 255), "orbit" },
	{ 3, "dimension", "차원", "공간이 일그러지는 보라", rgb(50, 20, 90), rgb(180, 90, 255), rgb(230, 180, 255), "rings" },
	{ 3, "ghost", "유령", "으스스한 청록", rgb(180, 240, 220), rgb(60, 90, 90), rgb(150, 255, 220), "wings" },
	{ 3, "arcane", "마법", "룬 문자가 떠다니는", rgb(90, 40, 160), rgb(255, 210, 90), rgb(220, 170, 255), "burst" },
	{ 3, "blackhole", "블랙홀", "빛을 삼키는 검은", rgb(20, 16, 30), rgb(160, 90, 255), rgb(255, 150, 60), "orbit" },
	{ 3, "hologram", "홀로그램", "깜빡이는 무지갯빛", rgb(80, 220, 255), rgb(255, 100, 230), rgb(180, 255, 255), "grid" },
	{ 3, "volcano", "화산", "용솟음치는 붉은", rgb(70, 30, 30), rgb(255, 90, 30), rgb(255, 170, 60), "flame" },
	{ 3, "abyss", "심해", "깊은 바다에서 빛나는", rgb(20, 40, 90), rgb(40, 220, 200), rgb(120, 255, 240), "dots" },
	{ 3, "steampunk", "스팀펑크", "황동 톱니와 증기의", rgb(190, 140, 60), rgb(110, 70, 40), rgb(255, 230, 170), "ring" },
	-- 전설 6
	{ 4, "sun", "태양", "이글거리는 태양빛", rgb(255, 180, 40), rgb(255, 90, 30), rgb(255, 245, 170), "burst" },
	{ 4, "constellation", "별자리", "별과 별을 잇는 금빛", rgb(30, 30, 80), rgb(255, 210, 90), rgb(255, 240, 180), "dots" },
	{ 4, "dragonking", "용왕", "비늘이 번쩍이는 금빛", rgb(200, 40, 40), rgb(255, 200, 60), rgb(255, 220, 120), "wings" },
	{ 4, "eternal", "영원", "끝없이 도는 흰 금빛", rgb(245, 240, 225), rgb(220, 170, 60), rgb(255, 250, 220), "rings" },
	{ 4, "rainbow", "무지개", "일곱 빛깔", rgb(255, 90, 120), rgb(90, 200, 255), rgb(255, 240, 120), "burst" },
	{ 4, "comet", "혜성", "긴 꼬리를 끄는 푸른 흰빛", rgb(200, 230, 255), rgb(80, 140, 255), rgb(240, 250, 255), "flame" },
}

local list: { Variant } = {}
local byId: { [string]: Variant } = {}
local byType: { [string]: { Variant } } = {}
local byTypeRarity: { [string]: { [number]: { Variant } } } = {}

local function add(variant: Variant)
	table.insert(list, variant)
	byId[variant.Id] = variant
	table.insert(byType[variant.Type], variant)
	table.insert(byTypeRarity[variant.Type][variant.Rarity], variant)
end

for typeIndex, partType in ipairs(Config.Parts.Types) do
	local typeId = partType.Id
	byType[typeId] = {}
	byTypeRarity[typeId] = { {}, {}, {}, {} }
	local counts = { 0, 0, 0, 0 }
	for _, row in ipairs(RAW[typeId] or {}) do
		local rarity = row[1] :: number
		counts[rarity] += 1
		add({
			Id = string.format("%s_%s%d", typeId, Catalog.RarityLetters[rarity], counts[rarity]),
			Type = typeId,
			Rarity = rarity,
			Name = row[2] :: string,
			Desc = row[3] :: string,
			Look = row[4] :: Look,
			Set = nil,
		})
	end
	local words = TYPE_WORDS[typeId]
	if words then
		for seriesIndex, row in ipairs(SERIES) do
			local body = words.Bodies[(seriesIndex + typeIndex) % #words.Bodies + 1]
			add({
				Id = typeId .. "_" .. (row[2] :: string),
				Type = typeId,
				Rarity = row[1] :: number,
				Name = (row[3] :: string) .. " " .. words.Noun,
				Desc = (row[4] :: string) .. " " .. words.Effect,
				Look = look(body, row[8] :: string, row[5] :: Color3, row[6] :: Color3, row[7] :: Color3),
				Set = row[3] :: string,
			})
		end
	end
end

-- 그림 정하기: 그 종류·레어도 안에서 차례로 번갈아
for _, partType in ipairs(Config.Parts.Types) do
	for rarity, pool in ipairs(byTypeRarity[partType.Id]) do
		local cycle = SHAPES_BY_RARITY[rarity]
		for index, variant in ipairs(pool) do
			variant.Look.Shape = cycle[(index - 1) % #cycle + 1]
		end
	end
end

-- 부품 하나 (없는 Id 면 nil)
function Catalog.get(id: any): Variant?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- 그 종류의 부품 모두 (따로 지은 부품 → 세트, 레어도 순서는 섞여 있음)
function Catalog.ofType(typeId: string): { Variant }
	return byType[typeId] or {}
end

-- 그 종류·레어도의 부품들
function Catalog.ofRarity(typeId: string, rarity: number): { Variant }
	local found = byTypeRarity[typeId]
	return if found then found[rarity] or {} else {}
end

-- 처음 받는 기본 부품 (그 종류의 첫 일반)
function Catalog.starter(typeId: string): Variant
	return Catalog.ofRarity(typeId, 1)[1]
end

function Catalog.count(): number
	return #list
end

function Catalog.all(): { Variant }
	return list
end

return Catalog
