-- 전광판 추격 화면: 진행도 전광판 아래쪽의 그림.
-- 로켓이 왼쪽(붕괴하는 고향 행성)에서 오른쪽(폭발권 밖)으로 날아가고, 붕괴 충격파가 화면 높이를 다 덮는 면으로 뒤따라옵니다.
-- 충격파 면이 로켓 꼬리에 닿으면 로켓이 터집니다 (그때 비행이 끝남).
--
-- 가로 위치
--   로켓 꼬리 = 출발해서 온 거리 (Route.logPosition 로그 눈금. 행성 표면 = 0 km, 오른쪽 결승선 = 폭발권 밖).
--   충격파 면의 앞 = 꼬리에서 '충격파 도달 예상 시간'(서버 Eta)만큼 뒤. 30초 이상이면 가장 멀고, 0초면 꼬리에 닿음.
--   실제 거리 차이는 로그 눈금에서 위기 때 몇 픽셀밖에 안 되므로, 위험한 정도가 보이도록 시간으로 간격을 잡습니다.
--   미션에 성공하거나 부스터를 쓰면 도달 시간이 늘어 면이 뒤로 밀려납니다.
-- Board.luau 가 전광판 안의 틀을 넘겨 ChaseView.build 를 부르고, 매 프레임 ChaseView.update 를 부릅니다.
-- 크기는 넘겨받은 틀의 픽셀 크기로 잡으므로 전광판 크기가 바뀌어도 그대로 씁니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Planets = require(Shared:WaitForChild("Planets"))
local Route = require(Shared:WaitForChild("Route"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local ChaseView = {}

local C = Ui.Colors

-- 간격 = 가장 먼 간격 × (도달 시간 / 30초)^GAP_EXP. 1보다 작아서 마지막 몇 초에 면이 확 달려듭니다.
local GAP_EXP = 0.6
local GAP_FOLLOW = 5 -- 간격이 목표를 따라가는 빠르기(1/초). 미션 성공으로 밀려날 때 부드럽게 움직임
local RUSH = 6 -- 비행이 끝났는데 면이 아직 떨어져 있으면(디버그 건너뛰기 등) 꼬리까지 달려오는 빠르기 (로켓 길이/초)
local FLASH_TIME = 0.3 -- 터질 때 번쩍이는 시간(초)
local BLAST_TIME = 1.6 -- 폭발 조각이 사라지는 시간(초)
local SWEEP_TIME = 0.9 -- 터진 뒤 면이 로켓 자리를 덮고 지나가는 시간(초)
local SWEEP_LENGTH = 0.8 -- 그동안 꼬리보다 앞으로 나가는 거리 (로켓 길이 배)
local SHAKE_TIME = 0.6 -- 터질 때 화면이 흔들리는 시간(초)
local LAUNCH_GLOW_TIME = 1.2 -- 발사 순간 행성 테두리가 밝아지는 시간(초)
local DEBRIS_COUNT = 14
local RIPPLE_COUNT = 4 -- 면 안에서 앞으로 밀려가는 물결 선 (충격파가 밀고 오는 느낌)
local RIPPLE_SPAN = 1.3 -- 물결 선이 생기는 깊이: 면의 앞에서 뒤로 로켓 길이 × 이 값
local RIPPLE_SPEED = 0.8 -- 물결 선이 1초에 앞으로 나아가는 몫 (깊이 전체 = 1)

local BACK = Color3.fromRGB(4, 6, 14)
local HULL = Color3.fromRGB(226, 232, 242)
local FIN = Color3.fromRGB(110, 122, 150)
local FLAME = Color3.fromRGB(255, 150, 60)
local FLAME_CORE = Color3.fromRGB(255, 236, 160)
local WAVE = Color3.fromRGB(255, 120, 80)
local WAVE_EDGE = Color3.fromRGB(255, 190, 110)
local WAVE_FRONT = Color3.fromRGB(255, 244, 214)
local FINISH = Color3.fromRGB(120, 255, 170)

type Fireball = { frame: Frame, dx: number, dy: number, size: number, delay: number, duration: number }
type Debris = { frame: Frame, vx: number, vy: number, spin: number, size: number }

local root: Frame? = nil
local shaker: Frame
local width = 0
local height = 0
local strip = 0 -- 위·아래 글자 줄 높이(px)
local L = 0 -- 로켓 길이(px)
local rocketH = 0 -- 로켓 몸통 굵기(px)
local startX = 0 -- 0 km 일 때 꼬리 x (행성 표면)
local endX = 0 -- 루트 끝일 때 꼬리 x (결승선)
local midY = 0 -- 궤적 높이
local maxGap = 0

local planetBody: Frame
local planetGlow: UIStroke
local cracks: { Frame } = {}
local planetId: string? = nil
local wallBody: Frame
local wallGlow: Frame
local wallFront: Frame
local ripples: { Frame } = {}
local recordLine: Frame
local recordLabel: TextLabel
local rocket: Frame
local hull: Frame
local nose: Frame
local flame: Frame
local flameCore: Frame
local flash: Frame
local fireballs: { Fireball } = {}
local debris: { Debris } = {}
local wreck: Frame

-- 판 진행 상태
local shownGap = 0
local ended: string? = nil -- nil = 비행 전이거나 비행 중 | "caught" = 따라잡힘 | "escaped" = 탈출
local endKm = 0
local blasted = false -- 로켓이 터졌는지
local blastAt = 0 -- 터진 시각(os.clock)
local launchedAt = 0
local lastPhase = ""
local sawFlight = false -- 이번 판의 비행을 봤는지 (정산 중에 들어왔으면 false)
local shaking = false
local random = Random.new()

-- 꼬리 x: 출발해서 온 거리(km)
local function tailX(km: number): number
	return startX + Route.logPosition(km) * (endX - startX)
end

-- 충격파 도달 예상 시간(초) -> 꼬리와 면 사이 간격(px)
local function gapFor(eta: number): number
	local share = math.clamp(eta / Config.Crisis.EtaLimit, 0, 1)
	return maxGap * share ^ GAP_EXP
end

local function round(frame: Frame)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
end

local function solid(parent: Instance, name: string, color: Color3, z: number, props: { [string]: any }): Frame
	local frame = Ui.frame(parent, name, { BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = z })
	for key, value in pairs(props) do
		(frame :: any)[key] = value
	end
	return frame
end

local function buildTrack(font: number)
	local band = height - strip * 2
	local lineWidth = math.max(2, math.floor(L * 0.03))
	-- 결승선 너머: 안전 지대
	solid(shaker, "ChaseSafe", FINISH, 1, {
		Position = UDim2.fromOffset(endX, strip),
		Size = UDim2.fromOffset(width - endX, band),
		BackgroundTransparency = 0.88,
	})
	-- 궤적 선
	solid(shaker, "ChasePath", C.Line, 1, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(startX, midY),
		Size = UDim2.fromOffset(endX - startX, lineWidth),
		BackgroundTransparency = 0.3,
	})
	-- 스테이지 경계 눈금 (챕터 경계는 길게)
	local chapters = Config.Route.Chapters
	local chapterEnd: { [number]: boolean } = {}
	for i = 1, #chapters - 1 do
		chapterEnd[chapters[i].EndKm] = true
	end
	for i = 1, Route.stageCount() - 1 do
		local km = Route.stage(i).EndKm
		local long = chapterEnd[km] == true
		solid(shaker, "ChaseTick" .. i, C.Line, 1, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(tailX(km), midY),
			Size = UDim2.fromOffset(lineWidth, if long then band * 0.8 else band * 0.22),
			BackgroundTransparency = if long then 0.15 else 0.35,
		})
	end
	-- 챕터 이름: 아래 줄, 자기 구간 가운데 (구간이 좁아 글자가 안 들어가면 생략). 충격파 면 위에도 보이게 그림
	for i, chapter in ipairs(chapters) do
		local x0 = tailX(if i == 1 then 0 else chapters[i - 1].EndKm)
		local x1 = tailX(chapter.EndKm)
		local need = (utf8.len(chapter.Name) or #chapter.Name) * font + 8
		if x1 - x0 >= need then
			Ui.label(shaker, "ChaseChapter" .. i, chapter.Name, font, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromOffset((x0 + x1) / 2, height - 2),
				Size = UDim2.fromOffset(x1 - x0, strip),
				TextColor3 = C.Dim,
				ZIndex = 4,
			})
		end
	end
	-- 결승선과 이름 (위 줄 오른쪽 끝)
	solid(shaker, "ChaseFinish", FINISH, 1, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(endX, strip * 0.5),
		Size = UDim2.fromOffset(math.max(3, math.floor(L * 0.04)), band + strip * 0.5),
		BackgroundTransparency = 0.1,
	})
	Ui.label(shaker, "ChaseFinishName", Config.Route.EscapeName, font, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(width - 4, 0),
		Size = UDim2.fromOffset(width * 0.3, strip),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = FINISH,
		ZIndex = 1,
	})
