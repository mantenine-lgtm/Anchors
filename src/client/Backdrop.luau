-- 배경 연출. 로켓은 제자리에 있고 배경이 움직여서 날아가는 것처럼 보입니다.
-- 선실 외창 너머로 보이는 것과 바깥 시점에서 보이는 것은 모두 같은 물체입니다(시점마다 따로 두지 않음).
--  · 발사 행성과 발사장은 Planet.luau 가 움직임. 고향 하늘(1단계) 빛은 판마다 바뀌는 행성의 하늘(Planets.luau)
--  · 충격파: 아래에서 올라오는 빛나는 판. 도달 예상 시간이 줄수록 가까이 옴
--  · 대기권(100 km까지): 마찰로 코와 외창 바깥면이 빨갛게 달아오름(빠를수록 셈). 화면 흔들림은 CameraRig
--  · 별빛 줄기: 대기권을 벗어난 뒤에만, 속도가 빠를수록 빠르게 아래로 흐름 (발사 전에는 천천히 떠오르는 불티)
--  · 하늘: 스테이지마다 빛과 안개 색이 바뀜, 폭풍 구름층에서는 번개
--  · 위기: 경보등이 깜박이고 화면이 붉어짐
--  · 엔진 불꽃과 추진운은 Exhaust.luau
-- 전부 내 화면에서만 바꾸는 것이라 다른 사람에게 영향이 없습니다.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Planets = require(Shared:WaitForChild("Planets"))
local Route = require(Shared:WaitForChild("Route"))

local State = require(script.Parent:WaitForChild("State"))

local Backdrop = {}

local W = Config.World
local random = Random.new()

-- 별빛 줄기: 로켓을 빙 두른 한 무리. 외창 너머로 보이는 줄기도 바깥 시점에서 보이는 줄기도 같은 것입니다.
-- 고르게 퍼져 있어서 외창 너머로는 한 번에 8개쯤 보입니다(예전 앞쪽 무리는 20개쯤).
local STREAK_COUNT = 300
local EMBER_COUNT = 70 -- 발사 전 불티로는 이 개수만 씀
local STREAK_TOP = 380
local STREAK_BOTTOM = -160
local STREAK_RADIUS_MIN = 60 -- 선실 카메라(선체 뒤쪽 바깥)보다 바깥에서만 흐름
local STREAK_RADIUS_MAX = 220
local STREAK_CLEARANCE = 15 -- 바깥 시점 카메라 바로 옆으로는 지나가지 않음
local CLOUD_COUNT = 9

-- 마찰 열: 원래 부품 위에 살짝 큰 빛나는 껍데기를 씌워 달아오르게 보임. 숫자는 부위별 열 비율(코 끝이 가장 뜨거움)
local HEAT_PARTS = { NoseTip = 1, Nose4 = 1, Nose3 = 0.9, Nose2 = 0.75, Nose1 = 0.6, UpperHull = 0.3 }
local HEAT_GLOW_ALPHA = 0.9 -- 가장 뜨거울 때 껍데기의 진하기
local HEAT_PANE_ALPHA = 0.45 -- 외창 바깥면 (선실에서 외창 너머가 붉게 보이는 정도)
local HEAT_DIM = Color3.fromRGB(150, 26, 8)
local HEAT_RED = Color3.fromRGB(255, 72, 24)
local HEAT_HOT = Color3.fromRGB(255, 168, 70)

type Sky = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	Outdoor: Color3,
	Density: number,
	Haze: number,
	Color: Color3,
	Decay: Color3, -- 해에서 먼 쪽 하늘빛. Atmosphere.Glare 가 0 보다 커야 보임 (지금은 0 이라 Color 만 보임)
	Streak: Color3,
	Clouds: number, -- 구름이 보이는 정도 (0~1)
}

