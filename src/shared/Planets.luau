--!strict
-- 발사 행성 종류. 판이 새로 시작할 때마다 서버가 지난 판과 다른 행성을 하나 골라
-- RoundState 의 Planet(행성 Id)·PlanetSeed(배치 씨앗) 속성으로 알립니다.
-- 클라이언트 Planet.luau 가 이 값으로 둥근 행성과 주변 지형지물을 만들고, Backdrop 이 Sky 를 1단계 하늘로 씁니다.
-- 행성을 하나 더 넣으려면 아래 목록에 항목을 하나 더 쓰면 됩니다. (지형지물·소품 종류는 Planet.luau 의 BUILDERS 이름)
-- 다음 판 행성은 정산 때 슬롯(PlanetSlot.luau)으로 뽑습니다: 지금 행성을 뺀 나머지에서 Weight(가중치) 비율대로.
-- 가중치는 임시 값입니다 (6종 합 100: 정글·사막·바다 22, 얼음 16, 용암 12, 수정 6 = 희귀).
-- 슬롯 칸의 그림은 Thumb (Roblox 이미지 에셋, 원본은 저장소 docs/planets/). 비어 있으면 행성 색으로 그린 둥근 그림을 씁니다.

local Planets = {}

-- 하늘: Backdrop 의 하늘 표와 같은 모양
export type Sky = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	Outdoor: Color3,
	Density: number,
	Haze: number,
	Color: Color3,
	Decay: Color3,
	Streak: Color3,
	Clouds: number,
}

-- 소품 한 종류: Kind = 만드는 함수 이름, Count = 개수, Colors = 그 함수가 쓰는 색들
export type Prop = { Kind: string, Count: number, Colors: { Color3 }, Size: number? }

-- 하늘의 천체 (발사대에서 본 방향): Az = 방위(도, 0 = 외창 쪽 +Z, 시계 반대로 +), El = 올려본 각(도), Size = 보이는 반지름(도)
export type Body = { Kind: string, Az: number, El: number, Size: number, Colors: { Color3 } }

