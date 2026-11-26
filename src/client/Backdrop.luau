-- 배경 연출. 로켓은 제자리에 있고 배경이 움직여서 날아가는 것처럼 보입니다.
--  · 발사장: 고도만큼 아래로 내려가다가, 멀어지면 작아지며 사라짐
--  · 충격파: 아래에서 올라오는 빛나는 판. 도달 예상 시간이 줄수록 가까이 옴
--  · 속도선: 속도가 빠를수록 빠르게 아래로 흐르는 빛줄기 (발사 전에는 천천히 떠오르는 불티)
--  · 하늘: 스테이지마다 빛과 안개 색이 바뀜, 폭풍 구름층에서는 번개
--  · 위기: 경보등이 깜박이고 화면이 붉어짐
-- 전부 내 화면에서만 바꾸는 것이라 다른 사람에게 영향이 없습니다.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Route = require(Shared:WaitForChild("Route"))

local State = require(script.Parent:WaitForChild("State"))

local Backdrop = {}

local W = Config.World
local random = Random.new()

-- 이 깊이까지는 실제 높이대로 내려가고, 그 뒤로는 작아짐 (너무 아래로 내려간 파트는 엔진이 지우기 때문)
local PAD_DROP_LIMIT = 400
local PAD_MIN_SCALE = 0.02

-- 속도선은 두 무리: 외창 너머로 보이는 앞쪽 무리(촘촘함)와 로켓을 빙 두른 무리(바깥 시점용)
local FRONT_STREAKS = 44
local AROUND_STREAKS = 46
local FRONT_HALF_ANGLE = math.rad(27) -- 선실 카메라에서 외창으로 보이는 범위
local FRONT_BOTTOM = 30
local FRONT_TOP = 250
local STREAK_TOP = 380
local STREAK_BOTTOM = -160
local CLOUD_COUNT = 9

type Sky = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	Outdoor: Color3,
	Density: number,
	Haze: number,
	Color: Color3,
	Decay: Color3,
	Streak: Color3,
	Clouds: number, -- 구름이 보이는 정도 (0~1)
}

-- 스테이지별 하늘. 5번째부터는 우주.
-- Density(안개 짙기)가 높으면 속도선과 충격파가 흐려지므로 너무 올리지 않습니다.
local SKIES: { Sky } = {
	{ -- 붕괴하는 고향 행성: 노을빛 먼지
		ClockTime = 17.6, Brightness = 2, Ambient = Color3.fromRGB(96, 92, 104), Outdoor = Color3.fromRGB(128, 116, 112),
		Density = 0.3, Haze = 2.2, Color = Color3.fromRGB(230, 150, 110), Decay = Color3.fromRGB(120, 60, 40),
		Streak = Color3.fromRGB(255, 240, 205), Clouds = 0.25,
	},
	{ -- 폭풍 구름층: 어둡고 푸른 구름
		ClockTime = 18.4, Brightness = 0.9, Ambient = Color3.fromRGB(58, 62, 78), Outdoor = Color3.fromRGB(60, 64, 80),
		Density = 0.38, Haze = 2.8, Color = Color3.fromRGB(90, 96, 116), Decay = Color3.fromRGB(40, 44, 60),
		Streak = Color3.fromRGB(205, 225, 255), Clouds = 1,
	},
	{ -- 화산재 하늘: 붉은 재
		ClockTime = 18.7, Brightness = 1.1, Ambient = Color3.fromRGB(80, 56, 52), Outdoor = Color3.fromRGB(96, 64, 56),
		Density = 0.34, Haze = 2.6, Color = Color3.fromRGB(150, 80, 60), Decay = Color3.fromRGB(70, 30, 24),
		Streak = Color3.fromRGB(255, 205, 150), Clouds = 0.7,
	},
	{ -- 오로라 하늘
		ClockTime = 21, Brightness = 0.8, Ambient = Color3.fromRGB(50, 70, 84), Outdoor = Color3.fromRGB(40, 70, 80),
		Density = 0.2, Haze = 0.6, Color = Color3.fromRGB(70, 160, 150), Decay = Color3.fromRGB(30, 60, 90),
		Streak = Color3.fromRGB(200, 255, 230), Clouds = 0,
	},
	{ -- 우주
		ClockTime = 0, Brightness = 0.6, Ambient = Color3.fromRGB(46, 48, 66), Outdoor = Color3.fromRGB(30, 32, 48),
		Density = 0.02, Haze = 0, Color = Color3.fromRGB(20, 22, 40), Decay = Color3.fromRGB(10, 10, 20),
		Streak = Color3.fromRGB(215, 235, 255), Clouds = 0,
	},
}

