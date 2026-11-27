--!strict
-- 행성마다 다른 분위기: 빛 색, 색감, 빛 번짐, 햇살, 별, 공기 중에 떠다니는 입자, 빛나는 소품의 불빛, 발사장 불빛 색.
-- 하늘빛과 안개(시각·밝기·Atmosphere 짙기와 색)는 Planets.luau 의 Sky 에 있고, 여기 값은 그 위에 더하는 것입니다.
-- 클라이언트 PlanetMood.luau 가 발사장(1단계 하늘)에서 이 값을 쓰고, 비행해서 폭풍 구름층(2단계)으로 들어가면
-- 비행 연출의 원래 값으로 천천히 돌립니다. 행성 Id 는 Planets.luau 와 같고, 목록에 없는 Id 는 NEUTRAL(아무것도 더하지 않음).

local PlanetMoods = {}

-- 공기 중에 떠다니는 입자 한 종류. 로켓 둘레(선체에서 조금 떨어진 곳부터)에 고르게 생기고, 행성과 함께 움직임.
export type Air = {
	Look: string, -- 입자 그림: "soft"(둥글고 부드러운 덩이: 눈·재·먼지·불티) | "spark"(네 갈래로 반짝이는 별)
	Colors: { Color3 }, -- 생길 때 색, 사라질 때 색
	Size: number, -- 가장 클 때 크기(스터드)
	Count: number, -- 한 번에 떠 있는 개수(대략). 휴대폰을 생각해 행성마다 합계 750 아래로 (큰 덩이는 50 안팎)
	Life: number, -- 한 입자가 떠 있는 시간(초, ±25%)
	Rise: number, -- 위아래 빠르기(스터드/초, + 떠오름 / - 떨어짐)
	Swirl: number, -- 로켓 둘레를 도는 바람의 평균 빠르기(스터드/초)
	Wander: number, -- 처음 움직이는 방향이 위아래에서 흩어지는 정도(도, 180 = 아무 방향)
	Low: number, -- 떠 있는 높이 범위(광장 윗면 y = 0 기준, 스터드). 선실 외창은 약 120~150
	High: number,
	Glow: number, -- 스스로 빛나는 정도(0~1). 1 이면 어두운 곳에서도 밝고 빛 번짐이 생김
	Opacity: number, -- 가장 진할 때 불투명도(0~1)
	Twinkle: boolean?, -- 켜졌다 꺼졌다 깜박임(반딧불이·반짝이)
}

-- 발사대 가까운 빛나는 소품에 불빛을 담. Names = Planet.luau 가 만드는 빛나는 파트 이름, 가까운 것부터 Max 개
export type Glow = { Names: { string }, Range: number, Brightness: number, Max: number }