export type Planet = {
	Id: string,
	Name: string,
	Ground: { Color3 }, -- 땅 면 색 (낮은 곳 -> 높은 곳)
	GroundMaterial: Enum.Material,
	Sea: Color3, -- 가장 낮은 면(바다·용암 호수·얼음 호수)
	SeaMaterial: Enum.Material,
	SeaNeon: boolean,
	SeaShare: number, -- 행성 꼭짓점 가운데 바다 높이인 비율 (0~1)
	Peak: Color3, -- 가장 높은 면
	Crack: Color3, -- 붕괴 균열 빛
	Bumps: number, -- 땅 높낮이(스터드)
	Landmarks: { Prop }, -- 멀리서도 보이는 큰 지형지물
	Props: { Prop }, -- 발사대 근처 소품
	Bodies: { Body }, -- 하늘의 천체
	Sky: Sky,
	Weight: number, -- 다음 행성 뽑기 가중치 (클수록 잘 나옴)
	Thumb: string, -- 슬롯 썸네일 이미지 ("rbxassetid://숫자", 아직 없으면 "")
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LIST: { Planet } = {
	{
		Id = "lava",
		Name = "용암 행성",
		Weight = 12,
		Thumb = "",
		Ground = { rgb(56, 42, 40), rgb(72, 50, 44), rgb(90, 60, 50) },
		GroundMaterial = Enum.Material.Basalt,
		Sea = rgb(255, 110, 30),
		SeaMaterial = Enum.Material.Neon,
		SeaNeon = true,
		SeaShare = 0.28,
		Peak = rgb(38, 32, 34),
		Crack = rgb(255, 140, 40),
		Bumps = 60,
		Landmarks = {
			{ Kind = "volcano", Count = 6, Colors = { rgb(66, 48, 44), rgb(255, 120, 40) } },
		},
		Props = {
			{ Kind = "spike", Count = 26, Colors = { rgb(34, 28, 40) } },
			{ Kind = "rock", Count = 34, Colors = { rgb(78, 58, 50), rgb(60, 46, 42) } },
			{ Kind = "pool", Count = 12, Colors = { rgb(255, 120, 35) } },
		},
		Bodies = {
			{ Kind = "sun", Az = 0, El = 4, Size = 8, Colors = { rgb(255, 92, 40) } },
			{ Kind = "moon", Az = 215, El = 24, Size = 4, Colors = { rgb(120, 80, 76) } },
		},
		Sky = {
			ClockTime = 18.3, Brightness = 1.3, Ambient = rgb(120, 72, 60), Outdoor = rgb(140, 84, 64),
			Density = 0.24, Haze = 2.2, Color = rgb(255, 130, 80), Decay = rgb(120, 40, 24),
			Streak = rgb(255, 215, 170), Clouds = 0.35,
		},
	},
	{
		Id = "ice",
		Name = "얼음 행성",
		Weight = 16,
		Thumb = "",
		Ground = { rgb(198, 218, 234), rgb(220, 234, 246), rgb(238, 246, 255) },
		GroundMaterial = Enum.Material.Snow,
		Sea = rgb(120, 188, 236),
		SeaMaterial = Enum.Material.Ice,
		SeaNeon = false,
		SeaShare = 0.25,
		Peak = rgb(255, 255, 255),
		Crack = rgb(80, 220, 255),
		Bumps = 70,
		Landmarks = {
			{ Kind = "mountain", Count = 7, Colors = { rgb(140, 160, 182), rgb(250, 252, 255) } },
		},
		Props = {
			{ Kind = "pine", Count = 34, Colors = { rgb(44, 92, 104), rgb(236, 244, 255) } },
			{ Kind = "spike", Count = 26, Colors = { rgb(150, 220, 255) } },
			{ Kind = "rock", Count = 18, Colors = { rgb(150, 162, 178), rgb(226, 236, 248) } },
		},
		Bodies = {
			{ Kind = "moon", Az = 0, El = 5, Size = 7, Colors = { rgb(214, 236, 255) } },
			{ Kind = "aurora", Az = 205, El = 30, Size = 30, Colors = { rgb(90, 255, 190), rgb(120, 170, 255) } },
		},
		Sky = {
			ClockTime = 16.2, Brightness = 2.0, Ambient = rgb(120, 138, 165), Outdoor = rgb(150, 172, 205),
			Density = 0.18, Haze = 1.2, Color = rgb(185, 225, 255), Decay = rgb(90, 140, 200),
			Streak = rgb(230, 245, 255), Clouds = 0.3,
		},
	},
	{
		Id = "jungle",
		Name = "정글 행성",
		Weight = 22,
		Thumb = "",
		Ground = { rgb(58, 128, 60), rgb(76, 148, 66), rgb(96, 166, 72) },
		GroundMaterial = Enum.Material.Grass,
		Sea = rgb(48, 140, 200),
		SeaMaterial = Enum.Material.SmoothPlastic,
		SeaNeon = false,
		SeaShare = 0.3,
		Peak = rgb(112, 122, 102),
		Crack = rgb(190, 255, 80),
		Bumps = 60,
		Landmarks = {
			{ Kind = "giantTree", Count = 6, Colors = { rgb(104, 72, 52), rgb(58, 158, 72), rgb(90, 190, 80) } },
			{ Kind = "mountain", Count = 3, Colors = { rgb(92, 120, 86), rgb(150, 168, 120) } },
		},
		Props = {
			{ Kind = "tree", Count = 44, Colors = { rgb(104, 72, 52), rgb(52, 150, 64), rgb(86, 178, 70) } },
			{ Kind = "mushroom", Count = 14, Colors = { rgb(236, 226, 210), rgb(255, 90, 170), rgb(90, 230, 255) } },
			{ Kind = "bush", Count = 26, Colors = { rgb(46, 128, 56), rgb(70, 160, 64) } },
			{ Kind = "rock", Count = 10, Colors = { rgb(110, 116, 104), rgb(90, 98, 90) } },
		},
		Bodies = {
			{ Kind = "moon", Az = 8, El = 4, Size = 5, Colors = { rgb(255, 172, 210) } },
			{ Kind = "moon", Az = -15, El = 10, Size = 2.5, Colors = { rgb(140, 232, 222) } },
			{ Kind = "moon", Az = 215, El = 28, Size = 4, Colors = { rgb(255, 230, 170) } },
		},
		Sky = {
			ClockTime = 14.5, Brightness = 2.3, Ambient = rgb(100, 125, 105), Outdoor = rgb(120, 155, 125),
			Density = 0.2, Haze = 1.5, Color = rgb(150, 230, 195), Decay = rgb(60, 140, 120),
			Streak = rgb(220, 255, 230), Clouds = 0.5,
		},
	},
	{
		Id = "desert",
		Name = "사막 행성",
		Weight = 22,
		Thumb = "",
		Ground = { rgb(212, 158, 98), rgb(226, 178, 112), rgb(236, 196, 128) },
		GroundMaterial = Enum.Material.Sand,
		Sea = rgb(238, 224, 198),
		SeaMaterial = Enum.Material.SmoothPlastic,
		SeaNeon = false,
		SeaShare = 0.15,
		Peak = rgb(172, 102, 70),
		Crack = rgb(255, 120, 40),
		Bumps = 50,
		Landmarks = {
			{ Kind = "mesa", Count = 8, Colors = { rgb(182, 92, 62), rgb(206, 124, 82), rgb(160, 80, 56) } },
			{ Kind = "arch", Count = 2, Colors = { rgb(190, 104, 70) } },
		},
		Props = {
			{ Kind = "cactus", Count = 34, Colors = { rgb(70, 140, 72) } },
			{ Kind = "rock", Count = 30, Colors = { rgb(192, 122, 82), rgb(168, 104, 70) } },
			{ Kind = "deadTree", Count = 8, Colors = { rgb(120, 90, 66) } },
		},
		Bodies = {
			{ Kind = "ringed", Az = 0, El = 6, Size = 9, Colors = { rgb(240, 190, 140), rgb(255, 232, 196) } },
			{ Kind = "moon", Az = 230, El = 22, Size = 3, Colors = { rgb(245, 240, 230) } },
		},
		Sky = {
			ClockTime = 16.8, Brightness = 2.5, Ambient = rgb(145, 118, 92), Outdoor = rgb(175, 138, 102),
			Density = 0.22, Haze = 2.0, Color = rgb(255, 205, 140), Decay = rgb(170, 100, 60),
			Streak = rgb(255, 235, 195), Clouds = 0.1,
		},
	},
	{
		Id = "crystal",
		Name = "수정 행성",
		Weight = 6,
		Thumb = "",
		Ground = { rgb(68, 48, 98), rgb(86, 60, 118), rgb(104, 74, 138) },
		GroundMaterial = Enum.Material.Slate,
		Sea = rgb(128, 88, 208),
		SeaMaterial = Enum.Material.SmoothPlastic,
		SeaNeon = false,
		SeaShare = 0.2,
		Peak = rgb(150, 122, 190),
		Crack = rgb(255, 80, 220),
		Bumps = 70,
		Landmarks = {
			{ Kind = "spire", Count = 9, Colors = { rgb(255, 90, 200), rgb(90, 220, 255), rgb(170, 110, 255) } },
		},
		Props = {
			{ Kind = "crystal", Count = 42, Colors = { rgb(255, 110, 210), rgb(100, 225, 255), rgb(180, 130, 255) } },
			{ Kind = "mushroom", Count = 14, Colors = { rgb(200, 190, 230), rgb(120, 255, 220), rgb(255, 120, 230) } },
			{ Kind = "rock", Count = 18, Colors = { rgb(82, 62, 112), rgb(66, 50, 92) } },
		},
		Bodies = {
			{ Kind = "nebula", Az = 6, El = 8, Size = 12, Colors = { rgb(255, 90, 200), rgb(90, 140, 255) } },
			{ Kind = "ringed", Az = 205, El = 26, Size = 6, Colors = { rgb(170, 120, 255), rgb(255, 170, 240) } },
		},
		Sky = {
			ClockTime = 20.8, Brightness = 1.1, Ambient = rgb(115, 85, 150), Outdoor = rgb(105, 78, 148),
			Density = 0.16, Haze = 1.0, Color = rgb(185, 120, 255), Decay = rgb(70, 35, 130),
			Streak = rgb(240, 205, 255), Clouds = 0,
		},
	},
	{
		Id = "ocean",
		Name = "바다 행성",
		Weight = 22,
		Thumb = "",
		Ground = { rgb(226, 210, 150), rgb(120, 180, 90), rgb(92, 150, 72) },
		GroundMaterial = Enum.Material.Grass,
		Sea = rgb(40, 130, 210),
		SeaMaterial = Enum.Material.SmoothPlastic,
		SeaNeon = false,
		SeaShare = 0.6,
		Peak = rgb(104, 112, 104),
		Crack = rgb(90, 230, 255),
		Bumps = 45,
		Landmarks = {
			{ Kind = "seaStack", Count = 6, Colors = { rgb(120, 122, 118), rgb(80, 150, 70) } },
			{ Kind = "lighthouse", Count = 1, Colors = { rgb(245, 245, 240), rgb(220, 60, 60), rgb(255, 230, 140) } },
		},
		Props = {
			{ Kind = "palm", Count = 38, Colors = { rgb(140, 104, 70), rgb(60, 170, 70) } },
			{ Kind = "rock", Count = 16, Colors = { rgb(128, 128, 122), rgb(104, 106, 100) } },
			{ Kind = "bush", Count = 14, Colors = { rgb(60, 150, 64), rgb(90, 176, 70) } },
		},
		Bodies = {
			{ Kind = "moon", Az = 0, El = 5, Size = 6, Colors = { rgb(200, 226, 255) } },
			{ Kind = "puffs", Az = 200, El = 14, Size = 22, Colors = { rgb(255, 255, 255) } },
		},
		Sky = {
			ClockTime = 13.5, Brightness = 2.6, Ambient = rgb(110, 132, 152), Outdoor = rgb(132, 162, 192),
			Density = 0.18, Haze = 1.3, Color = rgb(140, 200, 255), Decay = rgb(70, 125, 205),
			Streak = rgb(230, 245, 255), Clouds = 0.7,
		},
	},
}

Planets.List = LIST

function Planets.count(): number
	return #LIST
end

-- Id 로 찾음. 없는 Id 면 첫 행성.
function Planets.get(id: string): Planet
	for _, planet in ipairs(LIST) do
		if planet.Id == id then
			return planet
		end
	end
	return LIST[1]
end

function Planets.has(id: string): boolean
	for _, planet in ipairs(LIST) do
		if planet.Id == id then
			return true
		end
	end
	return false
end

export type Odds = { Planet: Planet, Chance: number }

-- 다음 판 행성 후보와 확률 (0~1): 지금 행성(currentId)을 뺀 나머지, 목록 순서. 확률 = 가중치 / 후보 가중치 합.
-- 슬롯 화면의 확률 표기와 서버의 뽑기가 같은 표를 씁니다.
function Planets.odds(currentId: string): { Odds }
	local choices: { Planet } = {}
	local total = 0
	for _, planet in ipairs(LIST) do
		if planet.Id ~= currentId and planet.Weight > 0 then
			table.insert(choices, planet)
			total += planet.Weight
		end
	end
	local out: { Odds } = {}
	for _, planet in ipairs(choices) do
		table.insert(out, { Planet = planet, Chance = planet.Weight / total })
	end
	return out
end

-- 다음 판 행성: 지금 행성(currentId)과 다른 것 가운데 가중치 비율대로 하나
function Planets.pick(currentId: string, rng: Random): Planet
	local odds = Planets.odds(currentId)
	if #odds == 0 then
		return LIST[1]
	end
	local roll = rng:NextNumber()
	local sum = 0
	for _, entry in ipairs(odds) do
		sum += entry.Chance
		if roll < sum then
			return entry.Planet
		end
	end
	return odds[#odds].Planet
end

-- 목록 순서대로 다음 행성 (디버그 패널에서 하나씩 넘겨 볼 때)
function Planets.after(currentId: string): Planet
	for i, planet in ipairs(LIST) do
		if planet.Id == currentId then
			return LIST[i % #LIST + 1]
		end
	end
	return LIST[1]
end

return Planets
