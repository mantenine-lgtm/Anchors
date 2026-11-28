-- 엔딩 (Nick 11-28): 충격파에 잡히면(탈출이 아니면) 로켓에 탄 모두가 바깥에서 로켓이 터지는 장면을 봅니다.
-- 서버는 잡힌 시각(RoundState 속성 CaughtAt)을 알리고 비행 페이즈를 Config.Ending.Seconds 만큼 더 둔 뒤 정산으로 넘어갑니다.
--  · 카메라: CameraRig 가 엔딩·정산 동안 바깥 엔딩 카메라로 강제로 옮김 (시점 버튼 숨김)
--  · 충격파 면: Backdrop 이 로켓 꼬리 바로 아래(Config.Ending.WaveY)에 둠. 면이 꼬리에 닿으면 터짐 (전광판 추격 화면과 같음)
--  · 0 ~ BlastAt 초: 엔진음이 끊긴 채 조용하고, 꼬리부터 불이 붙음
--  · BlastAt 초: 번쩍임·흔들림·폭발음(EndingBlast 알림을 Hud·CameraRig·Sfx 가 받음) + 로켓과 탄 사람을 내 화면에서 숨기고,
--    아래에서 위로 번지는 불덩이 기둥, 가운데 섬광, 파편(달아올랐다 식으며 충격파 면으로 떨어짐), 불티, 연기, 충격파 면 위로 퍼지는 고리
--  · 정산 동안: 연기가 걷히고 빈자리만 남음. 엔딩이 끝나면(다음 판·내림) 숨긴 것을 모두 되돌림
-- 파편이 튀는 모양은 잡힌 시각으로 정해서 모든 사람에게 같게 보입니다.
-- 전부 내 화면에서만 만들고 숨기는 것이라 서버·다른 사람에게 영향이 없습니다.
-- 폰 사양(프로젝트 규칙): 파트 37개를 미리 만들어 두고 판마다 다시 씀(파티클·빛 없음). 연출이 끝나면(약 5초) 매 프레임 일을 하지 않고,
-- 숨긴 것은 1초마다 한 번 다시 확인만 합니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local State = require(script.Parent:WaitForChild("State"))

local Ending = {}

local E = Config.Ending
local W = Config.World
local R = W.HullRadius
local player = Players.LocalPlayer

local AXIS_LOW = W.RocketBaseY + 14 -- 불덩이 기둥 아래 끝 (엔진 바로 위)
local AXIS_HIGH = W.RocketTopY + 40 -- 위 끝 (코 가운데쯤)
local CENTER_Y = (W.CabinFloorY + W.CabinCeilY) / 2 -- 가운데 섬광 (선실)
local TAIL_FIRES = 2 -- 잡히자마자 꼬리에서 붙는 불
local FIRE_COUNT = 7 -- 불덩이 (앞의 TAIL_FIRES 개는 꼬리 불, 나머지는 터질 때)
local SMOKE_COUNT = 6
local DEBRIS_COUNT = 14
local EMBER_COUNT = 8
local GRAVITY = 62 -- 파편이 떨어지는 가속(스터드/초²)
local EMBER_GRAVITY = 40
local LATE = 1.5 -- 터질 시각보다 이만큼 넘게 늦게 처음 보면(정산 중에 들어옴 등) 터지는 장면 없이 빈자리만
local RESCAN = 1 -- 숨긴 것을 다시 확인하는 간격(초)
local END_AFTER = E.BlastAt + 4.8 -- 잡힌 뒤 이 시각이 지나면 연출 파트를 모두 숨기고 멈춤 (가장 늦은 파편까지)
local CAMERA_CLEAR = math.rad(25) -- 엔딩 카메라 쪽으로 곧장 날아오는 파편은 옆으로 돌림 (화면을 덮지 않게)

