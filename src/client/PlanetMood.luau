-- 행성마다 다른 분위기 (값은 PlanetMoods.luau).
-- 발사장에 있을 때(1단계 하늘) 이번 판 행성의 분위기를 씌우고, 비행해서 폭풍 구름층(2단계)으로 들어가면
-- 비행 연출의 원래 값으로 천천히 돌립니다. 판이 바뀌거나 디버그로 행성을 바꾸면 새 행성 값으로 천천히 바뀝니다.
-- 하늘빛과 같은 빠르기로 섞으므로 Backdrop 의 하늘(행성의 Sky)과 함께 바뀝니다.
--  · 빛: 햇빛 받는 면과 반대쪽 면의 색(ColorShift), 화면 밝기 보정
--  · 색감: 채도·대비·전체 색 (RoflyMood 색 보정. 번개·위기 때 색은 Backdrop 의 RoflyTint 가 따로 함)
--  · 빛 번짐(Bloom), 햇살 줄기(SunRays)와 해 둘레 눈부심(Atmosphere.Glare), 별 개수, 엔진이 그리는 해·달 보이기
--  · 행성 위: 공기 중에 떠다니는 입자, 빛나는 소품의 불빛, 발사장 불빛 색. Planet.luau 가 행성을 만들 때 부르므로
--    행성과 함께 움직이고, 높이 오르면 소품과 함께 숨습니다.
-- 하늘빛과 안개(시각·밝기·Atmosphere 짙기와 색)는 Planets.luau 의 Sky 를 Backdrop 이 씁니다.
-- 전부 내 화면에서만 바꾸는 것이라 다른 사람에게 영향이 없습니다.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlanetMoods = require(Shared:WaitForChild("PlanetMoods"))
local Route = require(Shared:WaitForChild("Route"))

local State = require(script.Parent:WaitForChild("State"))

local PlanetMood = {}

local W = Config.World
local BLEND_RATE = 0.9 -- 섞는 빠르기 (Backdrop 의 하늘과 같음)

-- 떠다니는 입자가 생기는 곳: 로켓 축을 비운 네모 고리(바깥 반 너비 AIR_REACH, 빈 가운데 반 너비 AIR_HOLE)를
-- 바람개비처럼 네 칸으로 나눔. 칸마다 긴 쪽으로 바람이 불어 로켓 둘레를 돌고, 빈 가운데(선체·선실 카메라 둘레)로는 들어오지 않음.
local AIR_HOLE = W.HullRadius + 44
local AIR_REACH = 210 -- 넓히면 같은 개수로는 성겨짐 (외창 앞·광장 둘레에 몰아 둠)
local AIR_BOXES = {
	{ x0 = -AIR_HOLE, x1 = AIR_REACH, z0 = AIR_HOLE, z1 = AIR_REACH, wind = Vector3.new(1, 0, 0) },
	{ x0 = AIR_HOLE, x1 = AIR_REACH, z0 = -AIR_REACH, z1 = AIR_HOLE, wind = Vector3.new(0, 0, -1) },
	{ x0 = -AIR_REACH, x1 = AIR_HOLE, z0 = -AIR_REACH, z1 = -AIR_HOLE, wind = Vector3.new(-1, 0, 0) },
	{ x0 = -AIR_REACH, x1 = -AIR_HOLE, z0 = -AIR_HOLE, z1 = AIR_REACH, wind = Vector3.new(0, 0, 1) },
}
local AIR_TEXTURES = {
	soft = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
}
local GLOW_SPACING = 30 -- 소품 불빛끼리 이만큼은 떨어뜨림 (한 무더기에 몰리지 않게)

-- 화면에 쓰는 값 가운데 섞는 것 (숫자·색)
type Look = {
	ShiftTop: Color3,
	ShiftBottom: Color3,
	Exposure: number,
	Saturation: number,
	Contrast: number,
	Tint: Color3,
	Bloom: number,
	BloomSize: number,
	BloomThreshold: number,
	Glare: number,
	SunRays: number,
}

local neutral: Look -- 비행 연출의 원래 값 (시작할 때 맵의 값을 읽음)
local neutralSunShown = true
local neutralStars = 3000
local current: Look
local looks: { [string]: Look } = {}
local home = 1 -- 발사장 분위기가 씌워진 정도 (0~1, current 와 같은 빠르기로 섞임)

local grade: ColorCorrectionEffect
local bloom: BloomEffect
local sunRays: SunRaysEffect
local sky: Sky
local atmosphere: Atmosphere? = nil

-- ------------------------------------------------------------ 섞기
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lookOf(mood: PlanetMoods.Mood): Look
	return {
		ShiftTop = mood.ShiftTop,
		ShiftBottom = mood.ShiftBottom,
		Exposure = mood.Exposure,
		Saturation = mood.Saturation,
		Contrast = mood.Contrast,
		Tint = mood.Tint,
		Bloom = mood.Bloom,
		BloomSize = mood.BloomSize,
		BloomThreshold = mood.BloomThreshold,
		Glare = if mood.SunShown then mood.Glare else 0,
		SunRays = if mood.SunShown then mood.SunRays else 0,
	}