end

-- 고향 행성: 왼쪽 끝의 큰 원. 오른쪽 끝(행성 표면)이 출발점이고, 충격파가 여기서 퍼져 나옴.
local function buildPlanet()
	local radius = startX * 0.75
	local cx = startX - radius
	planetBody = solid(shaker, "ChasePlanet", Color3.fromRGB(90, 60, 50), 2, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, midY),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
	})
	round(planetBody)
	planetGlow = Ui.stroke(planetBody, C.Orange, math.max(2, L * 0.03), 0.3)
	-- 붕괴 균열: 보이는 오른쪽 안에 빛나는 금 3개 (중심에서 바깥으로)
	for i, deg in ipairs({ -38, 4, 42 }) do
		local angle = math.rad(deg)
		local crack = solid(shaker, "ChaseCrack" .. i, C.Orange, 2, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + math.cos(angle) * radius * 0.66, midY + math.sin(angle) * radius * 0.66),
			Size = UDim2.fromOffset(radius * 0.38, math.max(2, L * 0.03)),
			Rotation = deg,
			BackgroundTransparency = 0.3,
		})
		table.insert(cracks, crack)
	end
end

-- 충격파 면: 왼쪽 끝부터 면의 앞까지 화면 높이를 다 덮음. 앞쪽일수록 밝고 진함.
local function buildWave()
	-- 왼쪽 끝은 틀 밖에서 시작 (터질 때 화면이 흔들려도 면의 왼쪽 끝이 드러나지 않게)
	wallBody = solid(shaker, "ChaseWave", WAVE, 3, {
		Position = UDim2.fromOffset(-L * 0.2, 0),
		Size = UDim2.fromOffset(0, height),
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	Ui.make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 60, 90), Color3.fromRGB(255, 255, 255)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = wallBody,
	})
	wallGlow = solid(shaker, "ChaseWaveGlow", WAVE_EDGE, 3, {
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(L * 0.5, height),
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	Ui.make("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = wallGlow })
	wallFront = solid(shaker, "ChaseWaveFront", WAVE_FRONT, 3, {
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(math.max(3, math.floor(L * 0.045)), height),
		Visible = false,
	})
	for i = 1, RIPPLE_COUNT do
		table.insert(ripples, solid(shaker, "ChaseRipple" .. i, WAVE_EDGE, 3, {
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(math.max(2, math.floor(L * 0.03)), height),
			Visible = false,
		}))
	end
end

-- 로켓: 오른쪽을 보는 옆모습 (꼬리 = 왼쪽 끝, 불꽃은 그 뒤로)
local function buildRocket()
	local boxH = rocketH * 2.4
	local cy = boxH / 2
	rocket = Ui.frame(shaker, "ChaseRocket", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(startX, midY),
		Size = UDim2.fromOffset(L, boxH),
		ZIndex = 5,
	})
	flame = solid(rocket, "ChaseFlame", FLAME, 1, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(L * 0.08, cy),
		Size = UDim2.fromOffset(L * 0.36, rocketH * 0.62),
		Visible = false,
	})
	round(flame)
	flameCore = solid(rocket, "ChaseFlameCore", FLAME_CORE, 2, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(L * 0.08, cy),
		Size = UDim2.fromOffset(L * 0.2, rocketH * 0.3),
		Visible = false,
	})
	round(flameCore)
	-- 꼬리 날개 두 장 (몸통 위아래로 뒤로 젖혀짐)
	for i, sign in ipairs({ -1, 1 }) do
		solid(rocket, "ChaseFin" .. i, FIN, 3, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(L * 0.17, cy + sign * rocketH * 0.5),
			Size = UDim2.fromOffset(L * 0.24, rocketH * 0.42),
			Rotation = -sign * 28,
		})
	end
	hull = solid(rocket, "ChaseHull", HULL, 4, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(L * 0.04, cy),
		Size = UDim2.fromOffset(L * 0.72, rocketH),
	})
	Ui.corner(hull, math.max(2, math.floor(rocketH * 0.18)))
	-- 둥근 코 (스테인리스 원통 선체)
	nose = solid(rocket, "ChaseNose", HULL, 4, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(L, cy),
		Size = UDim2.fromOffset(L * 0.5, rocketH),
	})
	round(nose)
	-- 선실 창 (승무원이 타고 있는 곳)
	local window = solid(rocket, "ChaseWindow", C.Cyan, 5, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L * 0.66, cy),
		Size = UDim2.fromOffset(rocketH * 0.46, rocketH * 0.46),
	})
	round(window)