-- 스테이지별 하늘. 5번째부터는 우주.
-- Density(안개 짙기)가 높으면 빛줄기·구름과 충격파가 흐려지므로 너무 올리지 않습니다.
-- Ambient 는 하늘이 가린 곳(선실 안), Outdoor 는 바깥의 빛입니다. 선실이 바깥보다 어둡게 Ambient 는 Outdoor 의 38% 쯤
-- (행성 하늘도 같음. 바깥이 아주 어두운 단계는 가장 밝은 색 성분이 40 이 되게 해서 선실이 너무 어둡지 않게)
local SKIES: { Sky } = {
	{ -- 붕괴하는 고향 행성: 노을빛 먼지
		ClockTime = 17.6, Brightness = 2, Ambient = Color3.fromRGB(52, 48, 46), Outdoor = Color3.fromRGB(138, 126, 120),
		Density = 0.3, Haze = 2.2, Color = Color3.fromRGB(230, 150, 110), Decay = Color3.fromRGB(120, 60, 40),
		Streak = Color3.fromRGB(255, 240, 205), Clouds = 0.25,
	},
	{ -- 폭풍 구름층: 어둡고 푸른 구름
		ClockTime = 18.4, Brightness = 1, Ambient = Color3.fromRGB(30, 32, 40), Outdoor = Color3.fromRGB(70, 74, 92),
		Density = 0.38, Haze = 2.8, Color = Color3.fromRGB(90, 96, 116), Decay = Color3.fromRGB(40, 44, 60),
		Streak = Color3.fromRGB(205, 225, 255), Clouds = 1,
	},
	{ -- 화산재 하늘: 붉은 재
		ClockTime = 18.7, Brightness = 1.2, Ambient = Color3.fromRGB(40, 27, 24), Outdoor = Color3.fromRGB(106, 70, 62),
		Density = 0.34, Haze = 2.6, Color = Color3.fromRGB(150, 80, 60), Decay = Color3.fromRGB(70, 30, 24),
		Streak = Color3.fromRGB(255, 205, 150), Clouds = 0.7,
	},
	{ -- 오로라 하늘
		ClockTime = 21, Brightness = 0.9, Ambient = Color3.fromRGB(21, 35, 40), Outdoor = Color3.fromRGB(48, 80, 92),
		Density = 0.2, Haze = 0.6, Color = Color3.fromRGB(70, 160, 150), Decay = Color3.fromRGB(30, 60, 90),
		Streak = Color3.fromRGB(200, 255, 230), Clouds = 0,
	},
	{ -- 우주
		ClockTime = 0, Brightness = 0.7, Ambient = Color3.fromRGB(26, 27, 40), Outdoor = Color3.fromRGB(36, 38, 56),
		Density = 0.02, Haze = 0, Color = Color3.fromRGB(20, 22, 40), Decay = Color3.fromRGB(10, 10, 20),
		Streak = Color3.fromRGB(215, 235, 255), Clouds = 0,
	},
}

local container: Folder

local wave: Part
-- 멀리 있을 때의 충격파 높이: 바깥 시점 화면 아래 끝보다 낮아서 안 보임. 다가오면(도달 30초 이내) 올라와 보이기 시작
local WAVE_FAR_Y = -1150
local waveY = WAVE_FAR_Y

type Streak = {
	part: Part,
	radius: number,
	angle: number,
	y: number,
	speedScale: number,
	width: number,
	-- 마지막으로 부품에 넣은 값 (바뀔 때만 다시 넣어 매 프레임 일을 줄임)
	length: number,
	color: Color3?,
	transparency: number,
}
local streaks: { Streak } = {}
-- 줄기가 보이는 정도(0~1)와 지금 그리는 종류: "ember" 발사 전 불티 | "star" 대기권 밖 별빛 | "none" 숨김(대기권 안)
-- 종류가 바뀌면 지금 것을 먼저 흐리게 지우고 바꿈
local streakShown = 1
local streakMode = "ember"
local streaksHidden = false
type Glow = { part: Part, weight: number, alpha: number }
local glows: { Glow } = {}
local heatLight: PointLight? = nil
local glowShown = false
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

-- 로켓 둘레에 놓일 방향(각도)을 뽑음. 구름 공이나 빛줄기가 바깥 시점 카메라를 덮으면 화면이 갑자기
-- 가려졌다 걷히므로, 카메라에서 clearance 안으로 오는 자리는 다시 뽑습니다.
local function aroundAngle(radius: number, clearance: number): number
	local cameraX, cameraZ = W.OutsideCamera[1], W.OutsideCamera[3]
	local angle = random:NextNumber() * math.pi * 2
	for _ = 1, 12 do
		local dx = math.sin(angle) * radius - cameraX
		local dz = math.cos(angle) * radius - cameraZ
		if math.sqrt(dx * dx + dz * dz) > clearance then
			break
		end
		angle = random:NextNumber() * math.pi * 2
	end
	return angle
end

local function cloudAngle(radius: number, size: number): number
	return aroundAngle(radius, size / 2 + 20)
end