local FIRE_HOT = Color3.fromRGB(255, 244, 196)
local FIRE_MID = Color3.fromRGB(255, 142, 46)
local FIRE_DARK = Color3.fromRGB(150, 38, 18)
local FLASH = Color3.fromRGB(255, 252, 236)
local SMOKE_DARK = Color3.fromRGB(58, 52, 50)
local SMOKE_LIGHT = Color3.fromRGB(96, 90, 88)
local RING = Color3.fromRGB(255, 236, 200)
local EMBER_HOT = Color3.fromRGB(255, 196, 90)
local EMBER_COOL = Color3.fromRGB(255, 84, 30)
local HOT_METAL = Color3.fromRGB(255, 136, 58)
-- 선체 강철·용접선·그을음 (RocketShell 과 같은 색)
local DEBRIS_COLORS = { Color3.fromRGB(178, 182, 188), Color3.fromRGB(129, 132, 137), Color3.fromRGB(43, 42, 44) }
-- 파편 모양: 휜 선체 판·쐐기·덩어리 (기본 크기, 판마다 0.7~1.3배. 엔딩 카메라에서 600 스터드쯤 떨어져도 보이게 큼직하게)
local DEBRIS_SHAPES = {
	{ class = "Part", size = Vector3.new(3, R * 0.75, R * 1.0) },
	{ class = "WedgePart", size = Vector3.new(3, R * 0.7, R * 0.85) },
	{ class = "Part", size = Vector3.new(R * 0.35, R * 0.35, R * 0.35) },
}

type Piece = {
	part: BasePart,
	kind: string, -- "core" 섬광 | "fire" 불덩이 | "smoke" 연기 | "debris" 파편 | "ember" 불티 | "ring" 고리
	start: number, -- 잡힌 뒤 나타나는 시각(초)
	life: number, -- 나타난 뒤 사는 시간(초)
	grow: number, -- 공이 가장 커지기까지 걸리는 시간(초)
	origin: Vector3,
	velocity: Vector3,
	size: number, -- 공: 가장 클 때 지름
	gravity: number,
	axis: Vector3, -- 도는 축
	spin: number, -- 도는 빠르기(라디안/초)
	tilt: CFrame, -- 처음 방향
	color: Color3,
	shown: boolean,
}

local container: Folder
local core: Piece
local ring: Piece
local fires: { Piece } = {}
local smokes: { Piece } = {}
local debris: { Piece } = {}
local embers: { Piece } = {}
local all: { Piece } = {}

local runningFor = 0 -- 지금 엔딩 중인 판의 잡힌 시각 (0 = 엔딩 아님)
local startClock = 0 -- 잡힌 순간의 os.clock() (늦게 받았으면 그만큼 앞당김)
local blasted = false
local animating = false
local rescanAt = 0
local hidden: { [Instance]: number } = {} -- 숨긴 파트·데칼 -> 원래 LocalTransparencyModifier
local disabled: { [Instance]: boolean } = {} -- 끈 빛·파티클·화면(SurfaceGui 등)

-- ------------------------------------------------------------ 만들기
local function newPiece(kind: string, class: string, name: string, material: Enum.Material, shape: Enum.PartType?): Piece
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Transparency = 1
	if shape and part:IsA("Part") then
		part.Shape = shape
	end
	part.Parent = container
	local piece: Piece = {
		part = part,
		kind = kind,
		start = 0,
		life = 1,
		grow = 0.3,
		origin = Vector3.zero,
		velocity = Vector3.zero,
		size = 1,
		gravity = 0,
		axis = Vector3.yAxis,
		spin = 0,
		tilt = CFrame.new(),
		color = FIRE_MID,
		shown = false,
	}
	table.insert(all, piece)
	return piece
end

