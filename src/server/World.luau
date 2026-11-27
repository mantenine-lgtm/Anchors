-- 회색 상자 월드를 코드로 만듭니다: 발사 광장, 로켓, 선실(외창 2개·전광판 2개).
-- 맵을 Studio 에서 따로 만들지 않아도 Play 만 누르면 생깁니다.
-- 선실은 승무원이 걸어다니는 둥근 방입니다. 4면 배치와 탑승 자리 계산은 shared/Cabin.luau.
-- 로켓은 원점에 고정이고, 비행 중에는 클라이언트가 배경(행성·발사 광장·별)을 움직입니다.
-- 광장 밖의 둥근 행성과 지형지물은 판마다 바뀌며 클라이언트가 만듭니다(client/Planet.luau).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cabin = require(Shared:WaitForChild("Cabin"))
local Config = require(Shared:WaitForChild("Config"))

local W = Config.World
-- 로켓 겉면과 발사장 시설의 모양 (GPT 가 만든 모델 코드)
local LaunchPad = require(script.Parent.LaunchPad)
local RocketShell = require(script.Parent.RocketShell)

local World = {}

local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_DARK = Color3.fromRGB(120, 126, 136)
local DARK = Color3.fromRGB(52, 56, 64)
local FLOOR = Color3.fromRGB(46, 50, 58)
local GLASS = Color3.fromRGB(170, 215, 255)
-- 선실 안쪽은 어둡게 (창밖이 더 밝아 보이게): 둘레 벽 안쪽을 덮는 판, 천장, 전광판 벽
local LINING = Color3.fromRGB(40, 44, 53)
local CEILING = Color3.fromRGB(30, 33, 40)
local PLAZA = Color3.fromRGB(96, 100, 110)
local PANEL_WALL = Color3.fromRGB(36, 40, 49)

-- 발사 광장: 행성 꼭대기 면(가장자리까지 약 187 스터드) 안에 들어가는 둥근 판. 윗면 y = 0
local PLAZA_RADIUS = 150

local rocket: Model? = nil
local spotCount = 0 -- 이번 판 탑승 자리 수 (승무원 수). 0 = 판이 없음

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

-- 각도(도)와 반지름으로 로켓 둘레의 한 점. 0도 = +Z, 90도 = +X, 180도 = -Z (외창은 0도와 180도)
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

