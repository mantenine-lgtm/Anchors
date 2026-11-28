-- 엔진 불꽃과 추진운(뒤로 길게 남는 배기 연기).
-- 로켓은 제자리에 있으므로, 연기 덩어리를 불꽃 끝에서 내보내 아래로 흘려보내면 로켓 뒤에 연기 꼬리가 생깁니다.
-- 선실 화면과 바깥 시점이 같은 물체를 봅니다(시점마다 따로 두지 않음). 로켓 아래라서 실제로는 바깥 시점에서만 보입니다.
--  · 세기: 비행 구간을 따름. 최대 출력·구원 연료는 크고 진하게, 순항은 보통, 연료가 떨어진 뒤(솔라 세일·관성)는 약하게.
--    터보 엔진이 켜져 있으면 세게, 미션 콤보 성공이나 추진 부스터를 쓴 순간에는 잠깐 확 커짐
--  · 흐르는 빠르기: 발사 직후에는 땅이 멀어지는 빠르기와 같고(연기 기둥이 발사장에 이어짐), 빨라지면 구름·별빛 줄기와 같은 빠르기
--  · 발사 직후 땅에 닿은 연기는 발사장 위로 퍼짐
--  · 대기권 안은 흰 연기. 공기가 옅어지면(70 km~) 옅게 빛나는 배기로 바뀌고, 대기권 밖(100 km~)에는 연기가 없음
--  · 굵기는 선체 굵기(Config.World.HullRadius)를 따라감
-- 전부 내 화면에서만 만드는 것이라 다른 사람에게 영향이 없습니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local FlightSim = require(Shared:WaitForChild("FlightSim"))
local Route = require(Shared:WaitForChild("Route"))

local Planet = require(script.Parent:WaitForChild("Planet"))
local State = require(script.Parent:WaitForChild("State"))

local Exhaust = {}

local W = Config.World
local random = Random.new()

-- 크기: 엔진 스커트(반지름 = 선체 반지름 - 6)를 기준으로 (선체 반지름 26 이면 불꽃 굵기 24, 길이 70)
local NOZZLE_RADIUS = W.HullRadius - 6
local FLAME_WIDTH = NOZZLE_RADIUS * 1.2
local FLAME_LENGTH = FLAME_WIDTH * 2.9 -- 최대 출력일 때
local NOZZLE_Y = W.MountHeight + 4 -- 불꽃이 시작하는 높이 (엔진 스커트 안)

-- 비행 구간별 세기 (FlightSim.phaseAt 이름). 1 = 최대 출력
local PHASE_POWER = { rescue = 1.35, hot = 1, cruise = 0.78, sail = 0.6, coast = 0.5 }
local TURBO_POWER = 1.2 -- 터보 엔진이 켜져 있는 동안 적어도 이만큼
local BURST_POWER = 0.45 -- 미션 콤보 성공·추진 부스터를 쓴 순간 더하는 세기 (BURST_SECONDS 동안 줄어듦)
local BURST_SECONDS = 0.9
local THRUST_BOOSTERS = { RescueFuel = true, Turbo = true, Slingshot = true, Wormhole = true }

-- 추진운 연기 덩어리
local PUFF_COUNT = 90 -- 미리 만들어 두는 덩어리 수 (모자라면 가장 오래된 것을 다시 씀)
local PUFF_START = FLAME_WIDTH * 1.6 -- 갓 나온 덩어리 지름 (엔진 스커트 굵기쯤)
local PUFF_GAP = 0.4 -- 덩어리 사이 간격 = 지름 × 이 값 (겹쳐서 이어진 꼬리로 보이게)
local MIN_RATE = 14 -- 초당 적어도 이만큼 내보냄 (느릴 때도 성기지 않게)
local MAX_RATE = 45 -- 초당 많아야 이만큼
local TRAIL_LENGTH = 700 -- 최대 출력일 때 꼬리 길이(스터드). 바깥 시점 화면 아래 너머까지 이어짐
local LIFE_MIN = 1.2 -- 덩어리 하나가 사는 시간(초)의 범위
local LIFE_MAX = 3.5
local SMOKE_GROW = 3 -- 사라질 때까지 지름이 처음의 (1 + 이 값)배로 커짐
local GLOW_GROW = 3 -- 공기가 없으면 더 빨리 퍼짐
local SMOKE_ALPHA = 0.85 -- 가장 진할 때 불투명도
local GLOW_ALPHA = 0.3
local GROUND_SPREAD = 45 -- 땅에 닿은 연기가 옆으로 퍼지는 빠르기(스터드/초)
local RESULTS_FADE = 2.5 -- 비행이 끝나면 남은 연기가 이만큼 빨리 사라짐