local function build()
	container = Instance.new("Folder")
	container.Name = "RoflyEnding"
	container.Parent = Workspace
	core = newPiece("core", "Part", "BlastCore", Enum.Material.Neon, Enum.PartType.Ball)
	for i = 1, FIRE_COUNT do
		fires[i] = newPiece("fire", "Part", "BlastFire", Enum.Material.Neon, Enum.PartType.Ball)
	end
	for i = 1, SMOKE_COUNT do
		smokes[i] = newPiece("smoke", "Part", "BlastSmoke", Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	for i = 1, DEBRIS_COUNT do
		local shape = DEBRIS_SHAPES[1 + (i - 1) % #DEBRIS_SHAPES]
		debris[i] = newPiece("debris", shape.class, "BlastDebris", Enum.Material.Metal, nil)
	end
	for i = 1, EMBER_COUNT do
		embers[i] = newPiece("ember", "Part", "BlastEmber", Enum.Material.Neon, nil)
	end
	ring = newPiece("ring", "Part", "BlastRing", Enum.Material.Neon, Enum.PartType.Cylinder)
end

-- ------------------------------------------------------------ 이번 판 폭발 계획 (잡힌 시각이 같으면 모두 같은 모양)
local function randomUnit(rng: Random): Vector3
	for _ = 1, 8 do
		local v = Vector3.new(rng:NextNumber() * 2 - 1, rng:NextNumber() * 2 - 1, rng:NextNumber() * 2 - 1)
		if v.Magnitude > 0.1 and v.Magnitude <= 1 then
			return v.Unit
		end
	end
	return Vector3.yAxis
end

local function randomTilt(rng: Random): CFrame
	return CFrame.Angles(rng:NextNumber() * math.pi * 2, rng:NextNumber() * math.pi * 2, rng:NextNumber() * math.pi * 2)
end

local function plan(caughtAt: number)
	local rng = Random.new(math.floor(caughtAt * 1000) % 2147483647)
	local cameraAngle = math.atan2(E.Camera[3], E.Camera[1]) -- 엔딩 카메라가 있는 쪽 (x, z 평면)

	local toCamera = Vector3.new(E.Camera[1], 0, E.Camera[3]).Unit

	-- 가운데 섬광: 터지는 순간 선실에서 확 커졌다 사라짐
	core.start = E.BlastAt
	core.life = 0.5
	core.size = R * 5
	core.origin = Vector3.new(0, CENTER_Y, 0)

	-- 불덩이
	--  · 꼬리 불: 잡히자마자 꼬리에서 붙어 터질 때까지 커짐. 선체보다 굵고 엔딩 카메라 쪽으로 조금 나와 있어 선체에 가려지지 않음
	--  · 터지는 불: 터질 때 아래에서 위로 차례로 번지며 옆으로도 퍼지고, 선체보다 훨씬 크게 부풂
	for i, piece in ipairs(fires) do
		if i <= TAIL_FIRES then
			piece.velocity = Vector3.new(0, 10 + rng:NextNumber() * 8, 0)
			piece.origin = toCamera * (R * 0.45) + Vector3.new(0, AXIS_LOW + (i - 1) * R * 0.9, 0)
			piece.start = (i - 1) * 0.14
			piece.size = R * 2 * (1.3 + 0.15 * (i - 1))
			piece.grow = math.max(0.1, E.BlastAt + 0.15 - piece.start)
			piece.life = E.BlastAt + 1.3 - piece.start
		else
			local u = (i - TAIL_FIRES - 1) / math.max(1, FIRE_COUNT - TAIL_FIRES - 1)
			local angle = rng:NextNumber() * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			-- 옆으로도 번져 기둥이 아닌 뭉게뭉게 퍼지는 불덩이로
			piece.origin = out * (rng:NextNumber() * R * 0.7) + Vector3.new(0, AXIS_LOW + (AXIS_HIGH - AXIS_LOW) * u, 0)
			piece.velocity = out * (12 + rng:NextNumber() * 18) + Vector3.new(0, 10 + rng:NextNumber() * 10, 0)
			piece.start = E.BlastAt + (i - TAIL_FIRES - 1) * 0.035
			piece.size = R * 2 * (1.8 + rng:NextNumber() * 0.5)
			piece.grow = 0.3
			piece.life = 1.25 + rng:NextNumber() * 0.25
		end
	end

	-- 연기: 불덩이가 사그라들 무렵 그 자리를 덮으며 커지고 천천히 오르다 걷힘
	for i, piece in ipairs(smokes) do
		local u = (i - 0.5) / SMOKE_COUNT
		local angle = rng:NextNumber() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		piece.origin = out * (R * 0.7) + Vector3.new(0, AXIS_LOW + 10 + (AXIS_HIGH - AXIS_LOW) * u, 0)
		piece.velocity = out * (5 + rng:NextNumber() * 7) + Vector3.new(0, 6 + rng:NextNumber() * 4, 0)
		piece.start = E.BlastAt + 0.08 + i * 0.03
		piece.life = 3.4 + rng:NextNumber() * 0.6
		piece.size = R * 2 * (2.0 + rng:NextNumber() * 0.5)
	end

	-- 파편: 선체 둘레에서 바깥·위로 튀고 돌면서 떨어져 충격파 면에 잠김
	for i, piece in ipairs(debris) do
		local angle = rng:NextNumber() * math.pi * 2
		local diff = (angle - cameraAngle + math.pi) % (math.pi * 2) - math.pi
		if math.abs(diff) < CAMERA_CLEAR then
			angle += if diff >= 0 then CAMERA_CLEAR * 2 else -CAMERA_CLEAR * 2
		end
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local y = AXIS_LOW + rng:NextNumber() * (AXIS_HIGH - AXIS_LOW)
		piece.origin = out * (R * 0.8) + Vector3.new(0, y, 0)
		piece.velocity = out * (70 + rng:NextNumber() * 70) + Vector3.new(0, 20 + rng:NextNumber() * 60, 0)
		piece.gravity = GRAVITY
		piece.axis = randomUnit(rng)
		piece.spin = (2 + rng:NextNumber() * 4) * (if rng:NextNumber() < 0.5 then -1 else 1)
		piece.tilt = randomTilt(rng)
		piece.start = E.BlastAt + rng:NextNumber() * 0.05
		piece.life = END_AFTER - E.BlastAt - 0.1
		piece.color = DEBRIS_COLORS[1 + (i - 1) % #DEBRIS_COLORS]
		local shape = DEBRIS_SHAPES[1 + (i - 1) % #DEBRIS_SHAPES]
		piece.part.Size = shape.size * (0.7 + rng:NextNumber() * 0.6)
	end

	-- 불티: 가운데에서 사방(위쪽이 많게)으로 빠르게 튀고 금방 식음
	for _, piece in ipairs(embers) do
		local dir = randomUnit(rng)
		dir = Vector3.new(dir.X, math.abs(dir.Y) * 0.8 + 0.1, dir.Z).Unit
		piece.origin = Vector3.new(0, CENTER_Y + (rng:NextNumber() - 0.5) * 80, 0)
		piece.velocity = dir * (120 + rng:NextNumber() * 80)
		piece.gravity = EMBER_GRAVITY
		piece.axis = randomUnit(rng)
		piece.spin = 6 + rng:NextNumber() * 6
		piece.tilt = randomTilt(rng)
		piece.start = E.BlastAt + rng:NextNumber() * 0.08
		piece.life = 0.9 + rng:NextNumber() * 0.6
		local size = 2 + rng:NextNumber() * 1.4
		piece.part.Size = Vector3.new(size, size, size)
	end

	-- 충격파 면 위로 퍼지는 고리
	ring.start = E.BlastAt + 0.03
	ring.life = 1.2
	ring.origin = Vector3.new(0, E.WaveY + 0.8, 0)
end

-- ------------------------------------------------------------ 그리기 (모두 잡힌 뒤 흐른 시간 t 로 계산: 프레임이 끊겨도 같은 자리)
local function hidePiece(piece: Piece)
	if piece.shown then
		piece.shown = false
		piece.part.Transparency = 1
	end
end

local function hidePieces()
	for _, piece in ipairs(all) do
		hidePiece(piece)
	end
end

local function easeOut(x: number): number
	local inv = 1 - math.clamp(x, 0, 1)
	return 1 - inv * inv * inv
end

local function showBall(piece: Piece, position: Vector3, diameter: number, transparency: number, color: Color3)
	local part = piece.part
	piece.shown = true
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(position)
	part.Transparency = transparency
	part.Color = color
end

local function stepFire(piece: Piece, tau: number)
	local k = easeOut(tau / piece.grow)
	local life = piece.life
	local fade = math.clamp((tau - life * 0.45) / (life * 0.55), 0, 1)
	local age = tau / life
	local color = if age < 0.35 then FIRE_HOT:Lerp(FIRE_MID, age / 0.35) else FIRE_MID:Lerp(FIRE_DARK, (age - 0.35) / 0.65)
	showBall(piece, piece.origin + piece.velocity * tau, piece.size * (0.25 + 0.75 * k), 0.04 + 0.96 * fade, color)
end

local function stepSmoke(piece: Piece, tau: number)
	local age = tau / piece.life
	local k = 1 - (1 - age) * (1 - age)
	showBall(piece, piece.origin + piece.velocity * tau, piece.size * (0.3 + 0.7 * k), 0.3 + 0.7 * age ^ 1.6, SMOKE_DARK:Lerp(SMOKE_LIGHT, age))
end

-- 파편·불티: 던진 물체처럼 날아가며 돎. 충격파 면 아래로 잠기면 사라짐
local function stepThrown(piece: Piece, tau: number, color: Color3, transparency: number): boolean
	local position = piece.origin + piece.velocity * tau - Vector3.new(0, 0.5 * piece.gravity * tau * tau, 0)
	if position.Y < E.WaveY - 4 then
		return false
	end
	local part = piece.part
	piece.shown = true
	part.CFrame = CFrame.new(position) * piece.tilt * CFrame.fromAxisAngle(piece.axis, piece.spin * tau)
	part.Transparency = transparency
	part.Color = color
	return true
end

local function step(t: number)
	for _, piece in ipairs(all) do
		local tau = t - piece.start
		if tau < 0 or tau >= piece.life then
			hidePiece(piece)
			continue
		end
		local kind = piece.kind
		if kind == "core" then
			local diameter = piece.size * easeOut(tau / 0.12)
			showBall(piece, piece.origin, math.max(diameter, 1), if tau < 0.1 then 0 else math.clamp((tau - 0.1) / 0.4, 0, 1), FLASH)
		elseif kind == "ring" then
			local age = tau / piece.life
			local diameter = R * 2 + R * 14 * (1 - (1 - age) * (1 - age))
			local part = piece.part
			piece.shown = true
			part.Size = Vector3.new(0.6, diameter, diameter)
			part.CFrame = CFrame.new(piece.origin) * CFrame.Angles(0, 0, math.pi / 2)
			part.Transparency = 0.15 + 0.85 * age
			part.Color = RING
		elseif kind == "fire" then
			stepFire(piece, tau)
		elseif kind == "smoke" then
			stepSmoke(piece, tau)
		elseif kind == "debris" then
			local heat = math.clamp((tau - 0.15) / 0.9, 0, 1)
			local fade = math.clamp((tau - (piece.life - 0.4)) / 0.4, 0, 1)
			if not stepThrown(piece, tau, HOT_METAL:Lerp(piece.color, heat), fade) then
				hidePiece(piece)
			end
		else
			local age = tau / piece.life
			local fade = math.clamp((age - 0.55) / 0.45, 0, 1)
			if not stepThrown(piece, tau, EMBER_HOT:Lerp(EMBER_COOL, age), fade) then
				hidePiece(piece)
			end
		end
	end
end

-- ------------------------------------------------------------ 로켓과 탄 사람 숨기기 / 되돌리기
local function hideInstance(item: Instance)
	local obj: any = item
	if item:IsA("BasePart") or item:IsA("Decal") then -- Texture 도 Decal
		local current = obj.LocalTransparencyModifier
		if current < 1 then
			if hidden[item] == nil then
				hidden[item] = current
			end
			obj.LocalTransparencyModifier = 1
		end
	elseif item:IsA("Light") or item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail")
		or item:IsA("Highlight") or item:IsA("SurfaceGui") or item:IsA("BillboardGui")
	then
		if obj.Enabled then
			disabled[item] = true
			obj.Enabled = false
			if item:IsA("ParticleEmitter") then
				obj:Clear()
			end
		end
	end
end

-- 숨길 것: 로켓 모델 전체(선체·선실·전광판·조명·봇)와 로켓에 탄 사람(승무원·관전자) 캐릭터
local function targets(): { Instance }
	local out: { Instance } = {}
	local rofly = Workspace:FindFirstChild("Rofly")
	local rocket = rofly and rofly:FindFirstChild("Rocket")
	if rocket then
		table.insert(out, rocket)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local role = other:GetAttribute("Role")
		local character = other.Character
		if character and (role == "Crew" or role == "Ghost") then
			table.insert(out, character)
		end
	end
	return out
end

local function hideTargets()
	local roots = targets()
	for _, root in ipairs(roots) do
		for _, item in ipairs(root:GetDescendants()) do
			hideInstance(item)
		end
	end
	-- 전광판 화면처럼 PlayerGui 에 두고 로켓 파트에 붙인 화면(SurfaceGui·BillboardGui)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("SurfaceGui") or gui:IsA("BillboardGui") then
				local adornee = gui.Adornee
				if adornee then
					for _, root in ipairs(roots) do
						if adornee:IsDescendantOf(root) then
							hideInstance(gui)
							break
						end
					end
				end
			end
		end
	end
end

local function restore()
	for item, value in pairs(hidden) do
		if item.Parent then
			local obj: any = item
			obj.LocalTransparencyModifier = value
		end
	end
	table.clear(hidden)
	for item in pairs(disabled) do
		if item.Parent then
			local obj: any = item
			obj.Enabled = true
		end
	end
	table.clear(disabled)
	State.wrecked = false
end

local function wreck(clock: number)
	State.wrecked = true
	hideTargets()
	rescanAt = clock + RESCAN
end

-- ------------------------------------------------------------ 엔딩 시작·끝
local function finish()
	runningFor = 0
	blasted = false
	animating = false
	hidePieces()
	restore()
end

local function begin(caughtAt: number, clock: number)
	if runningFor ~= 0 then
		finish()
	end
	runningFor = caughtAt
	local elapsed = math.max(0, State.now() - caughtAt)
	startClock = clock - elapsed
	plan(caughtAt)
	if elapsed > E.BlastAt + LATE then
		-- 정산 중에 들어왔거나 한참 늦게 받음: 터지는 장면 없이 빈자리만 (번쩍임·폭발음 없음)
		blasted = true
		animating = false
		wreck(clock)
	else
		blasted = false
		animating = true
	end
end

-- 지금 엔딩 중인지, 터졌는지 (검사·디버그용)
function Ending.status(): (boolean, boolean)
	return runningFor ~= 0, blasted
end

function Ending.init()
	build()
end

function Ending.update(_dt: number)
	local caughtAt = State.caughtAt()
	local active = caughtAt > 0 and State.caught() and State.aboard()
	if not active then
		if runningFor ~= 0 then
			finish()
		end
		return
	end
	local clock = os.clock()
	if runningFor ~= caughtAt then
		begin(caughtAt, clock)
	end
	local t = clock - startClock
	if not blasted and t >= E.BlastAt then
		blasted = true
		wreck(clock)
		State.emit("EndingBlast")
	end
	if blasted and clock >= rescanAt then
		rescanAt = clock + RESCAN
		hideTargets()
	end
	if animating then
		if t >= END_AFTER then
			animating = false
			hidePieces()
		else
			step(t)
		end
	end
end

-- 검사용
Ending._internal = {
	pieces = all,
	core = function(): Piece
		return core
	end,
	ring = function(): Piece
		return ring
	end,
	fires = fires,
	smokes = smokes,
	debris = debris,
	embers = embers,
	hiddenCount = function(): number
		local n = 0
		for _ in pairs(hidden) do
			n += 1
		end
		return n
	end,
	endAfter = END_AFTER,
}

return Ending
