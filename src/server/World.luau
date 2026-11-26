-- 회색 상자 월드를 코드로 만듭니다: 발사장, 로켓, 선실(외창·전광판), 좌석.
-- 맵을 Studio 에서 따로 만들지 않아도 Play 만 누르면 생깁니다.
-- 로켓은 원점에 고정이고, 비행 중에는 클라이언트가 배경(발사장·별)을 움직입니다.

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
local GROUND = Color3.fromRGB(84, 78, 74)
local CRACK = Color3.fromRGB(255, 110, 40)
local SEAT = Color3.fromRGB(78, 84, 98)
local CUSHION = Color3.fromRGB(40, 44, 54)
local GOLD = Color3.fromRGB(255, 205, 60)
local TOWER = Color3.fromRGB(120, 60, 54)

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

local function buildPad(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Pad"

	local ground = block(model, "Ground", Vector3.new(W.GroundSize, 4, W.GroundSize), CFrame.new(0, -2, 0), GROUND, Enum.Material.Slate)
	model.PrimaryPart = ground

	-- 붕괴 조짐: 땅의 빛나는 균열
	local random = Random.new(7)
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2 + random:NextNumber() * 0.3
		local length = 160 + random:NextNumber() * 420
		local distance = 70 + length / 2
		local position = Vector3.new(math.sin(angle) * distance, 0.06, math.cos(angle) * distance)
		local crack = block(model, "Crack", Vector3.new(2 + random:NextNumber() * 3, 0.2, length), CFrame.new(position) * CFrame.Angles(0, angle, 0), CRACK, Enum.Material.Neon)
		crack.CanCollide = false
		crack.CastShadow = false
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
-- 가운데 자리부터 센 좌석 번호 목록을 돌려줌 (첫 번째 = 맨 윗줄 가운데 = 선장 자리).
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
		local position = Vector3.new(math.sin(theta) * W.SeatRadius, W.SeatFirstRowY + row * W.SeatRowHeight, math.cos(theta) * W.SeatRadius)
		local inward = Vector3.new(-math.sin(theta), 0, -math.cos(theta))
		local base = CFrame.lookAt(position, position + inward)
		local seatCFrame = base * CFrame.Angles(math.rad(W.SeatReclineDeg), 0, 0)
		seatCFrames[i] = seatCFrame
		centrality[i] = math.abs(col - (inRow - 1) / 2) * 10 - row
		if i == captainSeat then
			centrality[i] = -1000
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