export type Mood = {
	ShiftTop: Color3, -- 햇빛(달빛)을 받는 면에 더해지는 빛 색 (Lighting.ColorShift_Top)
	ShiftBottom: Color3, -- 반대쪽 면의 빛 색: 땅에서 올라오는 반사광 (Lighting.ColorShift_Bottom)
	Exposure: number, -- 화면 밝기 보정 (Lighting.ExposureCompensation, -3~3)
	Saturation: number, -- 색감: 채도 (-1~1)
	Contrast: number, -- 색감: 대비 (-1~1)
	Tint: Color3, -- 색감: 화면 전체에 곱하는 색
	Bloom: number, -- 빛 번짐 세기 (BloomEffect.Intensity)
	BloomSize: number, -- 빛 번짐 크기
	BloomThreshold: number, -- 이보다 밝은 것만 번짐 (낮을수록 네온·불빛이 많이 번짐)
	SunShown: boolean, -- 엔진이 그리는 해·달을 보일지. 행성 그림의 해·달과 겹치는 노을·밤 행성은 숨김
	Glare: number, -- 해 둘레 눈부심 (Atmosphere.Glare). SunShown 일 때만
	SunRays: number, -- 해를 볼 때 햇살 줄기 (SunRaysEffect.Intensity). SunShown 일 때만
	Stars: number, -- 별 개수 (Sky.StarCount, 0~5000). 밤 하늘에서만 보임
	Pad: Color3, -- 발사장 가장자리 불빛·관제실 창 색
	Lamp: Color3, -- 조명탑 등과 그 불빛 색
	Glow: Glow?,
	Air: { Air },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- 아무것도 더하지 않는 값 (목록에 없는 행성). 발사장 불빛은 서버가 만든 원래 색
local NEUTRAL: Mood = {
	ShiftTop = rgb(0, 0, 0),
	ShiftBottom = rgb(0, 0, 0),
	Exposure = 0,
	Saturation = 0,
	Contrast = 0,
	Tint = rgb(255, 255, 255),
	Bloom = 1,
	BloomSize = 24,
	BloomThreshold = 2,
	SunShown = true,
	Glare = 0,
	SunRays = 0,
	Stars = 3000,
	Pad = rgb(90, 230, 255),
	Lamp = rgb(255, 244, 214),
	Glow = nil,
	Air = {},
}

local MOODS: { [string]: Mood } = {
	-- 용암: 연기 낀 핏빛 노을. 아래(용암)에서 붉은 빛이 올라오고, 불티가 떠오르고 재가 내림. 용암 웅덩이가 둘레를 비춤
	lava = {
		ShiftTop = rgb(190, 90, 40),
		ShiftBottom = rgb(120, 34, 12),
		Exposure = 0,
		Saturation = 0.15,
		Contrast = 0.16,
		Tint = rgb(255, 232, 218),
		Bloom = 1,
		BloomSize = 30,
		BloomThreshold = 1.2,
		SunShown = false,
		Glare = 0,
		SunRays = 0,
		Stars = 0,
		Pad = rgb(255, 120, 50),
		Lamp = rgb(255, 190, 140),
		Glow = { Names = { "Pool" }, Range = 30, Brightness = 3, Max = 8 },
		Air = {
			{ -- 불티
				Look = "soft", Colors = { rgb(255, 210, 110), rgb(255, 80, 30) }, Size = 0.8, Count = 200, Life = 7,
				Rise = 5, Swirl = 3, Wander = 25, Low = 0, High = 200, Glow = 1, Opacity = 1,
			},
			{ -- 재
				Look = "soft", Colors = { rgb(120, 108, 106), rgb(70, 64, 64) }, Size = 1.1, Count = 200, Life = 9,
				Rise = -3, Swirl = 4, Wander = 30, Low = 20, High = 240, Glow = 0, Opacity = 0.7,
			},
		},
	},
	-- 얼음: 해 진 뒤 푸른 하늘, 별과 오로라. 눈이 내리고 공기 중 얼음 알갱이가 반짝임
	ice = {
		ShiftTop = rgb(90, 130, 200),
		ShiftBottom = rgb(30, 60, 110),
		Exposure = 0.25,
		Saturation = -0.05,
		Contrast = 0.1,
		Tint = rgb(222, 238, 255),
		Bloom = 0.7,
		BloomSize = 26,
		BloomThreshold = 1.4,
		SunShown = false,
		Glare = 0,
		SunRays = 0,
		Stars = 2500,
		Pad = rgb(110, 220, 255),
		Lamp = rgb(210, 235, 255),
		Glow = nil,
		Air = {
			{ -- 눈
				Look = "soft", Colors = { rgb(255, 255, 255), rgb(225, 240, 255) }, Size = 1.4, Count = 640, Life = 10,
				Rise = -5, Swirl = 3, Wander = 15, Low = 0, High = 240, Glow = 0.2, Opacity = 0.9,
			},
			{ -- 반짝이는 얼음 알갱이
				Look = "spark", Colors = { rgb(225, 248, 255), rgb(160, 220, 255) }, Size = 0.6, Count = 80, Life = 4,
				Rise = -0.5, Swirl = 2, Wander = 180, Low = 0, High = 160, Glow = 1, Opacity = 0.9, Twinkle = true,
			},
		},
	},
	-- 정글: 습한 황금빛 오후. 초록 반사광, 짙은 색감, 반딧불이와 꽃가루. 빛나는 버섯이 둘레를 비춤
	jungle = {
		ShiftTop = rgb(190, 150, 70),
		ShiftBottom = rgb(30, 80, 35),
		Exposure = 0.05,
		Saturation = 0.22,
		Contrast = 0.08,
		Tint = rgb(238, 255, 226),
		Bloom = 0.8,
		BloomSize = 28,
		BloomThreshold = 1.5,
		SunShown = true,
		Glare = 0.4,
		SunRays = 0.1,
		Stars = 0,
		Pad = rgb(170, 255, 110),
		Lamp = rgb(255, 230, 160),
		Glow = { Names = { "Cap" }, Range = 20, Brightness = 2, Max = 8 },
		Air = {
			{ -- 반딧불이
				Look = "soft", Colors = { rgb(225, 255, 120), rgb(160, 255, 90) }, Size = 0.9, Count = 120, Life = 8,
				Rise = 0.4, Swirl = 1, Wander = 180, Low = 2, High = 70, Glow = 1, Opacity = 1, Twinkle = true,
			},
			{ -- 꽃가루
				Look = "soft", Colors = { rgb(255, 250, 200), rgb(230, 255, 190) }, Size = 0.5, Count = 240, Life = 10,
				Rise = 1, Swirl = 2, Wander = 60, Low = 0, High = 220, Glow = 0.4, Opacity = 0.7,
			},
		},
	},
	-- 사막: 뜨거운 한낮. 눈부신 해와 햇살, 바랜 색에 센 대비, 로켓 둘레를 도는 모래바람
	desert = {
		ShiftTop = rgb(200, 160, 100),
		ShiftBottom = rgb(120, 70, 40),
		Exposure = 0.15,
		Saturation = -0.1,
		Contrast = 0.22,
		Tint = rgb(255, 242, 220),
		Bloom = 0.5,
		BloomSize = 40,
		BloomThreshold = 1.6,
		SunShown = true,
		Glare = 0.8,
		SunRays = 0.16,
		Stars = 0,
		Pad = rgb(255, 180, 70),
		Lamp = rgb(255, 240, 210),
		Glow = nil,
		Air = {
			{ -- 모래 먼지 구름
				Look = "soft", Colors = { rgb(235, 200, 150), rgb(215, 170, 120) }, Size = 16, Count = 50, Life = 7,
				Rise = 0.5, Swirl = 14, Wander = 15, Low = 0, High = 90, Glow = 0, Opacity = 0.22,
			},
			{ -- 날리는 모래
				Look = "soft", Colors = { rgb(240, 210, 160), rgb(220, 180, 130) }, Size = 0.8, Count = 220, Life = 4,
				Rise = 0.3, Swirl = 22, Wander = 10, Low = 0, High = 140, Glow = 0, Opacity = 0.6,
			},
		},
	},
	-- 수정: 성운이 뜬 보랏빛 밤. 진한 색감과 센 빛 번짐, 떠오르는 분홍·하늘색 반짝이. 수정이 둘레를 비춤
	crystal = {
		ShiftTop = rgb(150, 90, 210),
		ShiftBottom = rgb(70, 30, 120),
		Exposure = 0.15,
		Saturation = 0.25,
		Contrast = 0.12,
		Tint = rgb(246, 230, 255),
		Bloom = 1.2,
		BloomSize = 36,
		BloomThreshold = 1.1,
		SunShown = false,
		Glare = 0,
		SunRays = 0,
		Stars = 3000,
		Pad = rgb(255, 90, 220),
		Lamp = rgb(230, 200, 255),
		Glow = { Names = { "Crystal", "Cap" }, Range = 24, Brightness = 2.5, Max = 10 },
		Air = {
			{ -- 떠오르는 반짝이
				Look = "spark", Colors = { rgb(255, 140, 230), rgb(130, 220, 255) }, Size = 0.8, Count = 220, Life = 7,
				Rise = 1.5, Swirl = 2, Wander = 50, Low = 0, High = 220, Glow = 1, Opacity = 1, Twinkle = true,
			},
			{ -- 크고 느린 빛
				Look = "spark", Colors = { rgb(200, 160, 255), rgb(255, 200, 250) }, Size = 1.6, Count = 40, Life = 6,
				Rise = 0.6, Swirl = 1, Wander = 180, Low = 10, High = 160, Glow = 1, Opacity = 0.8, Twinkle = true,
			},
		},
	},
	-- 바다: 맑은 한낮. 바다에서 올라오는 푸른 반사광, 낮게 깔린 바다 안개와 반짝이는 물보라
	ocean = {
		ShiftTop = rgb(110, 120, 110),
		ShiftBottom = rgb(20, 90, 120),
		Exposure = 0.1,
		Saturation = 0.2,
		Contrast = 0.1,
		Tint = rgb(232, 248, 255),
		Bloom = 0.45,
		BloomSize = 28,
		BloomThreshold = 1.7,
		SunShown = true,
		Glare = 0.5,
		SunRays = 0.08,
		Stars = 0,
		Pad = rgb(110, 240, 230),
		Lamp = rgb(255, 250, 235),
		Glow = nil,
		Air = {
			{ -- 바다 안개
				Look = "soft", Colors = { rgb(255, 255, 255), rgb(220, 240, 255) }, Size = 26, Count = 40, Life = 10,
				Rise = 0.3, Swirl = 5, Wander = 20, Low = 0, High = 30, Glow = 0, Opacity = 0.16,
			},
			{ -- 물보라 반짝임
				Look = "spark", Colors = { rgb(240, 255, 255), rgb(180, 235, 255) }, Size = 0.5, Count = 140, Life = 5,
				Rise = 0.8, Swirl = 6, Wander = 60, Low = 0, High = 150, Glow = 0.8, Opacity = 0.8, Twinkle = true,
			},
		},
	},
}

PlanetMoods.Neutral = NEUTRAL

-- 행성 Id 의 분위기. 목록에 없으면 NEUTRAL
function PlanetMoods.get(id: string): Mood
	return MOODS[id] or NEUTRAL
end

function PlanetMoods.has(id: string): boolean
	return MOODS[id] ~= nil
end

return PlanetMoods