-- 둘레 벽 한 칸의 안쪽 면을 덮는 얇은 어두운 판. 벽 조각은 바깥에서 보이는 밝은 선체 겉면이기도 해서 안쪽만 어둡게 덮음
local function lining(parent: Instance, angleDeg: number, y0: number, y1: number)
	local width = 2 * W.CabinRadius * math.tan(math.pi / W.WallSegments) + 0.05
	local cframe = CFrame.new(ringPoint(angleDeg, W.CabinRadius - 0.1, (y0 + y1) / 2)) * CFrame.Angles(0, math.rad(angleDeg), 0)
	local p = block(parent, "WallLining", Vector3.new(width, y1 - y0, 0.2), cframe, LINING, Enum.Material.Metal)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function buildPad(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Pad"

	-- 발사 광장 (행성 꼭대기 면에 조금 묻힘. 광장 밖 땅과 지형지물은 클라이언트가 만드는 행성)
	local plaza = cylinder(model, "Plaza", PLAZA_RADIUS, -14, 0, PLAZA, Enum.Material.Concrete)
	model.PrimaryPart = plaza
	-- 발사대·발사탑·연료 탱크·관제 벙커·조명탑·광장 표시 (Spawn 은 맨 마지막에: 클라이언트가 Spawn 을 보고 발사장이 다 왔다고 봄)
	LaunchPad.build(model, {
		plazaRadius = PLAZA_RADIUS,
		mountRadius = W.MountRadius,
		mountY = W.MountHeight,
		hullRadius = W.HullRadius,
		armY = W.CabinFloorY - 2,
		spawnDistance = W.SpawnDistance,
	})

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

-- 외창 유리가 덮는 방위각 범위. 벽 조각 중심이 외창 중심에서 WindowHalfAngle 안이면 유리이고, 조각은 양옆으로 반 칸씩 더 넓음
local function windowRanges(): { { centerDeg: number, halfDeg: number } }
	local stepDeg = 360 / W.WallSegments
	local half = math.floor((W.WindowHalfAngle + 0.01) / stepDeg) * stepDeg + stepDeg / 2
	return { { centerDeg = 0, halfDeg = half }, { centerDeg = 180, halfDeg = half } } -- 외창 2개 (+Z, -Z)
end

local function buildRocket(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Rocket"

	-- 선체 겉면: 엔진·아래 선체·위 선체·코·플랩·내열 타일 (선실 구간은 아래 벽 조각이 겉면이고, 유리 앞은 비워 둠)
	local lower = RocketShell.build(model, {
		hullRadius = W.HullRadius,
		mountY = W.MountHeight,
		baseY = W.RocketBaseY,
		cabinFloorY = W.CabinFloorY,
		cabinCeilY = W.CabinCeilY,
		topY = W.RocketTopY,
		windowBottomY = W.WindowBottomY,
		windowTopY = W.WindowTopY,
		windows = windowRanges(),
	})
	model.PrimaryPart = lower

	-- 선실 바닥·천장
	local floor = cylinder(model, "CabinFloor", W.CabinRadius, W.CabinFloorY - 0.4, W.CabinFloorY + 0.2, FLOOR, Enum.Material.DiamondPlate)
	floor.CastShadow = false
	cylinder(model, "CabinCeiling", W.CabinRadius, W.CabinCeilY - 0.2, W.CabinCeilY + 0.4, CEILING, Enum.Material.Metal)

	-- 선실 둘레 벽과 외창 2개 (+Z 와 -Z). 이 벽 조각들이 바깥에서 보이는 선체 겉면이기도 함
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local stepDeg = 360 / W.WallSegments
	for i = 0, W.WallSegments - 1 do
		local angle = i * stepDeg
		local fromFront = math.min(angle, 360 - angle) -- +Z 외창 중심(0도)에서 벌어진 각도
		local fromBack = math.abs(angle - 180) -- -Z 외창 중심(180도)에서 벌어진 각도
		if math.min(fromFront, fromBack) <= W.WindowHalfAngle + 0.01 then
			wallPanel(walls, "WallLow", angle, W.CabinFloorY, W.WindowBottomY, STEEL, Enum.Material.Metal)
			lining(walls, angle, W.CabinFloorY, W.WindowBottomY)
			-- 유리 재질은 뒤의 반투명 물체를 가리므로 일반 재질에 투명도만 줌. 거의 투명하게 해서 창밖이 밝게 보이게
			local glass = wallPanel(walls, "Window", angle, W.WindowBottomY, W.WindowTopY, GLASS, Enum.Material.SmoothPlastic)
			glass.Transparency = 0.93
			glass.CastShadow = false
			wallPanel(walls, "WallHigh", angle, W.WindowTopY, W.CabinCeilY, STEEL, Enum.Material.Metal)
			lining(walls, angle, W.WindowTopY, W.CabinCeilY)
		else
			wallPanel(walls, "Wall", angle, W.CabinFloorY, W.CabinCeilY, STEEL, Enum.Material.Metal)
			lining(walls, angle, W.CabinFloorY, W.CabinCeilY)
		end
	end
	walls.Parent = model

	-- 전광판 벽: 둥근 벽 앞(x = ±PanelWallX)에 세운 평평한 벽. 끝은 둘레 벽 속에 묻히고 선체 밖으로는 나오지 않음
	local wallRadius = (W.CabinRadius + W.HullRadius) / 2
	local halfChord = math.sqrt(wallRadius * wallRadius - (W.PanelWallX + 1) ^ 2)
	local cabinHeight = W.CabinCeilY - W.CabinFloorY
	for _, side in ipairs({ 1, -1 }) do
		local panelWall = block(model, "PanelWall", Vector3.new(1, cabinHeight, halfChord * 2), CFrame.new(side * (W.PanelWallX + 0.5), (W.CabinFloorY + W.CabinCeilY) / 2, 0), PANEL_WALL, Enum.Material.Metal)
		panelWall:SetAttribute("Side", side)
	end

	-- 전광판: 평평한 벽에 붙어 선실 가운데를 바라봄 (앞면에 클라이언트가 화면을 붙임)
	--  · Board (+X): 진행도 (Board.luau)   · PartsBoard (-X 위쪽): 부품 장착판 (PartsBoard.luau)
	--  · MyPartsBoard (-X, 장착판 바로 아래): 내 부품 판 (사람마다 자기 부품을 그림)
	local function screen(name: string, side: number, width: number, height: number, centerY: number)
		local position = Vector3.new(side * (W.PanelWallX - 0.55), centerY, 0)
		local board = block(model, name, Vector3.new(width, height, 0.6), CFrame.lookAt(position, Vector3.new(0, centerY, 0)), Color3.fromRGB(12, 14, 20), Enum.Material.SmoothPlastic)
		board.CastShadow = false
		local frame = block(model, name .. "Frame", Vector3.new(width + 1.2, height + 1.2, 0.5), board.CFrame * CFrame.new(0, 0, 0.3), DARK, Enum.Material.Metal)
		frame.CastShadow = false
	end
	screen("Board", 1, W.BoardWidth, W.BoardHeight, W.BoardY)
	screen("PartsBoard", -1, W.PartsBoardWidth, W.PartsBoardHeight, W.PartsBoardY)
	screen("MyPartsBoard", -1, W.MyPartsBoardWidth, W.MyPartsBoardHeight, W.MyPartsBoardY)

	-- 선실 조명과 위기 경보등. 조명은 어둑하게 (창밖이 선실보다 밝아 보이게). 빛 색은 Backdrop 이 경보 때 바꿨다 되돌림
	local lampRadius = W.CabinRadius * 0.5
	for i = 0, 4 do
		local at = if i == 4 then Vector3.new(0, W.CabinCeilY - 0.5, 0) else ringPoint(45 + i * 90, lampRadius, W.CabinCeilY - 0.5)
		local lamp = block(model, "Lamp", Vector3.new(4, 0.4, 4), CFrame.new(at), Color3.fromRGB(150, 160, 182), Enum.Material.Neon)
		lamp.CanCollide = false
		lamp.CastShadow = false
		local light = Instance.new("PointLight")
		light.Range = 30
		light.Brightness = 0.5
		light.Color = Color3.fromRGB(225, 232, 255)
		light.Shadows = false
		light.Parent = lamp
	end
	-- 경보등은 외창과 전광판 벽 사이의 둥근 벽 네 귀퉁이에
	for i = 0, 3 do
		local angle = 45 + i * 90
		local at = ringPoint(angle, W.CabinRadius - 1, W.CabinCeilY - 4)
		local alarm = block(model, "AlarmLight", Vector3.new(3, 1.2, 1.2), CFrame.new(at) * CFrame.Angles(0, math.rad(angle), 0), Color3.fromRGB(90, 20, 20), Enum.Material.SmoothPlastic)
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

-- 탑승 자리: 승무원 count 명이 판을 시작할 때 서는 선실 바닥의 자리 (의자는 없고 그 뒤로는 자유롭게 걸어다님).
-- 자리 번호 목록을 돌려줌: 1번(방 가운데, 선장)부터 바깥쪽으로. 사람이 이 순서대로 먼저 받으므로 봇은 바깥쪽에 섭니다.
function World.buildSpots(count: number): { number }
	World.clearSpots()
	spotCount = count
	local order: { number } = {}
	for i = 1, count do
		order[i] = i
	end
	return order
end

function World.clearSpots()
	spotCount = 0
end

-- 탑승 자리의 바닥 위치와 방향 (가까운 외창을 바라봄)
function World.spotCFrame(index: number): CFrame
	return Cabin.spotCFrame(index, spotCount)
end

function World.spotCount(): number
	return spotCount
end

-- 관전자(유령) 자리: 선실 천장 가까이 둘레에 떠서 선실 가운데를 내려다봄
function World.ghostCFrame(index: number): CFrame
	local angle = 20 + (index - 1) * 47
	local radius = W.PanelWallX - 6
	local position = ringPoint(angle, radius, W.CabinCeilY - 9 - ((index - 1) % 2) * 4)
	return CFrame.lookAt(position, Vector3.new(0, W.CabinFloorY + 6, 0))
end

-- 발사장 리스폰 자리 (여러 명이 겹치지 않게 옆으로 벌림)
function World.spawnCFrame(index: number): CFrame
	local offset = ((index - 1) % 8 - 3.5) * 5
	local position = Vector3.new(offset, 4, W.SpawnDistance + math.floor((index - 1) / 8) * 5)
	return CFrame.lookAt(position, Vector3.new(0, 4, 0))
end

return World