local function buildStreaks()
	for i = 1, STREAK_COUNT do
		local part = localPart("Streak", container)
		part.Material = Enum.Material.Neon
		local width = 0.45 + random:NextNumber() * 0.4
		part.Size = Vector3.new(width, 4, width)
		local radius = STREAK_RADIUS_MIN + random:NextNumber() * (STREAK_RADIUS_MAX - STREAK_RADIUS_MIN)
		local streak: Streak = {
			part = part,
			radius = radius,
			angle = aroundAngle(radius, STREAK_CLEARANCE),
			y = STREAK_BOTTOM + random:NextNumber() * (STREAK_TOP - STREAK_BOTTOM),
			speedScale = 0.7 + random:NextNumber() * 0.6,
			width = width,
			length = 4,
			color = nil,
			transparency = 0,
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
		local radius = 190 + random:NextNumber() * 260
		local cloud: Cloud = {
			part = part,
			radius = radius,
			angle = cloudAngle(radius, size),
			y = STREAK_BOTTOM + random:NextNumber() * (STREAK_TOP - STREAK_BOTTOM),
			size = size,
		}
		clouds[i] = cloud
	end
end

local function findRocketParts()
	local rofly = Workspace:WaitForChild("Rofly")
	local rocket = rofly:WaitForChild("Rocket")
	rocket:WaitForChild("NoseTip", 10)
	local walls = rocket:WaitForChild("Walls", 10)
	for _, item in ipairs(rocket:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "AlarmLight" then
			table.insert(alarmParts, item)
		elseif item:IsA("BasePart") and item.Name == "Lamp" then
			local light = item:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(lamps, light)
			end
		elseif item:IsA("Part") and HEAT_PARTS[item.Name] then
			-- 마찰 열 껍데기: 같은 모양으로 조금 크게
			local glow = localPart("HeatGlow", container)
			glow.Shape = item.Shape
			glow.Material = Enum.Material.Neon
			glow.Transparency = 1
			glow.Size = item.Size + (if item.Shape == Enum.PartType.Ball then Vector3.new(0.8, 0.8, 0.8) else Vector3.new(0.2, 0.8, 0.8))
			glow.CFrame = item.CFrame
			table.insert(glows, { part = glow, weight = HEAT_PARTS[item.Name], alpha = HEAT_GLOW_ALPHA })
			if item.Name == "NoseTip" then
				local light = Instance.new("PointLight")
				light.Range = 45
				light.Brightness = 0
				light.Shadows = false
				light.Parent = glow
				heatLight = light
			end
		end
	end
	-- 외창 바깥면: 유리판마다 선체 바깥면 바로 밖에 빛나는 판 (선실에서는 외창 너머가 붉게, 바깥에서는 외창이 달아올라 보임)
	if walls then
		local panelRadius = (W.CabinRadius + W.HullRadius) / 2
		local paneRadius = W.HullRadius + 0.5
		for _, panel in ipairs(walls:GetChildren()) do
			if panel:IsA("BasePart") and panel.Name == "Window" then
				local pane = localPart("HeatPane", container)
				pane.Material = Enum.Material.Neon
				pane.Transparency = 1
				pane.Size = Vector3.new(panel.Size.X * paneRadius / panelRadius + 0.1, W.WindowTopY - W.WindowBottomY + 2, 0.3)
				-- 벽판의 앞(+Z)이 바깥쪽
				pane.CFrame = panel.CFrame * CFrame.new(0, 0, paneRadius - panelRadius)
				table.insert(glows, { part = pane, weight = 1, alpha = HEAT_PANE_ALPHA })
			end
		end
	end
end

-- ------------------------------------------------------------ 하늘
local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 고향 하늘(1단계): 이번 판 행성의 하늘
local function homeSky(): Sky
	return Planets.get(State.text("Planet")).Sky
end

local function blendSky(target: Sky, t: number)
	-- 시각은 24시간이 한 바퀴이므로 가까운 쪽으로 돌려 섞음 (21시에서 0시로 갈 때 낮을 거치지 않게)
	local hours = (target.ClockTime - sky.ClockTime + 12) % 24 - 12
	sky.ClockTime = (sky.ClockTime + hours * t) % 24
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

local function heatColor(h: number): Color3
	if h < 0.5 then
		return HEAT_DIM:Lerp(HEAT_RED, h * 2)
	end
	return HEAT_RED:Lerp(HEAT_HOT, math.min(1, (h - 0.5) * 2))
end

-- 마찰 열(0~1)만큼 껍데기와 외창 바깥면을 달아오르게 함. 식으면 숨김.
local function applyHeat(heat: number, clock: number)
	if heat < 0.01 then
		if glowShown then
			glowShown = false
			for _, glow in ipairs(glows) do
				glow.part.Transparency = 1
			end
			if heatLight then
				heatLight.Brightness = 0
			end
		end
		return
	end
	glowShown = true
	for i, glow in ipairs(glows) do
		local h = heat * glow.weight
		local flicker = 0.88 + 0.12 * math.noise(clock * 6, i * 1.37)
		glow.part.Color = heatColor(h)
		glow.part.Transparency = 1 - glow.alpha * math.clamp(h * 1.15, 0, 1) * flicker
	end
	if heatLight then
		heatLight.Color = heatColor(heat)
		heatLight.Brightness = 4 * heat
	end
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

	sky = table.clone(homeSky())
	buildWave()
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

	-- 하늘
	local stage = if flying or phase == "Results" then math.min(Route.stageIndex(f.km), #SKIES) else 1
	blendSky(if stage == 1 then homeSky() else SKIES[stage], math.min(1, dt * 0.9))
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

	-- 마찰 열 (대기권 안에서 빠를수록)
	applyHeat(State.heat, clock)

	-- 빛줄기의 흐름 빠르기 (구름도 씀)
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
	elseif phase == "Results" then
		-- 정산: 천천히 흐르는 별
		speedStuds = 8
		length = 2.2
	else
		-- 발사 전: 천천히 떠오르는 불티
		speedStuds = -9
		length = 1.6
	end

	-- 별빛 줄기: 대기권을 벗어난 뒤에만. 대기권 안(비행·정산)에서는 숨기고, 발사장에서는 불티
	local mode = "ember"
	if flying or phase == "Results" then
		mode = if f.km >= Route.atmosphereEndKm() then "star" else "none"
	end
	if streakMode ~= mode then
		streakShown = math.max(0, streakShown - dt * 2.5)
		if streakShown <= 0 then
			streakMode = mode
		end
	elseif mode ~= "none" then
		streakShown = math.min(1, streakShown + dt * 0.8)
	end
	if streakShown <= 0 or streakMode == "none" then
		if not streaksHidden then
			streaksHidden = true
			for _, streak in ipairs(streaks) do
				streak.part.Transparency = 1
				streak.transparency = 1
			end
		end
	else
		streaksHidden = false
		local count = if streakMode == "ember" then EMBER_COUNT else #streaks
		local transparency = 1 - streakShown
		for i, streak in ipairs(streaks) do
			local part = streak.part
			if i > count then
				if streak.transparency < 1 then
					part.Transparency = 1
					streak.transparency = 1
				end
			else
				local y = streak.y - speedStuds * streak.speedScale * dt
				if y < STREAK_BOTTOM then
					y += STREAK_TOP - STREAK_BOTTOM
					streak.angle = aroundAngle(streak.radius, STREAK_CLEARANCE)
				elseif y > STREAK_TOP then
					y -= STREAK_TOP - STREAK_BOTTOM
					streak.angle = aroundAngle(streak.radius, STREAK_CLEARANCE)
				end
				streak.y = y
				if streak.transparency ~= transparency then
					streak.transparency = transparency
					part.Transparency = transparency
				end
				if math.abs(streak.length - length) > 0.25 then
					streak.length = length
					part.Size = Vector3.new(streak.width, length, streak.width)
				end
				if streak.color ~= sky.Streak then
					streak.color = sky.Streak
					part.Color = sky.Streak
				end
				part.CFrame = CFrame.new(math.sin(streak.angle) * streak.radius, y, math.cos(streak.angle) * streak.radius)
			end
		end
	end
	local span = STREAK_TOP - STREAK_BOTTOM
	for _, cloud in ipairs(clouds) do
		local visible = if flying then sky.Clouds else 0
		local part = cloud.part
		if visible <= 0.02 then
			part.Transparency = 1
		else
			local y = cloud.y - speedStuds * 0.45 * dt
			if y < STREAK_BOTTOM - 100 then
				y += span + 200
				cloud.angle = cloudAngle(cloud.radius, cloud.size)
			end
			cloud.y = y
			part.Transparency = 1 - 0.5 * visible
			part.Color = sky.Color:Lerp(Color3.new(0, 0, 0), 0.35)
			part.CFrame = CFrame.new(math.sin(cloud.angle) * cloud.radius, y, math.cos(cloud.angle) * cloud.radius)
		end
	end

	-- 충격파: 도달 예상 시간이 짧을수록 선실 바닥 가까이 올라옴.
	-- 위기(10초 이내)에는 로켓 밑동 아래에서 선실 바닥까지(선실 외창에 보임), 그 전에는 바깥 시점 화면 아래 끝에서 로켓 밑동까지
	local targetY = WAVE_FAR_Y
	local waveVisible = false
	if flying then
		waveVisible = true
		local eta = math.clamp(State.number("Eta"), 0, Config.Crisis.EtaLimit)
		local below = if eta <= 10 then eta * 23.4 else 234 + (eta - 10) * 51.8
		targetY = math.max(W.CabinFloorY - below, WAVE_FAR_Y)
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
		waveY = WAVE_FAR_Y
		wave.Transparency = 1
	end
end

return Backdrop
