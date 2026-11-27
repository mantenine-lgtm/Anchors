-- 회색 상자 월드를 코드로 만듭니다: 발사 광장, 로켓, 선실(외창·전광판), 좌석.
-- 맵을 Studio 에서 따로 만들지 않아도 Play 만 누르면 생깁니다.
-- 로켓은 원점에 고정이고, 비행 중에는 클라이언트가 배경(행성·발사 광장·별)을 움직입니다.
-- 광장 밖의 둥근 행성과 지형지물은 판마다 바뀌며 클라이언트가 만듭니다(client/Planet.luau).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local W = Config.World

local World = {}

local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_DARK = Color3.fromRGB(120, 126, 136)
local DARK = Color3.fromRGB(52, 56, 64)
local FLOOR = Color3.fromRGB(70, 74, 84)
local GLASS = Color3.fromRGB(170, 215, 255)
local PLAZA = Color3.fromRGB(96, 100, 110)
local PLAZA_EDGE = Color3.fromRGB(62, 66, 76)
local MARK = Color3.fromRGB(255, 196, 60)
local RIM_LIGHT = Color3.fromRGB(90, 230, 255)
local TANK = Color3.fromRGB(226, 230, 236)
local STRIPE = Color3.fromRGB(255, 120, 40)
local SEAT = Color3.fromRGB(78, 84, 98)
local CUSHION = Color3.fromRGB(40, 44, 54)
local GOLD = Color3.fromRGB(255, 205, 60)
local TOWER = Color3.fromRGB(120, 60, 54)

-- 발사 광장: 행성 꼭대기 면(가장자리까지 약 187 스터드) 안에 들어가는 둥근 판. 윗면 y = 0
local PLAZA_RADIUS = 150

local rocket: Model? = nil
local seatsFolder: Folder? = nil
local seatCFrames: { CFrame } = {}

-- 고정된 상자 하나
local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