local container: Folder
local pad: Model? = nil
local padHome: CFrame = CFrame.new()
local padMoved = false
local padHidden = false

local wave: Part
local waveY = -440
local flame: Part
local flameLight: PointLight

type Streak = { part: Part, radius: number, angle: number, y: number, speedScale: number, front: boolean, width: number }
local streaks: { Streak } = {}
type Cloud = { part: Part, radius: number, angle: number, y: number, size: number }
local clouds: { Cloud } = {}

local atmosphere: Atmosphere
local correction: ColorCorrectionEffect
local sky: Sky = table.clone(SKIES[1])
local boostUntil = 0
local nextLightning = 0
local lightningUntil = 0
local caughtAt = 0
local alarmParts: { BasePart } = {}
local alarmOn = false
local lamps: { PointLight } = {}

-- ------------------------------------------------------------ 만들기
local function localPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildWave()
	wave = localPart("Shockwave", container)
	wave.Shape = Enum.PartType.Cylinder
	wave.Material = Enum.Material.Neon
	wave.Color = Color3.fromRGB(255, 96, 40)
	wave.Transparency = 1
	wave.Size = Vector3.new(6, 2040, 2040)
	wave.CFrame = CFrame.new(0, waveY, 0) * CFrame.Angles(0, 0, math.rad(90))
end

local function buildFlame()
	flame = localPart("EngineFlame", container)
	flame.Shape = Enum.PartType.Cylinder
	flame.Material = Enum.Material.Neon
	flame.Color = Color3.fromRGB(255, 190, 90)
	flame.Transparency = 1
	flame.Size = Vector3.new(60, 26, 26)
	flame.CFrame = CFrame.new(0, W.MountHeight - 26, 0) * CFrame.Angles(0, 0, math.rad(90))
	flameLight = Instance.new("PointLight")
	flameLight.Color = Color3.fromRGB(255, 170, 90)
	flameLight.Range = 60
	flameLight.Brightness = 0
	flameLight.Shadows = false
	flameLight.Parent = flame
end

local function streakAngle(front: boolean): number
	if front then
		return (random:NextNumber() * 2 - 1) * FRONT_HALF_ANGLE
	end
	return random:NextNumber() * math.pi * 2
end

local function buildStreaks()
	for i = 1, FRONT_STREAKS + AROUND_STREAKS do
		local front = i <= FRONT_STREAKS
		local part = localPart("Streak", container)
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new(0.6, 4, 0.6)
		local bottom = if front then FRONT_BOTTOM else STREAK_BOTTOM
		local top = if front then FRONT_TOP else STREAK_TOP
		local streak: Streak = {
			part = part,
			radius = if front then 60 + random:NextNumber() * 170 else 48 + random:NextNumber() * 210,
			angle = streakAngle(front),
			y = bottom + random:NextNumber() * (top - bottom),
			speedScale = 0.7 + random:NextNumber() * 0.6,
			front = front,
			width = if front then 0.9 else 0.6,
		}
		streaks[i] = streak
	end
	for i = 1, CLOUD_COUNT do
		local part = localPart("Cloud", container)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 1
		local size = 90 + random:NextNumber() * 110
		part.Size = Vector3.new(size, size, size)
		local cloud: Cloud = {
			part = part,
			radius = 190 + random:NextNumber() * 260,
			angle = random:NextNumber() * math.pi * 2,
			y = STREAK_BOTTOM + random:NextNumber() * (STREAK_TOP - STREAK_BOTTOM),
			size = size,
		}
		clouds[i] = cloud
	end
end