local FLAME_COLOR = Color3.fromRGB(255, 190, 90)
local CORE_COLOR = Color3.fromRGB(255, 244, 205)
local SMOKE_HOT = Color3.fromRGB(255, 178, 100) -- 불꽃에 비친 갓 나온 연기
local SMOKE = Color3.fromRGB(226, 228, 234)
local GLOW_HOT = Color3.fromRGB(255, 196, 128)
local GLOW_COOL = Color3.fromRGB(150, 186, 255)

type Puff = {
	part: Part,
	alive: boolean,
	born: number, -- 내보낸 순서 (가장 오래된 것을 찾을 때)
	age: number,
	life: number,
	x: number,
	y: number,
	z: number,
	vx: number, -- 옆으로 움직이는 빠르기
	vz: number,
	fall: number, -- 아래로 흐르는 빠르기 배율 (덩어리마다 조금씩 다름)
	size: number, -- 처음 지름
	alpha: number, -- 처음 불투명도
	glow: boolean, -- 공기가 없는 곳의 빛나는 배기
	grounded: boolean,
	-- 마지막으로 부품에 넣은 값 (바뀔 때만 다시 넣음)
	shownSize: number,
	shownTransparency: number,
	shownColor: Color3?,
}

local container: Folder
local flame: Part
local core: Part
local flameLight: PointLight
local puffs: { Puff } = {}
local power = 0 -- 지금 세기 (부드럽게 따라감)
local trailSpeed = 0 -- 지금 연기가 흐르는 빠르기(스터드/초)
local emitDistance = 0 -- 마지막으로 내보낸 뒤 흐른 거리
local emitTime = 0 -- 마지막으로 내보낸 뒤 지난 시간
local bornCount = 0
local burstUntil = 0
local boostUntil = 0 -- 콤보 성공으로 줄기·구름이 빨라지는 동안 (Backdrop 과 같음)
local anyAlive = false

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
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function buildFlame()
	flame = localPart("EngineFlame", container)
	flame.Shape = Enum.PartType.Cylinder
	flame.Material = Enum.Material.Neon
	flame.Color = FLAME_COLOR
	flame.Size = Vector3.new(FLAME_LENGTH, FLAME_WIDTH, FLAME_WIDTH)
	flame.CFrame = CFrame.new(0, NOZZLE_Y - FLAME_LENGTH / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	core = localPart("EngineFlameCore", container)
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = CORE_COLOR
	core.Size = Vector3.new(FLAME_LENGTH * 0.55, FLAME_WIDTH * 0.55, FLAME_WIDTH * 0.55)
	core.CFrame = flame.CFrame
	flameLight = Instance.new("PointLight")
	flameLight.Color = Color3.fromRGB(255, 170, 90)
	flameLight.Range = 60
	flameLight.Brightness = 0
	flameLight.Shadows = false
	flameLight.Parent = flame
end

local function buildPuffs()
	for i = 1, PUFF_COUNT do
		local part = localPart("ExhaustPuff", container)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(PUFF_START, PUFF_START, PUFF_START)
		puffs[i] = {
			part = part,
			alive = false,
			born = 0,
			age = 0,
			life = 1,
			x = 0,
			y = 0,
			z = 0,
			vx = 0,
			vz = 0,
			fall = 1,
			size = PUFF_START,
			alpha = 0,
			glow = false,
			grounded = false,
			shownSize = PUFF_START,
			shownTransparency = 1,
			shownColor = nil,
		}
	end
end

-- ------------------------------------------------------------ 세기와 빠르기
-- 공기 밀도(0~1): 대기권 끝(100 km)에 가까워지면(70 km부터) 옅어지고 대기권을 벗어나면 0 (Route.heat 와 같은 기준)
local function airDensity(km: number): number
	local endKm = Route.atmosphereEndKm()
	return math.clamp((endKm - km) / (endKm - Config.Atmosphere.ThinAirKm), 0, 1)
end

-- 지금 비행 구간의 세기 (부스터·콤보로 잠깐 세지는 것 포함)
local function thrustTarget(clock: number): number
	local f = State.flight
	local name = FlightSim.phaseAt(f.t, State.number("HotTime"), State.number("FuelTime"), State.number("SailTime"), State.number("RescueUntil"))
	local target = PHASE_POWER[name] or 0.75
	if State.number(Boosters.untilAttribute("Turbo")) > f.t then
		target = math.max(target, TURBO_POWER)
	end
	if clock < burstUntil then
		target += BURST_POWER * (burstUntil - clock) / BURST_SECONDS
	end
	return target
end

-- 연기가 아래로 흐르는 빠르기(스터드/초). 느릴 때는 실제 빠르기(땅이 멀어지는 빠르기와 같음),
-- 빨라지면 구름·별빛 줄기(Backdrop)와 같은 빠르기. 둘 중 작은 쪽을 부드럽게 고름.
local function flowSpeed(clock: number): number
	local f = State.flight
	local metersPerSecond = math.max(f.speed, 0) * 1000
	local air = 60 + 140 * math.log10(1 + metersPerSecond / 5)
	local actual = metersPerSecond * W.StudsPerMeter
	local speed = if actual > 0.01 then (actual ^ -3 + air ^ -3) ^ (-1 / 3) else 0
	if clock < boostUntil then
		speed *= 1.7
	end
	if State.number("RescueUntil") > f.t then
		speed *= 1.8
	end
	return speed
end

-- 발사장 땅의 높이: 행성이 내려간 만큼 (바깥 시점에서 발사 직후 발사장 윗면과 같음)
local function groundY(): number
	return -Planet.visualAltitude(math.max(State.flight.km, 0))
end

-- ------------------------------------------------------------ 연기 덩어리
local function hidePuff(puff: Puff)
	puff.alive = false
	if puff.shownTransparency < 1 then
		puff.shownTransparency = 1
		puff.part.Transparency = 1
	end
end

local function hideAll()
	for _, puff in ipairs(puffs) do
		hidePuff(puff)
	end
	anyAlive = false
	emitDistance = 0
	emitTime = 0
end

local function freePuff(): Puff
	local oldest = puffs[1]
	for _, puff in ipairs(puffs) do
		if not puff.alive then
			return puff
		end
		if puff.born < oldest.born then
			oldest = puff
		end
	end
	return oldest
end

local function emit(flameLength: number, km: number)
	local puff = freePuff()
	bornCount += 1
	local strength = math.min(power, 1.2)
	local space = 1 - airDensity(km)
	local spread = FLAME_WIDTH * 0.15
	local angle = random:NextNumber() * math.pi * 2
	local drift = (3 + 0.05 * trailSpeed) * random:NextNumber()
	local length = TRAIL_LENGTH * (0.5 + 0.5 * strength)
	puff.alive = true
	puff.born = bornCount
	puff.age = 0
	puff.life = math.clamp(length / math.max(trailSpeed, 1), LIFE_MIN, LIFE_MAX) * (0.85 + 0.3 * random:NextNumber())
	puff.x = (random:NextNumber() * 2 - 1) * spread
	puff.z = (random:NextNumber() * 2 - 1) * spread
	puff.y = NOZZLE_Y - flameLength * 0.5 + (random:NextNumber() * 2 - 1) * 3 -- 불꽃 아래쪽 절반이 연기에 싸여 보임
	puff.vx = math.cos(angle) * drift
	puff.vz = math.sin(angle) * drift
	puff.fall = 0.92 + 0.16 * random:NextNumber()
	puff.size = PUFF_START * (0.85 + 0.3 * random:NextNumber()) * (0.75 + 0.25 * strength)
	puff.glow = space >= 0.5
	local density = math.clamp(0.35 + 0.65 * power, 0.3, 1)
	-- 연기는 공기가 옅어질수록 흐려짐
	puff.alpha = if puff.glow then GLOW_ALPHA * density else SMOKE_ALPHA * density * (1 - 0.45 * space)
	puff.grounded = false
	puff.shownColor = nil
	puff.part.Material = if puff.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	anyAlive = true
end

-- 덩어리 하나를 dt 만큼 움직이고 모양을 맞춤. 다 살았으면 숨김
local function stepPuff(puff: Puff, dt: number, ageRate: number, ground: number)
	puff.age += dt * ageRate
	local t = puff.age / puff.life
	if t >= 1 then
		hidePuff(puff)
		return
	end
	puff.y -= trailSpeed * puff.fall * dt
	puff.x += puff.vx * dt
	puff.z += puff.vz * dt
	local grow = if puff.glow then GLOW_GROW else SMOKE_GROW
	local size = puff.size * (1 + grow * t ^ 0.5)
	if puff.grounded then
		size *= 1.25
		local drag = math.exp(-0.7 * dt)
		puff.vx *= drag
		puff.vz *= drag
	end
	-- 로켓 밑동 위로는 올라가지 않음: 갓 나온 연기는 빠르게 부푸는데 아직 느리게 흐르므로, 위쪽은 불꽃 시작점에 맞추고 아래로 부풂
	local highest = NOZZLE_Y - size * 0.5
	if puff.y > highest then
		puff.y = highest
	end
	-- 땅 밑으로는 들어가지 않고 옆으로 퍼짐 (발사 직후. 땅이 가까우면 이쪽이 이김)
	local lowest = ground + size * 0.3
	if puff.y < lowest and not puff.glow then
		puff.y = lowest
		if not puff.grounded then
			puff.grounded = true
			local flat = Vector3.new(puff.x, 0, puff.z)
			local away = if flat.Magnitude > 0.5 then flat.Unit else Vector3.new(math.cos(puff.born * 2.4), 0, math.sin(puff.born * 2.4))
			local push = GROUND_SPREAD * (0.6 + 0.8 * random:NextNumber()) * (0.6 + 0.4 * math.min(power, 1))
			puff.vx = away.X * push
			puff.vz = away.Z * push
		end
	end
	local part = puff.part
	if math.abs(size - puff.shownSize) > puff.shownSize * 0.03 then
		puff.shownSize = size
		part.Size = Vector3.new(size, size, size)
	end
	part.CFrame = CFrame.new(puff.x, puff.y, puff.z)
	local transparency = 1 - puff.alpha * (1 - t) ^ 1.4
	if math.abs(transparency - puff.shownTransparency) > 0.01 then
		puff.shownTransparency = transparency
		part.Transparency = transparency
	end
	local color = if puff.glow then GLOW_HOT:Lerp(GLOW_COOL, math.min(1, t / 0.4)) else SMOKE_HOT:Lerp(SMOKE, math.min(1, t / 0.1))
	if puff.shownColor ~= color then
		puff.shownColor = color
		part.Color = color
	end
end

-- ------------------------------------------------------------ 불꽃
local function applyFlame(on: boolean, clock: number): number
	if not on then
		flame.Transparency = 1
		core.Transparency = 1
		flameLight.Brightness = 0
		return 0
	end
	local flicker = 0.85 + 0.3 * math.noise(clock * 14, 3.1)
	local strength = 0.45 + 0.55 * power
	local length = FLAME_LENGTH * strength * flicker
	local width = FLAME_WIDTH * (0.8 + 0.2 * math.min(power, 1.4))
	local upright = CFrame.Angles(0, 0, math.rad(90))
	flame.Transparency = 0.15
	flame.Size = Vector3.new(length, width, width)
	flame.CFrame = CFrame.new(0, NOZZLE_Y - length / 2, 0) * upright
	core.Transparency = 0.05
	core.Size = Vector3.new(length * 0.55, width * 0.55, width * 0.55)
	core.CFrame = CFrame.new(0, NOZZLE_Y - length * 0.55 / 2, 0) * upright
	flameLight.Brightness = 3 * flicker * (0.5 + 0.5 * math.min(power, 1.4))
	return length
end

-- ------------------------------------------------------------ 매 프레임
function Exhaust.init()
	container = Instance.new("Folder")
	container.Name = "RoflyExhaust"
	container.Parent = Workspace
	buildFlame()
	buildPuffs()

	State.on("MissionFx", function(rate: number)
		if rate >= Config.Mission.ComboRule then
			burstUntil = os.clock() + BURST_SECONDS
			boostUntil = os.clock() + 0.9
		end
	end)
	State.on("ItemUsed", function(info: any)
		if type(info) == "table" and THRUST_BOOSTERS[info.item] then
			burstUntil = os.clock() + BURST_SECONDS
		end
	end)
	State.on("Phase", function(phase: string)
		if phase == "Join" or phase == "Build" then
			power = 0
			trailSpeed = 0
			hideAll()
		end
	end)
end

function Exhaust.update(dt: number)
	local phase = State.phase()
	local clock = os.clock()
	local flying = State.flying() -- 충격파에 잡히면(엔딩) 엔진이 꺼진 것으로 봄: 불꽃을 끄고 남은 연기만 사라지게
	local after = phase == "Results" or phase == "Flight" -- 비행이 끝난 뒤 (엔딩·정산): 남은 연기가 천천히 흐르며 사라짐

	if flying then
		local target = thrustTarget(clock)
		power += (target - power) * math.min(1, dt * (if target > power then 6 else 2))
		trailSpeed = flowSpeed(clock)
	else
		power = 0
		-- 비행이 끝나면 남은 연기는 천천히 흐르며 사라짐
		trailSpeed += (8 - trailSpeed) * math.min(1, dt * 1.5)
	end
	local flameLength = applyFlame(flying, clock)

	if flying then
		emitDistance += trailSpeed * dt
		emitTime += dt
		local gap = PUFF_START * PUFF_GAP
		local made = 0
		while (emitDistance >= gap or emitTime >= 1 / MIN_RATE) and made < math.max(1, math.ceil(MAX_RATE * dt)) do
			emit(flameLength, State.flight.km)
			emitDistance = math.max(0, emitDistance - gap)
			emitTime = 0
			made += 1
		end
		if made > 0 and emitDistance >= gap then
			emitDistance = 0 -- 너무 빨라 다 못 내보낸 만큼은 버림 (한꺼번에 몰리지 않게)
		end
	elseif not after then
		if anyAlive then
			hideAll()
		end
		return
	end

	if not anyAlive then
		return
	end
	local ground = groundY()
	local ageRate = if flying then 1 else RESULTS_FADE
	local alive = false
	for _, puff in ipairs(puffs) do
		if puff.alive then
			stepPuff(puff, dt, ageRate, ground)
			alive = alive or puff.alive
		end
	end
	anyAlive = alive
end

-- 검사용
Exhaust._internal = {
	puffs = puffs,
	flameWidth = FLAME_WIDTH,
	flameLength = FLAME_LENGTH,
	nozzleY = NOZZLE_Y,
	power = function(): number
		return power
	end,
	trailSpeed = function(): number
		return trailSpeed
	end,
}

return Exhaust