-- 세로로 선 원기둥 (y0 ~ y1)
local function cylinder(parent: Instance, name: string, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = Vector3.new(y1 - y0, radius * 2, radius * 2)
	p.CFrame = CFrame.new(0, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = parent
	return p
end

-- 세로 원기둥을 (x, z) 자리에
local function post(parent: Instance, name: string, x: number, z: number, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material?): Part
	local p = cylinder(parent, name, radius, y0, y1, color, material)
	p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

-- 각도(도)와 반지름으로 로켓 둘레의 한 점. 0도 = +Z(외창 쪽), 180도 = -Z(좌석 쪽)
local function ringPoint(angleDeg: number, radius: number, y: number): Vector3
	local theta = math.rad(angleDeg)
	return Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius)
end

-- 둘레 벽 한 칸 (두께 방향이 바깥을 향함)
local function wallPanel(parent: Instance, name: string, angleDeg: number, y0: number, y1: number, color: Color3, material: Enum.Material): Part
	local radius = (W.CabinRadius + W.HullRadius) / 2
	local thickness = W.HullRadius - W.CabinRadius
	local width = 2 * W.HullRadius * math.tan(math.pi / W.WallSegments) + 0.05
	local cframe = CFrame.new(ringPoint(angleDeg, radius, (y0 + y1) / 2)) * CFrame.Angles(0, math.rad(angleDeg), 0)
	local p = block(parent, name, Vector3.new(width, y1 - y0, thickness), cframe, color, material)
	p:SetAttribute("AngleDeg", angleDeg)
	return p
end

-- 빛나는 장식 파트 (부딪히지 않고 그림자 없음)
local function glow(part: Part): Part
	part.CanCollide = false
	part.CastShadow = false
	return part
end

-- 연료 탱크: 세로 원통 + 둥근 지붕 + 주황 띠
local function fuelTank(parent: Instance, angleDeg: number, radius: number, size: number)
	local at = ringPoint(angleDeg, radius, 0)
	local height = 34 * size
	local r = 11 * size
	post(parent, "FuelTank", at.X, at.Z, r, 0, height, TANK, Enum.Material.Metal)
	post(parent, "TankStripe", at.X, at.Z, r + 0.3, height * 0.55, height * 0.55 + 3, STRIPE, Enum.Material.SmoothPlastic)
	local dome = Instance.new("Part")
	dome.Name = "TankDome"
	dome.Shape = Enum.PartType.Ball
	dome.Anchored = true
	dome.Material = Enum.Material.Metal
	dome.Color = TANK
	dome.Size = Vector3.new(r * 2, r * 2, r * 2)
	dome.CFrame = CFrame.new(at.X, height, at.Z)
	dome.Parent = parent
	-- 발사대 쪽으로 가는 배관
	local toward = Vector3.new(-at.X, 0, -at.Z).Unit
	local from = at + toward * r
	local to = toward * (W.MountRadius + 2)
	local middle = (from + to) / 2 + Vector3.new(0, 1.5, 0)
	block(parent, "Pipe", Vector3.new(2, 2, (to - from).Magnitude), CFrame.lookAt(middle, middle + toward), STEEL_DARK, Enum.Material.Metal)
end

-- 조명탑: 가는 기둥 위에 빛나는 등
local function lightMast(parent: Instance, angleDeg: number, radius: number)
	local at = ringPoint(angleDeg, radius, 0)
	post(parent, "Mast", at.X, at.Z, 1.4, 0, 84, STEEL_DARK, Enum.Material.Metal)
	local facing = CFrame.lookAt(Vector3.new(at.X, 86, at.Z), Vector3.new(0, 60, 0))
	block(parent, "MastHead", Vector3.new(9, 4, 2), facing, DARK, Enum.Material.Metal)
	local lamp = glow(block(parent, "MastLamp", Vector3.new(8, 3, 0.4), facing * CFrame.new(0, 0, -1.1), Color3.fromRGB(255, 244, 214), Enum.Material.Neon))
	local light = Instance.new("SpotLight")
	light.Angle = 70
	light.Range = 60
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Face = Enum.NormalId.Front
	light.Shadows = false
	light.Parent = lamp
end

-- 관제실: 낮은 건물 + 빛나는 창 + 안테나
local function controlRoom(parent: Instance, angleDeg: number, radius: number)
	local at = ringPoint(angleDeg, radius, 0)
	local facing = CFrame.lookAt(Vector3.new(at.X, 0, at.Z), Vector3.new(0, 0, 0))
	block(parent, "ControlRoom", Vector3.new(34, 14, 20), facing * CFrame.new(0, 7, 0), PLAZA_EDGE, Enum.Material.Concrete)
	block(parent, "ControlRoof", Vector3.new(36, 2, 22), facing * CFrame.new(0, 15, 0), DARK, Enum.Material.Metal)
	glow(block(parent, "ControlWindow", Vector3.new(26, 3, 0.4), facing * CFrame.new(0, 9, -10.1), RIM_LIGHT, Enum.Material.Neon))
	block(parent, "Antenna", Vector3.new(1, 22, 1), facing * CFrame.new(11, 27, 4), STEEL_DARK, Enum.Material.Metal)
	glow(block(parent, "AntennaLamp", Vector3.new(1.6, 1.6, 1.6), facing * CFrame.new(11, 38.5, 4), STRIPE, Enum.Material.Neon))
end

local function buildPad(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Pad"

	-- 발사 광장 (행성 꼭대기 면에 조금 묻힘. 광장 밖 땅과 지형지물은 클라이언트가 만드는 행성)
	local plaza = cylinder(model, "Plaza", PLAZA_RADIUS, -14, 0, PLAZA, Enum.Material.Concrete)
	model.PrimaryPart = plaza
	cylinder(model, "PlazaEdge", PLAZA_RADIUS + 3, -16, -0.6, PLAZA_EDGE, Enum.Material.Concrete)
	-- 발사대 둘레 표시: 노란 고리
	glow(cylinder(model, "PadMark", W.MountRadius + 10, 0, 0.1, MARK, Enum.Material.SmoothPlastic))
	glow(cylinder(model, "PadMarkInner", W.MountRadius + 6, 0, 0.16, PLAZA_EDGE, Enum.Material.Concrete))
	-- 광장 가장자리 불빛
	for i = 0, 23 do
		local angle = i * 15 + 7.5
		local at = ringPoint(angle, PLAZA_RADIUS - 3, 0.3)
		glow(block(model, "RimLight", Vector3.new(3, 0.6, 1.2), CFrame.new(at) * CFrame.Angles(0, math.rad(angle), 0), RIM_LIGHT, Enum.Material.Neon))
	end
	-- 기지 시설: 로켓 뒤쪽(바깥 시점에서 보이는 쪽)에 연료 탱크와 관제실, 둘레에 조명탑
	fuelTank(model, 215, 104, 1)
	fuelTank(model, 240, 112, 0.8)
	fuelTank(model, 192, 116, 0.7)
	controlRoom(model, 285, 112)
	lightMast(model, 150, 128)
	lightMast(model, 255, 134)
	lightMast(model, 330, 128)
	-- 리스폰 옆 짐 상자
	for i, spot in ipairs({ { 24, 118 }, { 30, 126 }, { -26, 120 } }) do
		local at = ringPoint(spot[1], spot[2], 0)
		local size = if i == 2 then 6 else 8
		block(model, "Crate", Vector3.new(size, size, size), CFrame.new(at + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, math.rad(spot[1] + 10 * i), 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	end

	cylinder(model, "Mount", W.MountRadius, 0, W.MountHeight, STEEL_DARK, Enum.Material.Concrete)

	-- 발사탑 (+X 쪽)
	block(model, "Tower", Vector3.new(10, 190, 10), CFrame.new(64, 95, 0), TOWER, Enum.Material.Metal)
	block(model, "TowerArm", Vector3.new(34, 3, 6), CFrame.new(43, W.CabinFloorY - 2, 0), TOWER, Enum.Material.Metal)
	block(model, "TowerBase", Vector3.new(22, 6, 22), CFrame.new(64, 3, 0), DARK, Enum.Material.Concrete)

	-- 리스폰 지점 (+Z 쪽, 로켓을 바라봄)
	local spawnPosition = Vector3.new(0, 0.5, W.SpawnDistance)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Size = Vector3.new(16, 1, 16)
	spawnLocation.CFrame = CFrame.lookAt(spawnPosition, Vector3.new(0, 0.5, 0))
	spawnLocation.Color = STEEL_DARK
	spawnLocation.Material = Enum.Material.DiamondPlate
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = model

	model.Parent = parent
	return model
end

local function buildRocket(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Rocket"

	-- 선체: 선실 아래와 위는 속이 찬 원기둥, 선실 구간만 벽 조각으로 둘러서 안이 비어 있음
	cylinder(model, "EngineSkirt", W.HullRadius - 6, W.MountHeight, W.RocketBaseY, DARK, Enum.Material.Metal)
	local lower = cylinder(model, "LowerHull", W.HullRadius, W.RocketBaseY, W.CabinFloorY, STEEL, Enum.Material.Metal)
	model.PrimaryPart = lower
	cylinder(model, "UpperHull", W.HullRadius, W.CabinCeilY, W.RocketTopY, STEEL, Enum.Material.Metal)
	cylinder(model, "Band", W.HullRadius + 0.2, W.RocketBaseY + 30, W.RocketBaseY + 34, DARK, Enum.Material.Metal)

	-- 코 (위로 갈수록 좁아짐)
	local noseSteps = { { 24, 12 }, { 20, 10 }, { 15, 8 }, { 9, 6 } }
	local y = W.RocketTopY
	for i, step in ipairs(noseSteps) do
		cylinder(model, "Nose" .. i, step[1], y, y + step[2], STEEL, Enum.Material.Metal)
		y += step[2]
	end
	local tip = Instance.new("Part")
	tip.Name = "NoseTip"
	tip.Shape = Enum.PartType.Ball
	tip.Anchored = true
	tip.Material = Enum.Material.Metal
	tip.Color = STEEL
	tip.Size = Vector3.new(14, 14, 14)
	tip.CFrame = CFrame.new(0, y, 0)
	tip.Parent = model

	-- 꼬리 날개 4장
	for i = 0, 3 do
		local angle = 45 + i * 90
		local cframe = CFrame.new(ringPoint(angle, W.HullRadius + 9, W.RocketBaseY + 22)) * CFrame.Angles(0, math.rad(angle), 0)
		block(model, "Fin", Vector3.new(2, 44, 20), cframe, STEEL_DARK, Enum.Material.Metal)
	end

	-- 선실 바닥·천장
	local floor = cylinder(model, "CabinFloor", W.CabinRadius, W.CabinFloorY - 0.4, W.CabinFloorY + 0.2, FLOOR, Enum.Material.DiamondPlate)
	floor.CastShadow = false
	cylinder(model, "CabinCeiling", W.CabinRadius, W.CabinCeilY - 0.2, W.CabinCeilY + 0.4, DARK, Enum.Material.Metal)

	-- 선실 벽과 외창
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local stepDeg = 360 / W.WallSegments
	for i = 0, W.WallSegments - 1 do
		local angle = i * stepDeg
		local fromWindow = math.min(angle, 360 - angle) -- 외창 중심(0도)에서 벌어진 각도
		if fromWindow <= W.WindowHalfAngle + 0.01 then
			wallPanel(walls, "WallLow", angle, W.CabinFloorY, W.WindowBottomY, STEEL, Enum.Material.Metal)
			-- 유리 재질은 뒤의 반투명 물체를 가리므로 일반 재질에 투명도만 줌
			local glass = wallPanel(walls, "Window", angle, W.WindowBottomY, W.WindowTopY, GLASS, Enum.Material.SmoothPlastic)
			glass.Transparency = 0.85
			glass.CastShadow = false
			wallPanel(walls, "WallHigh", angle, W.WindowTopY, W.CabinCeilY, STEEL, Enum.Material.Metal)
		else
			wallPanel(walls, "Wall", angle, W.CabinFloorY, W.CabinCeilY, STEEL, Enum.Material.Metal)
		end
	end
	walls.Parent = model

	-- 전광판: 외창 위에서 좌석 쪽을 내려다봄 (앞면에 클라이언트가 화면을 붙임)
	local boardPosition = Vector3.new(0, W.BoardY, W.BoardZ)
	local seatFocus = Vector3.new(0, W.SeatFirstRowY + 4, -W.SeatRadius)
	local board = block(model, "Board", Vector3.new(W.BoardWidth, W.BoardHeight, 0.6), CFrame.lookAt(boardPosition, seatFocus), Color3.fromRGB(12, 14, 20), Enum.Material.SmoothPlastic)
	board.CastShadow = false
	local frame = block(model, "BoardFrame", Vector3.new(W.BoardWidth + 1.2, W.BoardHeight + 1.2, 0.5), board.CFrame * CFrame.new(0, 0, 0.5), DARK, Enum.Material.Metal)
	frame.CastShadow = false

	-- 선실 조명과 위기 경보등
	for i = 0, 3 do
		local lamp = block(model, "Lamp", Vector3.new(4, 0.4, 4), CFrame.new(ringPoint(45 + i * 90, 12, W.CabinCeilY - 0.5)), Color3.fromRGB(235, 240, 255), Enum.Material.Neon)
		lamp.CanCollide = false
		lamp.CastShadow = false
		local light = Instance.new("PointLight")
		light.Range = 46
		light.Brightness = 1.4
		light.Color = Color3.fromRGB(225, 232, 255)
		light.Shadows = false
		light.Parent = lamp
	end
	for i = 0, 3 do
		local alarm = block(model, "AlarmLight", Vector3.new(3, 1.2, 1.2), CFrame.new(ringPoint(70 + i * 73, W.CabinRadius - 1, W.CabinCeilY - 4)), Color3.fromRGB(90, 20, 20), Enum.Material.SmoothPlastic)
		alarm.CanCollide = false
		alarm.CastShadow = false
	end

	-- 관전자(유령)가 떠 있는 자리 기준점
	local ghostSpot = block(model, "GhostSpot", Vector3.new(1, 1, 1), CFrame.new(0, W.CabinCeilY - 9, 0), DARK, Enum.Material.SmoothPlastic)
	ghostSpot.Transparency = 1
	ghostSpot.CanCollide = false
	ghostSpot.CanQuery = false

	model.Parent = parent
	return model
end

-- 서버 시작 때 한 번
function World.build()
	-- 기본 Baseplate 와 리스폰 지점은 로켓 자리와 겹치므로 치움
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local model = Instance.new("Model")
	model.Name = "Rofly"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildPad(model)
	rocket = buildRocket(model)
	model.Parent = Workspace

	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(96, 92, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 116, 112)
end

function World.rocket(): Model
	return rocket :: Model
end

-- 좌석 배치: 외창 맞은편 벽에 층층이.
-- 좌석 번호 목록을 돌려줌: 맨 윗줄 가운데(선장 자리)부터, 윗줄을 먼저 채우고 아랫줄로.
-- 사람이 이 순서대로 먼저 앉으므로, 화면 아래쪽 미션 판에 가려지는 아랫줄에는 봇부터 앉게 됩니다.
-- (사람이 윗줄 좌석 수보다 많으면 나머지 사람은 아랫줄에 앉습니다. 기본 10명 배치는 윗줄 5자리.)
function World.buildSeats(count: number): { number }
	World.clearSeats()
	local folder = Instance.new("Folder")
	folder.Name = "Seats"

	local perRow = math.min(W.SeatsPerRowMax, math.ceil(math.sqrt(count * 2.5)))
	local rows = math.ceil(count / perRow)
	local stepRad = W.SeatSpacing / W.SeatRadius
	local topRowCount = count - perRow * (rows - 1)
	local captainSeat = perRow * (rows - 1) + math.ceil(topRowCount / 2)

	seatCFrames = {}
	local centrality: { [number]: number } = {}
	for i = 1, count do
		local row = math.floor((i - 1) / perRow)
		local col = (i - 1) % perRow
		local inRow = if row < rows - 1 then perRow else topRowCount
		local theta = math.pi + (col - (inRow - 1) / 2) * stepRad
		-- 한 줄뿐이면 둘째 줄 높이에 둠 (첫 줄 높이는 선실 시점에서 미션 판 뒤에 가려짐)
		local level = if rows == 1 then 1 else row
		local position = Vector3.new(math.sin(theta) * W.SeatRadius, W.SeatFirstRowY + level * W.SeatRowHeight, math.cos(theta) * W.SeatRadius)
		local inward = Vector3.new(-math.sin(theta), 0, -math.cos(theta))
		local base = CFrame.lookAt(position, position + inward)
		local seatCFrame = base * CFrame.Angles(math.rad(W.SeatReclineDeg), 0, 0)
		seatCFrames[i] = seatCFrame
		centrality[i] = (rows - 1 - row) * 1000 + math.abs(col - (inRow - 1) / 2) * 10
		if i == captainSeat then
			centrality[i] = -1
		end

		local seat = Instance.new("Model")
		seat.Name = "Seat" .. i
		seat:SetAttribute("Index", i)
		local seatPad = block(seat, "Pad", Vector3.new(4, 0.5, 3.6), seatCFrame, CUSHION, Enum.Material.SmoothPlastic)
		seatPad.CanCollide = false
		seat.PrimaryPart = seatPad
		local back = block(seat, "Back", Vector3.new(4, 3, 0.5), seatCFrame * CFrame.new(0, 1.5, 2.05), SEAT, Enum.Material.SmoothPlastic)
		back.CanCollide = false
		local arm = block(seat, "Arm", Vector3.new(1, 1, 5), base * CFrame.new(0, -0.7, 3.6), DARK, Enum.Material.Metal)
		arm.CanCollide = false
		if i == captainSeat then
			local trim = block(seat, "CaptainTrim", Vector3.new(4.2, 0.3, 0.7), seatCFrame * CFrame.new(0, 3.15, 2.05), GOLD, Enum.Material.Neon)
			trim.CanCollide = false
			trim.CastShadow = false
		end
		seat.Parent = folder
	end

	folder.Parent = rocket
	seatsFolder = folder

	local order: { number } = {}
	for i = 1, count do
		order[i] = i
	end
	table.sort(order, function(a: number, b: number): boolean
		if centrality[a] ~= centrality[b] then
			return centrality[a] < centrality[b]
		end
		return a < b
	end)
	return order
end

function World.clearSeats()
	if seatsFolder then
		seatsFolder:Destroy()
		seatsFolder = nil
	end
	seatCFrames = {}
end

function World.seatCFrame(index: number): CFrame
	return seatCFrames[index]
end

function World.seatCount(): number
	return #seatCFrames
end

-- 관전자(유령) 자리: 선실 양옆 위쪽에 떠서 외창을 바라봄
function World.ghostCFrame(index: number): CFrame
	local side = if index % 2 == 1 then 1 else -1
	local slot = math.floor((index - 1) / 2)
	local position = Vector3.new(side * 16, W.CabinCeilY - 10 - (slot % 3) * 6, 6 - math.floor(slot / 3) * 6)
	return CFrame.lookAt(position, Vector3.new(0, (W.WindowBottomY + W.WindowTopY) / 2, W.CabinRadius))
end

-- 발사장 리스폰 자리 (여러 명이 겹치지 않게 옆으로 벌림)
function World.spawnCFrame(index: number): CFrame
	local offset = ((index - 1) % 8 - 3.5) * 5
	local position = Vector3.new(offset, 4, W.SpawnDistance + math.floor((index - 1) / 8) * 5)
	return CFrame.lookAt(position, Vector3.new(0, 4, 0))
end

return World