end

-- 행성 Id 의 발사장 분위기 (목록에 없는 행성은 원래 값 그대로)
local function homeLook(id: string): Look
	if not PlanetMoods.has(id) then
		return neutral
	end
	local look = looks[id]
	if not look then
		look = lookOf(PlanetMoods.get(id))
		looks[id] = look
	end
	return look
end

local function blend(target: Look, t: number)
	current.ShiftTop = current.ShiftTop:Lerp(target.ShiftTop, t)
	current.ShiftBottom = current.ShiftBottom:Lerp(target.ShiftBottom, t)
	current.Exposure = lerp(current.Exposure, target.Exposure, t)
	current.Saturation = lerp(current.Saturation, target.Saturation, t)
	current.Contrast = lerp(current.Contrast, target.Contrast, t)
	current.Tint = current.Tint:Lerp(target.Tint, t)
	current.Bloom = lerp(current.Bloom, target.Bloom, t)
	current.BloomSize = lerp(current.BloomSize, target.BloomSize, t)
	current.BloomThreshold = lerp(current.BloomThreshold, target.BloomThreshold, t)
	current.Glare = lerp(current.Glare, target.Glare, t)
	current.SunRays = lerp(current.SunRays, target.SunRays, t)
end

-- 별 개수와 엔진 해·달은 섞지 않고 바꿈 (별 개수를 매 프레임 바꾸면 별이 다시 뿌려질 수 있어서, 바뀔 때만 넣음)
local function apply(sunShown: boolean, stars: number)
	Lighting.ColorShift_Top = current.ShiftTop
	Lighting.ColorShift_Bottom = current.ShiftBottom
	Lighting.ExposureCompensation = current.Exposure
	grade.Saturation = current.Saturation
	grade.Contrast = current.Contrast
	grade.TintColor = current.Tint
	bloom.Intensity = current.Bloom
	bloom.Size = current.BloomSize
	bloom.Threshold = current.BloomThreshold
	sunRays.Intensity = current.SunRays
	if sky.StarCount ~= stars then
		sky.StarCount = stars
	end
	if sky.CelestialBodiesShown ~= sunShown then
		sky.CelestialBodiesShown = sunShown
	end
	if atmosphere == nil or atmosphere.Parent ~= Lighting then
		atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	end
	if atmosphere then
		atmosphere.Glare = current.Glare
	end
end