end

-- 폭발: 번쩍임 + 불덩이 4개 + 파편 + 남는 X 표시
local function buildBlast()
	wreck = Ui.frame(shaker, "ChaseWreck", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(L * 0.36, L * 0.36),
		ZIndex = 6,
		Visible = false,
	})
	for i, deg in ipairs({ 45, -45 }) do
		solid(wreck, "ChaseWreckStroke" .. i, C.Red, 6, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, math.max(3, math.floor(L * 0.06))),
			Rotation = deg,
		})
	end
	-- { 가로, 세로 (로켓 길이 배), 최대 지름 (로켓 길이 배), 시작 지연(초), 길이(초), 색 } — 연기(어두움)가 맨 아래
	local specs = {
		{ 0.02, 0.16, 1.3, 0.15, 1.6, Color3.fromRGB(70, 60, 64) },
		{ 0.18, 0.1, 0.85, 0.1, 1.1, Color3.fromRGB(230, 64, 40) },
		{ -0.16, -0.12, 0.9, 0.05, 0.95, C.Orange },
		{ 0, 0, 1.1, 0, 0.7, Color3.fromRGB(255, 226, 110) },
	}
	for i, spec in ipairs(specs) do
		local ball = solid(shaker, "ChaseFireball" .. i, spec[6], 6 + i, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
		round(ball)
		table.insert(fireballs, { frame = ball, dx = spec[1], dy = spec[2], size = spec[3], delay = spec[4], duration = spec[5] })
	end
	local colors = { HULL, HULL, FIN, C.Orange, FLAME_CORE }
	for i = 1, DEBRIS_COUNT do
		local piece = solid(shaker, "ChaseDebris" .. i, colors[(i - 1) % #colors + 1], 9, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
		})
		table.insert(debris, { frame = piece, vx = 0, vy = 0, spin = 0, size = 0 })
	end
	flash = solid(shaker, "ChaseFlash", Color3.fromRGB(255, 250, 230), 11, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
	round(flash)
end

-- 최고 기록선: 이 서버의 최고 기록 자리 (로켓 꼬리가 넘으면 신기록)
local function buildRecord(font: number)
	recordLine = solid(shaker, "ChaseRecord", C.Yellow, 4, {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(math.max(2, math.floor(L * 0.03)), height - strip * 2),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	recordLabel = Ui.label(shaker, "ChaseRecordName", "", font, {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(font * 5, strip),
		TextColor3 = C.Yellow,
		ZIndex = 4,
		Visible = false,
	})
end

local function reset()
	ended = nil
	endKm = 0
	blasted = false
	shownGap = maxGap
end

local function startBlast()
	for _, piece in ipairs(debris) do
		local angle = random:NextNumber() * math.pi * 2
		local speed = L * (0.9 + random:NextNumber() * 1.6)
		piece.vx = math.cos(angle) * speed
		piece.vy = math.sin(angle) * speed
		piece.spin = (random:NextNumber() - 0.5) * 900
		piece.size = L * (0.04 + random:NextNumber() * 0.08)
	end
end

-- parent: 추격 화면을 그릴 틀, w/h: 그 틀의 픽셀 크기
function ChaseView.build(parent: GuiObject, w: number, h: number)
	width = w
	height = h
	strip = math.clamp(math.floor(h * 0.15), 22, 40)
	local font = math.clamp(math.floor(strip * 0.78), 17, 30)
	local band = h - strip * 2
	midY = strip + band / 2
	L = math.clamp(math.min(w * 0.1, band * 1.1), 40, 140)
	rocketH = L * 0.3
	startX = L * 2.2
	endX = w - L * 1.15
	maxGap = L * 1.9
	shownGap = maxGap

	local frame = Ui.frame(parent, "Chase", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BACK,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	})
	shaker = Ui.frame(frame, "ChaseShake", { Size = UDim2.fromScale(1, 1) })
	buildTrack(font)
	buildPlanet()
	buildWave()
	buildRecord(font)
	buildRocket()
	buildBlast()
	root = frame

	State.on("FlightEnd", function(info: any)
		if type(info) ~= "table" then
			return
		end
		endKm = if type(info.km) == "number" then info.km else State.number("Km")
		ended = if info.escaped then "escaped" else "caught"
	end)
	State.on("Launched", function()
		launchedAt = os.clock()
	end)
end

local function updatePlanet(clock: number, burning: boolean)
	local id = State.text("Planet")
	if id ~= planetId then
		planetId = id
		local planet = Planets.get(id)
		planetBody.BackgroundColor3 = planet.Ground[#planet.Ground]:Lerp(BACK, 0.35)
		planetGlow.Color = planet.Crack
		for _, crack in ipairs(cracks) do
			crack.BackgroundColor3 = planet.Crack
		end
	end
	local launchGlow = if launchedAt > 0 then math.max(0, 1 - (clock - launchedAt) / LAUNCH_GLOW_TIME) else 0
	local pulse = 0.5 + 0.5 * math.sin(clock * (if burning then 5 else 2.4))
	planetGlow.Transparency = math.clamp(0.5 - 0.35 * pulse - 0.5 * launchGlow, 0, 1)
	planetGlow.Thickness = math.max(2, L * (0.03 + 0.05 * launchGlow))
	for i, crack in ipairs(cracks) do
		local flicker = 0.5 + 0.5 * math.sin(clock * 3 + i * 2.1)
		crack.BackgroundTransparency = math.clamp(0.55 - 0.4 * flicker - 0.5 * launchGlow, 0, 1)
	end
end

local function updateWave(front: number, show: boolean, crisis: boolean, clock: number)
	wallBody.Visible = show
	wallGlow.Visible = show
	wallFront.Visible = show
	if not show then
		for _, ripple in ipairs(ripples) do
			ripple.Visible = false
		end
		return
	end
	wallBody.Size = UDim2.fromOffset(front + L * 0.2, height)
	wallGlow.Position = UDim2.fromOffset(front, 0)
	wallFront.Position = UDim2.fromOffset(front, 0)
	local pulse = if crisis then 0.5 + 0.5 * math.sin(clock * 9) else 0
	wallGlow.BackgroundTransparency = 0.35 - 0.25 * pulse
	-- 물결 선: 면 안쪽 깊은 곳에서 생겨 앞으로 밀려가며 밝아짐
	local depth = L * RIPPLE_SPAN
	for i, ripple in ipairs(ripples) do
		local u = ((i - 1) / RIPPLE_COUNT + clock * RIPPLE_SPEED) % 1
		local x = front - depth * (1 - u)
		ripple.Visible = x > 0
		ripple.Position = UDim2.fromOffset(x, 0)
		ripple.BackgroundTransparency = 0.25 + 0.7 * (1 - u)
	end
end

local function updateRocket(tail: number, phase: string, flying: boolean, crisis: boolean, clock: number)
	local shown = not blasted
	rocket.Visible = shown
	if not shown then
		return
	end
	local bob = if flying then math.sin(clock * 3.1) * L * 0.015 else 0
	rocket.Position = UDim2.fromOffset(tail, midY + bob)
	-- 불꽃: 비행 중·탈출 후에는 켬, 카운트다운 마지막 2초에는 작게 (점화)
	local ignite = 0
	if flying or ended == "escaped" then
		ignite = 1
	elseif phase == "Countdown" and ended == nil and State.number("LaunchAt") - State.now() <= 2 then
		ignite = 0.45
	end
	flame.Visible = ignite > 0
	flameCore.Visible = ignite > 0
	if ignite > 0 then
		local flicker = 0.8 + 0.4 * math.clamp(0.5 + math.noise(clock * 13, 2.7), 0, 1)
		flame.Size = UDim2.fromOffset(L * 0.36 * flicker * ignite, rocketH * 0.62)
		flameCore.Size = UDim2.fromOffset(L * 0.2 * flicker * ignite, rocketH * 0.3)
	end
	-- 위기: 선체가 붉게 깜박임
	local color = HULL
	if crisis then
		color = HULL:Lerp(C.Red, 0.2 + 0.4 * (0.5 + 0.5 * math.sin(clock * 9)))
	end
	hull.BackgroundColor3 = color
	nose.BackgroundColor3 = color
end

local function updateBlast(cx: number, clock: number)
	local e = if blasted then clock - blastAt else -1
	local flashOn = e >= 0 and e < FLASH_TIME
	flash.Visible = flashOn
	if flashOn then
		local k = e / FLASH_TIME
		local size = L * (0.5 + 2 * k)
		flash.Position = UDim2.fromOffset(cx, midY)
		flash.Size = UDim2.fromOffset(size, size)
		flash.BackgroundTransparency = k
	end
	for _, ball in ipairs(fireballs) do
		local k = if e >= 0 then (e - ball.delay) / ball.duration else -1
		local on = k >= 0 and k < 1
		ball.frame.Visible = on
		if on then
			local size = ball.size * L * (0.3 + 0.7 * (1 - (1 - k) * (1 - k)))
			ball.frame.Position = UDim2.fromOffset(cx + (ball.dx + k * 0.25) * L, midY + ball.dy * L)
			ball.frame.Size = UDim2.fromOffset(size, size)
			ball.frame.BackgroundTransparency = 0.05 + 0.95 * k * k
		end
	end
	-- 파편: 바깥으로 튀며 느려지고, 충격파에 밀려 오른쪽으로 흘러감
	local debrisOn = e >= 0 and e < BLAST_TIME
	local spread = if debrisOn then (1 - math.exp(-e * 2.2)) / 2.2 else 0
	for _, piece in ipairs(debris) do
		piece.frame.Visible = debrisOn
		if debrisOn then
			piece.frame.Position = UDim2.fromOffset(cx + piece.vx * spread + e * L * 0.35, midY + piece.vy * spread)
			piece.frame.Size = UDim2.fromOffset(piece.size, piece.size * 0.6)
			piece.frame.Rotation = piece.spin * e
			piece.frame.BackgroundTransparency = (e / BLAST_TIME) ^ 2
		end
	end
	local wreckOn = e >= FLASH_TIME * 0.5
	wreck.Visible = wreckOn
	if wreckOn then
		wreck.Position = UDim2.fromOffset(cx, midY)
	end
	if e >= 0 and e < SHAKE_TIME then
		shaking = true
		local amp = L * 0.07 * (1 - e / SHAKE_TIME)
		shaker.Position = UDim2.fromOffset(math.noise(e * 37, 1.3) * 2 * amp, math.noise(e * 37, 7.9) * 2 * amp)
	elseif shaking then
		shaking = false
		shaker.Position = UDim2.fromOffset(0, 0)
	end
end

function ChaseView.update(dt: number)
	if root == nil then
		return
	end
	local clock = os.clock()
	local phase = State.phase()
	if phase ~= lastPhase then
		lastPhase = phase
		if phase ~= "Results" then
			reset() -- 새 판이나 새 비행: 지난 비행의 끝 모습을 지움
			sawFlight = phase == "Flight"
		end
	end
	-- 비행 끝 신호보다 정산 단계가 먼저 보이면 상태 값으로 끝을 정함.
	-- 비행을 봤으면 터지는 연출을 그대로 하고, 정산 중에 들어온 사람에게는 터진 뒤 모습만 보여 줌.
	if phase == "Results" and ended == nil then
		endKm = State.number("Km")
		ended = if State.flag("Escaped") then "escaped" else "caught"
		if ended == "caught" and not sawFlight then
			shownGap = 0
			blasted = true
			blastAt = clock - BLAST_TIME - SWEEP_TIME
		end
	end

	local flying = phase == "Flight" and ended == nil
	local crisis = flying and State.flag("Crisis")
	local km = 0
	if ended ~= nil then
		km = endKm
	elseif phase == "Flight" then
		km = State.flight.km
	end
	local tail = tailX(km)

	-- 꼬리와 면 사이 간격
	if ended == "caught" then
		if not blasted then
			-- 따라잡힘: 면이 꼬리에 닿는 순간 터짐 (면이 떨어져 있었으면 빠르게 달려옴)
			shownGap = math.max(0, shownGap - math.max(shownGap * 10, RUSH * L) * dt)
			if shownGap <= 0.5 then
				shownGap = 0
				blasted = true
				blastAt = clock
				startBlast()
			end
		end
	elseif ended == "escaped" then
		shownGap += (maxGap - shownGap) * math.min(1, dt * 1.5)
	else
		local target = if phase == "Flight" then gapFor(State.number("Eta")) else maxGap
		shownGap += (target - shownGap) * math.min(1, dt * GAP_FOLLOW)
	end
	local front = tail - shownGap
	if blasted then
		local k = math.clamp((clock - blastAt) / SWEEP_TIME, 0, 1)
		front = tail + SWEEP_LENGTH * L * (1 - (1 - k) * (1 - k))
	end

	updatePlanet(clock, phase == "Flight" or phase == "Results")
	-- 충격파는 발사한 뒤에만 (발사 전에는 아직 행성이 터지지 않음)
	updateWave(front, (phase == "Flight" or phase == "Results") and front > 1, crisis, clock)
	updateRocket(tail, phase, flying, crisis, clock)
	updateBlast(tail + L * 0.5, clock)

	local best = State.number("BestKm")
	local showRecord = best > 0
	recordLine.Visible = showRecord
	recordLabel.Visible = showRecord
	if showRecord then
		local x = tailX(best)
		recordLine.Position = UDim2.fromOffset(x, strip)
		recordLabel.Position = UDim2.fromOffset(x, 0)
		recordLabel.Text = if km > best then "신기록!" else "최고 기록"
	end
end

return ChaseView