local function findRocketParts()
	local rofly = Workspace:WaitForChild("Rofly")
	local foundPad = rofly:WaitForChild("Pad")
	if foundPad:IsA("Model") then
		pad = foundPad
		padHome = foundPad:GetPivot()
	end
	local rocket = rofly:WaitForChild("Rocket")
	for _, item in ipairs(rocket:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "AlarmLight" then
			table.insert(alarmParts, item)
		elseif item:IsA("BasePart") and item.Name == "Lamp" then
			local light = item:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(lamps, light)
			end
		end
	end
end

-- ------------------------------------------------------------ 발사장
local function setPadHidden(hidden: boolean)
	if padHidden == hidden or not pad then
		return
	end
	padHidden = hidden
	for _, item in ipairs(pad:GetDescendants()) do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function resetPad()
	if not pad or not padMoved then
		return
	end
	padMoved = false
	pad:ScaleTo(1)
	pad:PivotTo(padHome)
	setPadHidden(false)
end

local function movePad(altitudeStuds: number)
	if not pad then
		return
	end
	padMoved = true
	if altitudeStuds <= PAD_DROP_LIMIT then
		setPadHidden(false)
		if pad:GetScale() ~= 1 then
			pad:ScaleTo(1)
		end
		pad:PivotTo(padHome * CFrame.new(0, -altitudeStuds, 0))
		return
	end
	local scale = PAD_DROP_LIMIT / altitudeStuds
	if scale < PAD_MIN_SCALE then
		setPadHidden(true)
		return
	end
	setPadHidden(false)
	pad:ScaleTo(scale)
	pad:PivotTo(padHome * CFrame.new(0, -PAD_DROP_LIMIT, 0))
end

-- ------------------------------------------------------------ 하늘
local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function blendSky(target: Sky, t: number)
	sky.ClockTime = lerpNumber(sky.ClockTime, target.ClockTime, t)
	sky.Brightness = lerpNumber(sky.Brightness, target.Brightness, t)
	sky.Ambient = sky.Ambient:Lerp(target.Ambient, t)
	sky.Outdoor = sky.Outdoor:Lerp(target.Outdoor, t)
	sky.Density = lerpNumber(sky.Density, target.Density, t)
	sky.Haze = lerpNumber(sky.Haze, target.Haze, t)
	sky.Color = sky.Color:Lerp(target.Color, t)
	sky.Decay = sky.Decay:Lerp(target.Decay, t)
	sky.Streak = sky.Streak:Lerp(target.Streak, t)
	sky.Clouds = lerpNumber(sky.Clouds, target.Clouds, t)
end

local function applySky(flashBoost: number, crisisPulse: number)
	Lighting.ClockTime = sky.ClockTime
	Lighting.Brightness = sky.Brightness + flashBoost * 3
	Lighting.Ambient = sky.Ambient
	Lighting.OutdoorAmbient = sky.Outdoor
	atmosphere.Density = sky.Density
	atmosphere.Haze = sky.Haze
	atmosphere.Color = sky.Color
	atmosphere.Decay = sky.Decay
	correction.Brightness = flashBoost * 0.25
	correction.TintColor = Color3.new(1, 1 - 0.3 * crisisPulse, 1 - 0.34 * crisisPulse)
end

local function setAlarm(on: boolean)
	if alarmOn == on then
		return
	end
	alarmOn = on
	for _, part in ipairs(alarmParts) do
		part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = if on then Color3.fromRGB(255, 50, 40) else Color3.fromRGB(90, 20, 20)
	end
	for _, light in ipairs(lamps) do
		light.Color = if on then Color3.fromRGB(255, 120, 110) else Color3.fromRGB(225, 232, 255)
	end
end

-- ------------------------------------------------------------ 매 프레임
function Backdrop.init()
	container = Instance.new("Folder")
	container.Name = "RoflyBackdrop"
	container.Parent = Workspace

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Glare = 0
	atmosphere.Offset = 0.2
	correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "RoflyTint"
	correction.Parent = Lighting
	-- 기본 맵에 들어 있는 흐림 효과는 선실 화면을 뿌옇게 만들어서 끔
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("DepthOfFieldEffect") then
			effect.Enabled = false
		end
	end

	buildWave()
	buildFlame()
	buildStreaks()
	task.spawn(findRocketParts)

	State.on("MissionFx", function(rate: number)
		if rate >= Config.Mission.ComboRule then
			boostUntil = os.clock() + 0.9
		end
	end)
	State.on("FlightEnd", function(info: any)
		if type(info) == "table" and not info.escaped then
			caughtAt = os.clock()
		end
	end)
	State.on("Phase", function(phase: string)
		if phase == "Join" or phase == "Build" then
			caughtAt = 0
		end
	end)
end

function Backdrop.update(dt: number)
	local phase = State.phase()
	local clock = os.clock()
	local flying = phase == "Flight"
	local f = State.flight
	local crisis = flying and State.flag("Crisis")

	-- 발사장
	if flying or (phase == "Results" and padMoved) then
		movePad(f.km * 1000 * W.StudsPerMeter)
	else
		resetPad()
	end

	-- 하늘
	local stage = if flying or phase == "Results" then math.min(Route.stageIndex(f.km), #SKIES) else 1
	blendSky(SKIES[stage], math.min(1, dt * 0.9))
	local flashBoost = 0
	if flying and stage == 2 then
		if clock >= nextLightning then
			nextLightning = clock + 2.5 + random:NextNumber() * 4
			lightningUntil = clock + 0.14
			State.emit("Sound", "Thunder")
		end
		if clock < lightningUntil then
			flashBoost = 1
		end
	end
	local crisisPulse = if crisis then 0.5 + 0.5 * math.sin(clock * 9) else 0
	applySky(flashBoost, crisisPulse)
	setAlarm(crisis and math.floor(clock * 4) % 2 == 0)

	-- 속도선
	local speedStuds: number
	local length: number
	if flying then
		local metersPerSecond = f.speed * 1000
		speedStuds = 60 + 140 * math.log10(1 + metersPerSecond / 5)
		if clock < boostUntil then
			speedStuds *= 1.7
		end
		if State.number("RescueUntil") > f.t then
			speedStuds *= 1.8
		end
		length = math.clamp(speedStuds * 0.09, 6, 44)
	else
		-- 발사 전: 천천히 떠오르는 불티
		speedStuds = -9
		length = 1.6
	end
	local span = STREAK_TOP - STREAK_BOTTOM
	for _, streak in ipairs(streaks) do
		local bottom = if streak.front then FRONT_BOTTOM else STREAK_BOTTOM
		local top = if streak.front then FRONT_TOP else STREAK_TOP
		local y = streak.y - speedStuds * streak.speedScale * dt
		if y < bottom then
			y += top - bottom
			streak.angle = streakAngle(streak.front)
		elseif y > top then
			y -= top - bottom
			streak.angle = streakAngle(streak.front)
		end
		streak.y = y
		local part = streak.part
		part.Size = Vector3.new(streak.width, length, streak.width)
		part.Color = sky.Streak
		part.CFrame = CFrame.new(math.sin(streak.angle) * streak.radius, y, math.cos(streak.angle) * streak.radius)
	end
	for _, cloud in ipairs(clouds) do
		local visible = if flying then sky.Clouds else 0
		local part = cloud.part
		if visible <= 0.02 then
			part.Transparency = 1
		else
			local y = cloud.y - speedStuds * 0.45 * dt
			if y < STREAK_BOTTOM - 100 then
				y += span + 200
				cloud.angle = random:NextNumber() * math.pi * 2
			end
			cloud.y = y
			part.Transparency = 1 - 0.5 * visible
			part.Color = sky.Color:Lerp(Color3.new(0, 0, 0), 0.35)
			part.CFrame = CFrame.new(math.sin(cloud.angle) * cloud.radius, y, math.cos(cloud.angle) * cloud.radius)
		end
	end

	-- 엔진 불꽃
	if flying then
		local flicker = 0.85 + 0.3 * math.noise(clock * 14, 3.1)
		local flameLength = 70 * flicker
		flame.Transparency = 0.15
		flame.Size = Vector3.new(flameLength, 24, 24)
		flame.CFrame = CFrame.new(0, W.MountHeight + 4 - flameLength / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		flameLight.Brightness = 3 * flicker
	else
		flame.Transparency = 1
		flameLight.Brightness = 0
	end

	-- 충격파: 도달 예상 시간이 짧을수록 선실 바닥 가까이 올라옴
	local targetY = -440
	local waveVisible = false
	if flying then
		waveVisible = true
		local eta = math.clamp(State.number("Eta"), 0, Config.Crisis.EtaLimit)
		local below = if eta <= 10 then eta * 23.4 else 234 + (eta - 10) * 16.3
		targetY = math.max(W.CabinFloorY - below, -440)
	elseif phase == "Results" and caughtAt > 0 then
		-- 따라잡힘: 충격파가 선실을 덮고 지나감
		waveVisible = true
		targetY = W.CabinCeilY + 60
	end
	if waveVisible then
		local rate = if phase == "Results" then 2.2 else 3
		waveY += (targetY - waveY) * math.min(1, dt * rate)
		wave.Transparency = 0.12
		wave.CFrame = CFrame.new(0, waveY, 0) * CFrame.Angles(0, 0, math.rad(90))
	else
		waveY = -440
		wave.Transparency = 1
	end
end

return Backdrop