-- ------------------------------------------------------------ 행성 위 (Planet.luau 가 부름)
local function sequence(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, point in ipairs(points) do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

local function addAir(parent: Instance, air: PlanetMoods.Air, index: number)
	local clear = 1 - air.Opacity
	local transparency: NumberSequence
	if air.Twinkle then
		-- 켜졌다 꺼졌다 (입자마다 사는 시간이 달라 서로 어긋나게 깜박임)
		transparency = sequence({
			{ 0, 1 }, { 0.1, clear }, { 0.22, 0.96 }, { 0.34, clear }, { 0.48, 0.92 },
			{ 0.6, clear }, { 0.74, 0.96 }, { 0.86, clear }, { 1, 1 },
		})
	else
		transparency = sequence({ { 0, 1 }, { 0.15, clear }, { 0.8, clear }, { 1, 1 } })
	end
	local size = sequence({ { 0, air.Size * 0.6 }, { 0.4, air.Size }, { 1, air.Size * 0.8 } })
	local speed = math.abs(air.Rise)
	for i, box in ipairs(AIR_BOXES) do
		local part = Instance.new("Part")
		part.Name = "AirBox"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(box.x1 - box.x0, air.High - air.Low, box.z1 - box.z0)
		part.CFrame = CFrame.new((box.x0 + box.x1) / 2, (air.Low + air.High) / 2, (box.z0 + box.z1) / 2)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Air" .. index
		emitter.Texture = AIR_TEXTURES[air.Look] or AIR_TEXTURES.soft
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.EmissionDirection = if air.Rise >= 0 then Enum.NormalId.Top else Enum.NormalId.Bottom
		emitter.Speed = NumberRange.new(speed * 0.7, speed * 1.3)
		emitter.SpreadAngle = Vector2.new(air.Wander, air.Wander)
		-- 바람: 처음엔 멈춰 있다가 바람을 타고 빨라짐 (사는 동안 평균 빠르기 = Swirl)
		emitter.Acceleration = box.wind * (2 * air.Swirl / air.Life)
		emitter.Lifetime = NumberRange.new(air.Life * 0.75, air.Life * 1.25)
		emitter.Rate = air.Count / air.Life / #AIR_BOXES
		emitter.Size = size
		emitter.Transparency = transparency
		emitter.Color = ColorSequence.new(air.Colors[1], air.Colors[#air.Colors])
		emitter.LightEmission = air.Glow
		emitter.LightInfluence = 1 - air.Glow
		emitter.Brightness = 1 + air.Glow
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.LockedToPart = true -- 행성이 멀어지면 입자도 함께 멀어짐
		emitter.Parent = part
		part.Parent = parent
	end
end

type Candidate = { part: BasePart, distance: number }

local function addGlows(parent: Instance, glow: PlanetMoods.Glow)
	local candidates: { Candidate } = {}
	for _, item in ipairs(parent:GetDescendants()) do
		if item:IsA("BasePart") and table.find(glow.Names, item.Name) then
			local p = item.Position
			table.insert(candidates, { part = item, distance = Vector3.new(p.X, 0, p.Z).Magnitude })
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.distance < b.distance
	end)
	local chosen: { BasePart } = {}
	for _, candidate in ipairs(candidates) do
		if #chosen >= glow.Max then
			break
		end
		local apart = true
		for _, other in ipairs(chosen) do
			if (other.Position - candidate.part.Position).Magnitude < GLOW_SPACING then
				apart = false
				break
			end
		end
		if apart then
			table.insert(chosen, candidate.part)
			local light = Instance.new("PointLight")
			light.Name = "PropGlow"
			light.Color = candidate.part.Color
			light.Range = glow.Range
			light.Brightness = glow.Brightness
			light.Shadows = false
			light.Parent = candidate.part
		end
	end
end

-- 행성을 만들 때: 소품 층(props, 쉬는 자세)에 떠다니는 입자와 소품 불빛을 더함
function PlanetMood.decorate(props: Instance, planetId: string)
	local mood = PlanetMoods.get(planetId)
	local air = Instance.new("Folder")
	air.Name = "Air"
	for i, kind in ipairs(mood.Air) do
		addAir(air, kind, i)
	end
	if mood.Glow then
		addGlows(props, mood.Glow)
	end
	air.Parent = props
end

-- 발사장 불빛 색: 가장자리 불빛·관제실 창, 조명탑 등과 그 불빛 (서버가 만든 발사장을 내 화면에서만 칠함)
function PlanetMood.tintPad(pad: Instance, planetId: string)
	local mood = PlanetMoods.get(planetId)
	for _, item in ipairs(pad:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Name == "RimLight" or item.Name == "ControlWindow" then
				item.Color = mood.Pad
			elseif item.Name == "MastLamp" then
				item.Color = mood.Lamp
				local light = item:FindFirstChildOfClass("SpotLight")
				if light then
					light.Color = mood.Lamp
				end
			end
		end
	end
end

-- ------------------------------------------------------------ 매 프레임
local function findOrMake(className: string, name: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = Lighting
	return made
end

function PlanetMood.init()
	-- 맵에 이미 있는 번짐·햇살·하늘은 그 값을 비행 연출의 원래 값으로 쓰고, 없으면 보이지 않는 값으로 새로 만듦
	local hadBloom = Lighting:FindFirstChildOfClass("BloomEffect") ~= nil
	local hadRays = Lighting:FindFirstChildOfClass("SunRaysEffect") ~= nil
	bloom = findOrMake("BloomEffect", "RoflyBloom") :: BloomEffect
	sunRays = findOrMake("SunRaysEffect", "RoflySunRays") :: SunRaysEffect
	sky = findOrMake("Sky", "RoflySkybox") :: Sky
	if not hadBloom then
		bloom.Intensity = 0
	end
	if not hadRays then
		sunRays.Intensity = 0
	end
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "RoflyMood"
	grade.Parent = Lighting
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

	neutralSunShown = sky.CelestialBodiesShown
	neutralStars = sky.StarCount
	neutral = {
		ShiftTop = Lighting.ColorShift_Top,
		ShiftBottom = Lighting.ColorShift_Bottom,
		Exposure = Lighting.ExposureCompensation,
		Saturation = 0,
		Contrast = 0,
		Tint = Color3.new(1, 1, 1),
		Bloom = bloom.Intensity,
		BloomSize = bloom.Size,
		BloomThreshold = bloom.Threshold,
		Glare = if atmosphere then atmosphere.Glare else 0,
		SunRays = sunRays.Intensity,
	}
	-- 처음에는 바로 발사장 분위기 (들어오자마자 천천히 바뀌는 것이 보이지 않게)
	current = table.clone(homeLook(State.text("Planet")))
	home = 1
end

function PlanetMood.update(dt: number)
	local phase = State.phase()
	local id = State.text("Planet")
	-- Backdrop 의 하늘과 같은 기준: 비행·정산 중에는 거리로 정한 스테이지, 그 밖에는 발사장
	local stage = if phase == "Flight" or phase == "Results" then Route.stageIndex(State.flight.km) else 1
	local atHome = stage == 1
	local t = math.min(1, dt * BLEND_RATE)
	blend(if atHome then homeLook(id) else neutral, t)
	home = lerp(home, if atHome then 1 else 0, t)
	local sunShown = neutralSunShown
	local stars = neutralStars
	if home > 0.5 and PlanetMoods.has(id) then
		local mood = PlanetMoods.get(id)
		sunShown = neutralSunShown and mood.SunShown
		stars = mood.Stars
	end
	apply(sunShown, stars)
end

-- 검사용
PlanetMood._internal = {
	airHole = AIR_HOLE,
	airReach = AIR_REACH,
	home = function(): number
		return home
	end,
	neutral = function(): Look
		return neutral
	end,
}

return PlanetMood
