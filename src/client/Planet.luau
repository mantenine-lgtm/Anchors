-- 발사 행성: 판마다 바뀌는 둥근 행성과 주변 지형지물을 내 화면에만 만들고,
-- 비행하면 행성이 점점 멀어지며 작아지는 모습을 선실 창과 바깥 시점 모두에서 보여 줍니다.
--
--  · 서버는 행성 종류(Planet)와 배치 씨앗(PlanetSeed)만 RoundState 속성으로 알려 줍니다. 씨앗이 같으면 모두 같은 행성이 생깁니다.
--  · 행성: 정이십면체를 나눈 삼각형 320개(쐐기 파트 2개씩)로 만든 반지름 2000 스터드의 로우폴리 공.
--    서버가 만든 발사 광장(Rofly.Pad)이 행성 꼭대기 면 위에 놓입니다. 꼭짓점 높이를 조금씩 달리해 언덕과 바다를 만들고,
--    모서리를 따라 붕괴 균열이 빛납니다.
--  · 지형지물: 멀리서도 보이는 큰 것(화산·산·메사·수정 첨탑 등)과 발사대 근처 소품(나무·바위·수정 등).
--  · 하늘: 행성마다 다른 천체(붉은 해, 달, 고리 행성, 성운, 오로라, 구름). 하늘빛은 Planets.luau 의 Sky 를 Backdrop 이 씀.
--  · 비행: 로켓은 원점에 그대로 있고 행성 쪽을 움직입니다. 처음 몇 초는 실제처럼 아래로 내려가고,
--    그 뒤로는 '보이는 고도'가 거리(km)의 0.38제곱으로 느리게 늘어 행성이 점점 작아지는 공이 됩니다.
--    카메라는 옆을 보고 있으므로 행성을 시선 아래쪽으로 돌려 놓아 화면에 계속 보이게 합니다
--    (선실 창: 지평선이 창 아래쪽에 걸림. 바깥 시점: 로켓 뒤 아래쪽, 작아지면 옆으로 비킴).
--    너무 멀면 크기를 줄여 그만큼 가깝게 둡니다(카메라에서 보이는 모습은 같음).
-- 전부 내 화면에서만 만들고 움직이는 것이라 다른 사람에게 영향이 없습니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Planets = require(Shared:WaitForChild("Planets"))

local State = require(script.Parent:WaitForChild("State"))
-- 지형지물·소품의 모양 (GPT 가 만든 모델 코드)
local PlanetProps = require(script.Parent:WaitForChild("PlanetProps"))

local Planet = {}

local W = Config.World

-- ------------------------------------------------------------ 모양 수치
local RADIUS = 2000 -- 행성 반지름(스터드)
local SUBDIVISIONS = 2 -- 정이십면체를 나누는 횟수 (2 = 삼각형 320개)
local SHELL = 8 -- 행성 껍질 두께
local TOP_Y = -2 -- 행성 꼭대기 면의 높이 (발사 광장 윗면 y = 0 보다 조금 아래)
local SEA_DROP = 0.35 -- 바다 높이 = 반지름 - 높낮이 × 이 값
local LAND_REACH = 0.3 -- 꼭대기에서 이 각도(라디안) 안은 늘 땅 (바다·용암이 발사대 바로 옆에 오지 않게)
local PROP_REACH = 0.8 -- 소품을 놓는 범위 (꼭대기에서 잰 각도, 라디안. 0.8 = 약 1600 스터드)
local BASE_CLEAR = 180 -- 발사대 중심에서 이 거리 안에는 소품을 놓지 않음 (광장 반지름 150)
local OUTSIDE_CAMERA = Vector3.new(W.OutsideCamera[1], 0, W.OutsideCamera[3])
local SKY_ORIGIN = Vector3.new(0, 140, 0)
local SKY_DISTANCE = 1600 -- 하늘 천체까지 거리 (멀수록 대기 안개에 흐려짐)

-- ------------------------------------------------------------ 비행 중 멀어지는 정도
local TRUE_STUDS_PER_KM = 1000 * W.StudsPerMeter -- 실제 높이 (처음 몇 초)
local FAR_SCALE = 418 -- 그 뒤 보이는 고도 = FAR_SCALE × km^FAR_POWER (스터드)
local FAR_POWER = 0.381 -- (1 km = 각반지름 약 51도, 30 km = 33도, 100 km = 26도, 36,000 km = 5도, 80만 km = 1.5도)
local MAX_DISTANCE = 3000 -- 카메라에서 행성 중심까지 이보다 멀면 크기를 줄여 그만큼 가깝게 둠 (안개에 덜 흐려짐)
local SCALE_STEPS = 32 -- 크기 배율은 2배마다 이만큼의 단계로만 바꿈 (크기 바꾸기는 무거워서 자주 하지 않음. 보이는 모습은 같음)
local INSIDE_RADIUS = 120 -- 카메라가 로켓 축에서 이 거리 안이면 선실 시점으로 봄
local OUTSIDE_RAMP = 350 -- 바깥 시점: 보이는 고도가 이만큼이 될 때까지 실제처럼 내려가다가 서서히 화면 안으로 들어옴
local PROPS_HIDE_ALTITUDE = 900 -- 보이는 고도가 이보다 높으면 작은 소품은 숨김 (안 보일 만큼 작고, 움직일 파트를 줄임)
local NEAR_ALTITUDE = 400 -- 이보다 낮을 때는 매 프레임 옮기고, 높으면 초당 20번만 옮김
local SLOW_INTERVAL = 0.05
local ANCHOR_MOVE = 2 -- 카메라가 이보다 많이 움직였을 때만 기준 위치를 바꿈 (작은 흔들림은 무시)

-- ------------------------------------------------------------ 상태
type Layer = { model: Model, rest: CFrame, hidden: boolean, applied: string }

local layers: { [string]: Layer } = {}
local builtId = ""
local builtSeed = -1
local restCenter = Vector3.new(0, -RADIUS, 0) -- 쉬는 자세에서 행성 중심
local skyFolder: Folder? = nil
local skyParts: { BasePart } = {}
local skyFade = 1
-- 서버가 만든 발사 광장(Rofly.Pad)의 파트들과 쉬는 자세의 자리·크기.
-- 광장은 기준 파트(PrimaryPart)가 있는 모델이라 PivotTo 를 거듭하면 회전 오차가 쌓이므로, 매번 쉬는 자세에서 바로 계산해 놓음
type PadPart = { part: BasePart, cframe: CFrame, size: Vector3 }
local padParts: { PadPart } = {}
local padScale = 1
local padApplied = "" -- 발사 광장에 마지막으로 적용한 자리 (같으면 다시 옮기지 않음)
local anchor: Vector3? = nil
local lastApply = 0
local toastPending = ""
local lastFlightKm = 0 -- 비행이 끝날 때의 거리 (정산이 끝나며 서버 거리가 0 으로 돌아가도 행성이 갑자기 다가오지 않게)

-- ------------------------------------------------------------ 작은 도구
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothstep(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function shade(color: Color3, k: number): Color3
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

local function newPart(parent: Instance, name: string, color: Color3, material: Enum.Material, className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material
	part.Color = color
	part.Parent = parent
	return part
end

local function box(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = newPart(parent, name, color, material)
	part.Size = size
	part.CFrame = cframe
	return part
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material): BasePart
	local part = newPart(parent, name, color, material) :: Part
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(center)
	return part
end

-- 삼각형 하나를 쐐기 파트 2개로 (바깥 면이 정확히 삼각형 a b c 에 오도록 두께만큼 안쪽으로 밀어 넣음).
-- inside 는 도형 안쪽의 한 점 (바깥 방향을 정하는 데 씀)
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, thickness: number, color: Color3, material: Enum.Material): { BasePart }
	local normal = (b - a):Cross(c - a)
	if normal.Magnitude < 1e-4 then
		return {}
	end
	normal = normal.Unit
	if normal:Dot((a + b + c) / 3 - inside) < 0 then
		normal = -normal
	end
	local shift = -normal * (thickness / 2)
	-- 가장 긴 변을 bc 로 놓고, a 에서 bc 에 내린 수선으로 직각삼각형 두 개로 나눔
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local first = newPart(parent, "Face", color, material, "WedgePart")
	first.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2 + shift, right, up, back)
	local second = newPart(parent, "Face", color, material, "WedgePart")
	second.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back)
	return { first, second }
end

-- 표면의 한 점에 세운 좌표계: Y = 표면에서 바깥쪽, yaw = 그 축으로 돌린 각
local function surfaceFrame(point: Vector3, up: Vector3, yaw: number): CFrame
	local reference = if math.abs(up.Z) < 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local right = reference:Cross(up).Unit
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(point, right, up, back) * CFrame.Angles(0, yaw, 0)
end

-- ------------------------------------------------------------ 지형지물과 소품
-- 모두 같은 모양: (부모, 표면 좌표계, 크기 배율, 색 목록, 난수) -> 차지하는 반지름(스터드). 만드는 코드는 PlanetProps.luau
type Builder = (Instance, CFrame, number, { Color3 }, Random) -> number

local function pick(colors: { Color3 }, index: number): Color3
	return colors[(index - 1) % #colors + 1]
end

local BUILDERS: { [string]: Builder } = PlanetProps

-- 바다 위에 서는 지형지물
local ON_SEA: { [string]: boolean } = { seaStack = true }

-- ------------------------------------------------------------ 하늘 천체
type BodyBuilder = (Instance, Vector3, number, { Color3 }, Random) -> ()

local BODIES: { [string]: BodyBuilder } = {}

BODIES.sun = function(parent, center, radius, colors, _rng)
	ball(parent, "Sun", center, radius * 2, pick(colors, 1), Enum.Material.Neon)
	local halo = ball(parent, "SunHalo", center, radius * 2.7, pick(colors, 1), Enum.Material.Neon)
	halo.Transparency = 0.8
end

BODIES.moon = function(parent, center, radius, colors, _rng)
	ball(parent, "Moon", center, radius * 2, pick(colors, 1), Enum.Material.Neon)
end

BODIES.ringed = function(parent, center, radius, colors, rng)
	ball(parent, "Giant", center, radius * 2, pick(colors, 1), Enum.Material.Neon)
	-- 고리: 작은 판을 둥글게 늘어놓음. 카메라 쪽(발사대)을 보게 기울임
	local facing = CFrame.lookAt(center, SKY_ORIGIN) * CFrame.Angles(math.rad(70), math.rad(rng:NextNumber(-20, 20)), 0)
	local count = 30
	local ringRadius = radius * 1.75
	local width = radius * 0.55
	local length = 2 * math.pi * ringRadius / count * 1.08
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local frame = facing * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -ringRadius)
		local segment = box(parent, "Ring", frame, Vector3.new(length, 2, width), pick(colors, 2), Enum.Material.Neon)
		segment.Transparency = 0.25
	end
end

BODIES.nebula = function(parent, center, radius, colors, rng)
	for i = 1, 4 do
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * radius * 0.6
		local cloud = ball(parent, "Nebula", center + offset, radius * rng:NextNumber(1.0, 1.5), pick(colors, i), Enum.Material.Neon)
		cloud.Transparency = 0.82
	end
end

BODIES.aurora = function(parent, center, radius, colors, rng)
	local facing = CFrame.lookAt(center, Vector3.new(SKY_ORIGIN.X, center.Y, SKY_ORIGIN.Z))
	local count = 8
	for i = 1, count do
		local x = (i - (count + 1) / 2) / count * radius * 2.2
		local height = radius * rng:NextNumber(0.6, 1.0)
		local frame = facing * CFrame.new(x, rng:NextNumber(-0.1, 0.1) * radius, rng:NextNumber(-0.3, 0.3) * radius) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		local panel = box(parent, "Aurora", frame, Vector3.new(radius * 0.32, height, 3), pick(colors, i), Enum.Material.Neon)
		panel.Transparency = 0.72
	end
end

BODIES.puffs = function(parent, center, radius, colors, rng)
	for _ = 1, 3 do
		local cluster = center + Vector3.new(rng:NextNumber(-1, 1) * radius, rng:NextNumber(-0.3, 0.3) * radius, rng:NextNumber(-1, 1) * radius)
		for _ = 1, 4 do
			local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.4), rng:NextNumber(-1, 1)) * radius * 0.22
			local puff = ball(parent, "Puff", cluster + offset, radius * rng:NextNumber(0.25, 0.4), pick(colors, 1), Enum.Material.SmoothPlastic)
			puff.Transparency = 0.08
		end
	end
end

-- ------------------------------------------------------------ 행성 그물
-- 정이십면체를 levels 번 나눈 공 (꼭짓점은 단위 벡터)
local function icosphere(levels: number): ({ Vector3 }, { { number } })
	local t = (1 + math.sqrt(5)) / 2
	local raw = {
		{ -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 },
		{ 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t },
		{ t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 },
	}
	local vertices: { Vector3 } = {}
	for i, v in ipairs(raw) do
		vertices[i] = Vector3.new(v[1], v[2], v[3]).Unit
	end
	local faces: { { number } } = {
		{ 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 },
		{ 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
		{ 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 },
		{ 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 },
	}
	for _ = 1, levels do
		local cache: { [number]: number } = {}
		local function middle(i: number, j: number): number
			local key = if i < j then i * 100000 + j else j * 100000 + i
			local found = cache[key]
			if found then
				return found
			end
			table.insert(vertices, ((vertices[i] + vertices[j]) / 2).Unit)
			cache[key] = #vertices
			return #vertices
		end
		local split: { { number } } = {}
		for _, face in ipairs(faces) do
			local a, b, c = face[1], face[2], face[3]
			local ab, bc, ca = middle(a, b), middle(b, c), middle(c, a)
			table.insert(split, { a, ab, ca })
			table.insert(split, { b, bc, ab })
			table.insert(split, { c, ca, bc })
			table.insert(split, { ab, bc, ca })
		end
		faces = split
	end
	return vertices, faces
end

type Mesh = {
	dirs: { Vector3 }, -- 꼭짓점 방향 (단위 벡터, 행성 좌표)
	radii: { number }, -- 꼭짓점 반지름
	sea: { boolean },
	height: { number }, -- 0 (바다 높이) ~ 1 (가장 높음)
	faces: { { number } },
	top: number, -- 발사대가 놓이는 꼭대기 면 번호
	neighbors: { { number } },
}

local function faceArea(mesh: Mesh, face: { number }): number
	local a = mesh.dirs[face[1]]
	return (mesh.dirs[face[2]] - a):Cross(mesh.dirs[face[3]] - a).Magnitude
end

-- 꼭대기 면이 +Y 를 보고, 그 면의 한 꼭짓점이 +Z(외창 쪽)를 향하게 돌린 그물
local function makeMesh(planet: Planets.Planet, rng: Random): Mesh
	local dirs, faces = icosphere(SUBDIVISIONS)
	-- 가장 넓은(가장 고른) 면을 꼭대기로
	local top = 1
	local best = -1
	local probe: Mesh = { dirs = dirs, radii = {}, sea = {}, height = {}, faces = faces, top = 1, neighbors = {} }
	for i, face in ipairs(faces) do
		local area = faceArea(probe, face)
		if area > best + 1e-9 then
			best = area
			top = i
		end
	end
	local f = faces[top]
	local normal = (dirs[f[2]] - dirs[f[1]]):Cross(dirs[f[3]] - dirs[f[1]]).Unit
	if normal:Dot(dirs[f[1]]) < 0 then
		normal = -normal
	end
	local toward = dirs[f[1]] - normal * dirs[f[1]]:Dot(normal)
	toward = toward.Unit
	local frame = CFrame.fromMatrix(Vector3.zero, normal:Cross(toward).Unit, normal, toward)
	for i, dir in ipairs(dirs) do
		dirs[i] = frame:VectorToObjectSpace(dir).Unit
	end

	-- 꼭짓점 높이: 잡음 값의 순위로 나눔 (바다 비율이 잡음 모양과 상관없이 SeaShare 가 되게)
	local ox, oy, oz = rng:NextNumber(10, 90) + 0.37, rng:NextNumber(10, 90) + 0.61, rng:NextNumber(10, 90) + 0.13
	local noise: { number } = {}
	local order: { number } = {}
	for i, dir in ipairs(dirs) do
		local n = math.noise(dir.X * 1.7 + ox, dir.Y * 1.7 + oy, dir.Z * 1.7 + oz)
			+ 0.5 * math.noise(dir.X * 3.9 + oy, dir.Y * 3.9 + oz, dir.Z * 3.9 + ox)
		noise[i] = n + rng:NextNumber(-0.02, 0.02)
		order[i] = i
	end
	table.sort(order, function(a: number, b: number): boolean
		return noise[a] < noise[b]
	end)
	local radii: { number } = {}
	local sea: { boolean } = {}
	local height: { number } = {}
	local topSet: { [number]: boolean } = { [f[1]] = true, [f[2]] = true, [f[3]] = true }
	local landFloor = math.min(planet.SeaShare + 0.15, 0.95)
	for rank, i in ipairs(order) do
		local q = (rank - 0.5) / #order
		local dir = dirs[i]
		if math.acos(math.clamp(dir.Y, -1, 1)) < LAND_REACH then
			q = math.max(q, landFloor)
		end
		if topSet[i] then
			radii[i] = RADIUS
			sea[i] = false
			height[i] = 0.35
		elseif q < planet.SeaShare then
			radii[i] = RADIUS - planet.Bumps * SEA_DROP
			sea[i] = true
			height[i] = 0
		else
			local h = (q - planet.SeaShare) / math.max(1 - planet.SeaShare, 1e-6)
			radii[i] = RADIUS + planet.Bumps * (h * (1 + SEA_DROP) - SEA_DROP)
			sea[i] = false
			height[i] = h
		end
	end

	local neighbors: { { number } } = {}
	for i = 1, #dirs do
		neighbors[i] = {}
	end
	local function link(a: number, b: number)
		if not table.find(neighbors[a], b) then
			table.insert(neighbors[a], b)
		end
	end
	for _, face in ipairs(faces) do
		for k = 1, 3 do
			local a, b = face[k], face[k % 3 + 1]
			link(a, b)
			link(b, a)
		end
	end
	return { dirs = dirs, radii = radii, sea = sea, height = height, faces = faces, top = top, neighbors = neighbors }
end

local function vertexAt(mesh: Mesh, i: number): Vector3
	return restCenter + mesh.dirs[i] * mesh.radii[i]
end

local function faceCorners(mesh: Mesh, face: { number }): (Vector3, Vector3, Vector3)
	return vertexAt(mesh, face[1]), vertexAt(mesh, face[2]), vertexAt(mesh, face[3])
end

local function faceNormal(a: Vector3, b: Vector3, c: Vector3): Vector3
	local normal = (b - a):Cross(c - a).Unit
	if normal:Dot((a + b + c) / 3 - restCenter) < 0 then
		normal = -normal
	end
	return normal
end

local function isSeaFace(mesh: Mesh, face: { number }): boolean
	return mesh.sea[face[1]] and mesh.sea[face[2]] and mesh.sea[face[3]]
end

-- 꼭대기(+Y)에서 잰 면 가운데의 각도(라디안)
local function faceAngle(mesh: Mesh, face: { number }): number
	local dir = (mesh.dirs[face[1]] + mesh.dirs[face[2]] + mesh.dirs[face[3]]).Unit
	return math.acos(math.clamp(dir.Y, -1, 1))
end

local function buildSurface(parent: Instance, mesh: Mesh, planet: Planets.Planet, rng: Random)
	for index, face in ipairs(mesh.faces) do
		local a, b, c = faceCorners(mesh, face)
		local color: Color3
		local material = planet.GroundMaterial
		if isSeaFace(mesh, face) then
			color = shade(planet.Sea, rng:NextNumber(0.96, 1.04))
			material = planet.SeaMaterial
		else
			local h = (mesh.height[face[1]] + mesh.height[face[2]] + mesh.height[face[3]]) / 3
			if index == mesh.top then
				h = 0.35
			end
			if h > 0.82 then
				color = planet.Peak
			else
				local slot = math.clamp(math.floor(h * #planet.Ground) + 1, 1, #planet.Ground)
				color = planet.Ground[slot]
			end
			color = shade(color, rng:NextNumber(0.93, 1.06))
		end
		for _, part in ipairs(triangle(parent, a, b, c, restCenter, SHELL, color, material)) do
			part.Name = if index == mesh.top then "TopFace" else "Ground"
			part.CanCollide = true
			part.CanQuery = true
		end
	end
end

-- 붕괴 균열: 꼭대기 면의 세 꼭짓점과 몇 군데에서 시작해 모서리를 따라 아래로 번지는 빛나는 금
local function buildCracks(parent: Instance, mesh: Mesh, planet: Planets.Planet, rng: Random)
	local topFace = mesh.faces[mesh.top]
	local starts: { number } = { topFace[1], topFace[2], topFace[3] }
	for _ = 1, 4 do
		table.insert(starts, rng:NextInteger(1, #mesh.dirs))
	end
	local used: { [number]: boolean } = {}
	for _, start in ipairs(starts) do
		local current = start
		local origin = mesh.dirs[start]
		used[start] = true
		for _ = 1, rng:NextInteger(4, 8) do
			local bestNext = 0
			local bestScore = -math.huge
			for _, n in ipairs(mesh.neighbors[current]) do
				if not used[n] then
					local score = -mesh.dirs[n]:Dot(origin) + rng:NextNumber(0, 0.25)
					if current == start then
						score -= mesh.dirs[n].Y * 2 -- 첫걸음은 꼭대기에서 멀어지는 쪽으로
					end
					if score > bestScore then
						bestScore = score
						bestNext = n
					end
				end
			end
			if bestNext == 0 then
				break
			end
			local p, q = vertexAt(mesh, current), vertexAt(mesh, bestNext)
			local up = (mesh.dirs[current] + mesh.dirs[bestNext]).Unit
			local middle = (p + q) / 2 + up * 0.8
			local crack = box(parent, "Crack", CFrame.lookAt(middle, middle + (q - p), up), Vector3.new(6, 1.2, (q - p).Magnitude + 6), planet.Crack, Enum.Material.Neon)
			crack.CastShadow = false
			used[bestNext] = true
			current = bestNext
		end
	end
end

-- 면 위의 무작위 점과 그 면의 바깥 방향
local function pointOnFace(mesh: Mesh, face: { number }, rng: Random): (Vector3, Vector3)
	local a, b, c = faceCorners(mesh, face)
	local u, v = rng:NextNumber(), rng:NextNumber()
	if u + v > 1 then
		u, v = 1 - u, 1 - v
	end
	return a + (b - a) * u + (c - a) * v, faceNormal(a, b, c)
end

type Spot = { position: Vector3, radius: number }

local function clearOf(spots: { Spot }, position: Vector3, radius: number): boolean
	if Vector3.new(position.X, 0, position.Z).Magnitude < BASE_CLEAR + radius then
		return false
	end
	for _, spot in ipairs(spots) do
		if (spot.position - position).Magnitude < spot.radius + radius then
			return false
		end
	end
	return true
end

-- 큰 지형지물: 처음 두 개는 외창 쪽(+Z, 선실에서 지평선에 걸쳐 보이는 거리), 다음 두 개는 로켓 뒤쪽(-Z, 발사장·바깥 시점에서 보이는 쪽)에 둠
local function placeLandmarks(parent: Instance, mesh: Mesh, planet: Planets.Planet, rng: Random, spots: { Spot })
	local placed = 0
	for _, entry in ipairs(planet.Landmarks) do
		local builder = BUILDERS[entry.Kind]
		if builder then
			for _ = 1, entry.Count do
				placed += 1
				local onSea = ON_SEA[entry.Kind] == true
				for _ = 1, 24 do
					local azimuth: number
					local reach: number
					if placed <= 2 then
						-- 외창 앞: 지평선 너머에 걸쳐 윗부분만 보이게 (가까우면 창을 다 덮음)
						azimuth = rng:NextNumber(-0.3, 0.3)
						reach = rng:NextNumber(0.5, 0.68)
					elseif placed <= 4 then
						azimuth = math.pi + rng:NextNumber(-0.7, 0.7)
						reach = rng:NextNumber(0.24, 0.5)
					else
						azimuth = rng:NextNumber(0, math.pi * 2)
						reach = rng:NextNumber(0.24, 1.15)
					end
					local want = Vector3.new(math.sin(reach) * math.sin(azimuth), math.cos(reach), math.sin(reach) * math.cos(azimuth))
					local bestFace: { number }? = nil
					local bestDot = -2
					for _, face in ipairs(mesh.faces) do
						if isSeaFace(mesh, face) == onSea then
							local dir = (mesh.dirs[face[1]] + mesh.dirs[face[2]] + mesh.dirs[face[3]]).Unit
							local dot = dir:Dot(want)
							if dot > bestDot then
								bestDot = dot
								bestFace = face
							end
						end
					end
					if bestFace and bestDot > math.cos(0.25) then
						local position, up = pointOnFace(mesh, bestFace, rng)
						local size = rng:NextNumber(0.85, 1.2)
						local footprint = 260 * size
						local flat = Vector3.new(position.X, 0, position.Z)
						if clearOf(spots, position, footprint * 0.8) and (flat - OUTSIDE_CAMERA).Magnitude > footprint + 60 then
							local radius = builder(parent, surfaceFrame(position, up, rng:NextNumber(0, math.pi * 2)), size, entry.Colors, rng)
							table.insert(spots, { position = position, radius = radius })
							break
						end
					end
				end
			end
		end
	end
end

-- 소품: 발사대에 가까운 면일수록 많이
local function placeProps(parent: Instance, mesh: Mesh, planet: Planets.Planet, rng: Random, spots: { Spot })
	local candidates: { { number } } = {}
	local weights: { number } = {}
	local total = 0
	for _, face in ipairs(mesh.faces) do
		local angle = faceAngle(mesh, face)
		if angle <= PROP_REACH and not isSeaFace(mesh, face) then
			local weight = faceArea(mesh, face) * ((1 - angle / PROP_REACH) ^ 1.5 + 0.12)
			table.insert(candidates, face)
			total += weight
			table.insert(weights, total)
		end
	end
	if #candidates == 0 then
		return
	end
	for _, entry in ipairs(planet.Props) do
		local builder = BUILDERS[entry.Kind]
		if builder then
			for _ = 1, entry.Count do
				for _ = 1, 6 do
					local roll = rng:NextNumber(0, total)
					local chosen = candidates[#candidates]
					for i, upTo in ipairs(weights) do
						if roll <= upTo then
							chosen = candidates[i]
							break
						end
					end
					local position, up = pointOnFace(mesh, chosen, rng)
					local size = rng:NextNumber(0.8, 1.45) * (entry.Size or 1)
					if clearOf(spots, position, 14 * size) then
						local radius = builder(parent, surfaceFrame(position, up, rng:NextNumber(0, math.pi * 2)), size, entry.Colors, rng)
						table.insert(spots, { position = position, radius = radius * 0.7 })
						break
					end
				end
			end
		end
	end
end

local function buildSky(parent: Instance, planet: Planets.Planet, rng: Random)
	for _, body in ipairs(planet.Bodies) do
		local builder = BODIES[body.Kind]
		if builder then
			local az, el = math.rad(body.Az), math.rad(body.El)
			local direction = Vector3.new(math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el))
			local radius = SKY_DISTANCE * math.tan(math.rad(body.Size))
			builder(parent, SKY_ORIGIN + direction * SKY_DISTANCE, radius, body.Colors, rng)
		end
	end
end

-- ------------------------------------------------------------ 만들기와 치우기
local function clearPlanet()
	for _, layer in pairs(layers) do
		layer.model:Destroy()
	end
	table.clear(layers)
	if skyFolder then
		skyFolder:Destroy()
		skyFolder = nil
	end
	table.clear(skyParts)
	skyFade = 1
end

local function addLayer(name: string, model: Model)
	model.WorldPivot = CFrame.new(restCenter)
	layers[name] = { model = model, rest = CFrame.new(restCenter), hidden = false, applied = "" }
end

local function build(planet: Planets.Planet, seed: number)
	clearPlanet()
	local rng = Random.new(seed)
	local mesh = makeMesh(planet, rng)
	-- 꼭대기 면이 y = TOP_Y 에 오고, 그 면의 가운데가 로켓 축(x = z = 0) 위에 오도록 행성 중심을 정함
	local topFace = mesh.faces[mesh.top]
	local probeA = mesh.dirs[topFace[1]] * RADIUS
	local probeB = mesh.dirs[topFace[2]] * RADIUS
	local probeC = mesh.dirs[topFace[3]] * RADIUS
	local middle = (probeA + probeB + probeC) / 3
	restCenter = Vector3.new(-middle.X, TOP_Y - middle.Y, -middle.Z)

	local core = Instance.new("Model")
	core.Name = "PlanetCore"
	buildSurface(core, mesh, planet, rng)
	buildCracks(core, mesh, planet, rng)
	local spots: { Spot } = {}
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	placeLandmarks(landmarks, mesh, planet, rng, spots)
	landmarks.Parent = core
	local props = Instance.new("Model")
	props.Name = "PlanetProps"
	placeProps(props, mesh, planet, rng, spots)
	for _, item in ipairs(landmarks:GetDescendants()) do
		if item:IsA("BasePart") and item.Material ~= Enum.Material.Neon then
			item.CastShadow = true
		end
	end
	for _, item in ipairs(props:GetDescendants()) do
		if item:IsA("BasePart") and item.Material ~= Enum.Material.Neon then
			item.CastShadow = true
		end
	end
	addLayer("core", core)
	addLayer("props", props)

	local sky = Instance.new("Folder")
	sky.Name = "RoflySky"
	buildSky(sky, planet, rng)
	for _, item in ipairs(sky:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(skyParts, item)
		end
	end

	-- 다 만든 뒤 한 번에 내놓음 (만드는 도중 조각이 하나씩 보이지 않게)
	local folder = Workspace:FindFirstChild("RoflyPlanet")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RoflyPlanet"
		folder.Parent = Workspace
	end
	core.Parent = folder
	props.Parent = folder
	sky.Parent = folder
	skyFolder = sky
	builtId = planet.Id
end

-- ------------------------------------------------------------ 비행 중 행성 자리
-- 보이는 고도(스터드): 처음 100 스터드쯤은 실제 높이, 그 뒤는 km^0.381 로 느리게 (둘 중 작은 쪽을 부드럽게 고름)
function Planet.visualAltitude(km: number): number
	if km <= 0 then
		return 0
	end
	local trueAltitude = km * TRUE_STUDS_PER_KM
	local farAltitude = FAR_SCALE * km ^ FAR_POWER
	return (trueAltitude ^ -3 + farAltitude ^ -3) ^ (-1 / 3)
end

-- 행성 가운데가 화면에 놓일 높이각(도, 아래가 -)과 옆으로 비킬 방위(도). alpha = 행성이 보이는 각반지름(도)
function Planet.placement(alpha: number, inside: boolean): (number, number)
	if inside then
		-- 선실 외창(높이각 약 -13 ~ +8도): 크면 지평선(공의 위 끝)을 -5도에 두고, 작아질수록 위 끝을 +6도까지 올림.
		-- 각반지름 7.5도 이하면 공이 통째로 창 안(-1.5도 중심, 창 아래쪽의 내 캐릭터 머리 위)에 들어옴. 위 끝이 창 위로 넘어가지 않음
		local top: number
		if alpha <= 7.5 then
			top = -1.5 + alpha
		else
			top = lerp(6, -5, smoothstep((alpha - 7.5) / 22.5))
		end
		return top - alpha, 0
	end
	-- 바깥 시점(화면 아래 끝 약 -26도): 크면 지평선을 -10도에, 작아지면 로켓과 화면 아래 미션 판에 덜 가리게 왼쪽 위(27도, -9도)로
	local t = smoothstep((alpha - 12) / 23)
	return lerp(-9, -10 - alpha, t), lerp(27, 0, t)
end

-- 카메라 위치와 거리(km)로 행성의 자리를 계산: 행성 중심 위치, 회전, 크기 배율.
-- 쉬는 자세(발사대 위)는 center = restCenter, rotation = 회전 없음, scale = 1.
function Planet.pose(km: number, camera: Vector3, center0: Vector3): (Vector3, CFrame, number)
	local altitude = Planet.visualAltitude(km)
	local raised = camera + Vector3.new(0, altitude, 0) -- 행성 쪽에서 보면 카메라가 이만큼 올라간 셈
	local toCenter = center0 - raised
	local distance = toCenter.Magnitude
	local flat = Vector3.new(toCenter.X, 0, toCenter.Z)
	local across = flat.Magnitude
	local axisDistance = Vector3.new(camera.X, 0, camera.Z).Magnitude
	local inside = axisDistance < INSIDE_RADIUS
	local toward = if across > 1 then flat / across else Vector3.new(0, 0, 1)
	local alpha = math.deg(math.asin(math.clamp(RADIUS / distance, 0, 1)))
	local trueElevation = math.atan2(toCenter.Y, across)
	local farElevation, farAzimuth = Planet.placement(alpha, inside)
	local weight = if inside then 1 else smoothstep(altitude / OUTSIDE_RAMP)
	local elevation = lerp(trueElevation, math.rad(farElevation), weight)
	local azimuth = math.rad(farAzimuth) * weight
	local sideways = CFrame.Angles(0, azimuth, 0):VectorToWorldSpace(toward)
	local direction = sideways * math.cos(elevation) + Vector3.new(0, math.sin(elevation), 0)
	local scale = 1
	if distance > MAX_DISTANCE then
		-- 계단식 배율 (가까이 두는 거리도 같은 배율로 줄이므로 카메라에서 보이는 크기는 그대로)
		local steps = math.ceil(math.log(distance / MAX_DISTANCE, 2) * SCALE_STEPS)
		scale = 2 ^ (-steps / SCALE_STEPS)
	end
	local center = camera + direction * distance * scale
	-- 행성 중심에서 (올라간) 카메라로 향하던 방향이 이제 행성 중심에서 실제 카메라로 향하도록 돌림
	local from = (-toCenter).Unit
	local to = -direction
	local axis = from:Cross(to)
	local rotation = CFrame.new()
	if axis.Magnitude > 1e-7 then
		rotation = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(from:Dot(to), -1, 1)))
	end
	return center, rotation, scale
end

local function placeModel(model: Model, rest: CFrame, center: Vector3, rotation: CFrame, scale: number)
	if math.abs(model:GetScale() - scale) > 1e-5 then
		model:ScaleTo(scale)
	end
	local offset = rotation:VectorToWorldSpace(rest.Position - restCenter) * scale
	model:PivotTo(CFrame.new(center + offset) * rotation * rest.Rotation)
end

local function poseKey(center: Vector3, rotation: CFrame, scale: number): string
	local look = rotation.LookVector
	local up = rotation.UpVector
	return string.format("%.2f,%.2f,%.2f|%.5f,%.5f,%.5f,%.5f,%.5f,%.5f|%.5f", center.X, center.Y, center.Z, look.X, look.Y, look.Z, up.X, up.Y, up.Z, scale)
end

local function applyPose(center: Vector3, rotation: CFrame, scale: number, hideProps: boolean)
	local key = poseKey(center, rotation, scale)
	for name, layer in pairs(layers) do
		local hide = name == "props" and hideProps
		if hide ~= layer.hidden then
			layer.hidden = hide
			layer.model.Parent = if hide then nil else Workspace:FindFirstChild("RoflyPlanet")
		end
		if not hide and layer.applied ~= key then
			placeModel(layer.model, layer.rest, center, rotation, scale)
			layer.applied = key
		end
	end
	if #padParts > 0 and padApplied ~= key then
		local resize = scale ~= padScale
		for _, entry in ipairs(padParts) do
			if resize then
				entry.part.Size = entry.size * scale
			end
			local offset = rotation:VectorToWorldSpace(entry.cframe.Position - restCenter) * scale
			entry.part.CFrame = CFrame.new(center + offset) * rotation * entry.cframe.Rotation
		end
		padScale = scale
		padApplied = key
	end
end

local function setSkyFade(fade: number)
	if math.abs(fade - skyFade) < 0.02 and not (fade == 0 or fade == 1) then
		return
	end
	if fade == skyFade then
		return
	end
	skyFade = fade
	for _, part in ipairs(skyParts) do
		part.LocalTransparencyModifier = 1 - fade
	end
end

local function findPad()
	local rofly = Workspace:WaitForChild("Rofly")
	local found = rofly:WaitForChild("Pad")
	found:WaitForChild("Spawn", 10) -- 서버가 마지막에 넣는 파트 (광장이 다 들어왔는지)
	for _, item in ipairs(found:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(padParts, { part = item, cframe = item.CFrame, size = item.Size })
		end
	end
end

-- ------------------------------------------------------------ 매 프레임
function Planet.init()
	task.spawn(findPad)
end

function Planet.update(_dt: number)
	local aboard = State.aboard()
	local phase = State.phase()

	-- 행성이 바뀌었으면(씨앗이 바뀜) 다시 만듦. 서버는 판이 끝나 모두 내린 뒤에 바꾸지만,
	-- 정산 화면을 보는 중에 먼저 도착하면 내릴 때까지 기다림 (멀어진 행성이 갑자기 바뀌지 않게)
	local id = State.text("Planet")
	local seed = State.number("PlanetSeed")
	local waiting = aboard and phase == "Results" and builtId ~= ""
	if id ~= "" and seed ~= builtSeed and not waiting then
		local planet = Planets.get(id)
		builtSeed = seed
		build(planet, seed)
		toastPending = "이번 행성: " .. planet.Name
		anchor = nil
		lastApply = 0
	end

	if toastPending ~= "" and not aboard then
		State.emit("Toast", toastPending)
		toastPending = ""
	end

	local camera = Workspace.CurrentCamera
	local center, rotation, scale = restCenter, CFrame.new(), 1
	local altitude = 0
	local km = 0
	if aboard and camera then
		local position = camera.CFrame.Position
		if anchor == nil or (position - (anchor :: Vector3)).Magnitude > ANCHOR_MOVE then
			anchor = position
			lastApply = 0 -- 시점이 바뀌었으면 바로 옮김 (한 프레임이라도 다른 시점용 자리에 있지 않게)
		end
		if phase == "Flight" then
			km = math.max(State.flight.km, 0)
			lastFlightKm = km
		elseif phase == "Results" then
			km = math.max(State.flight.km, lastFlightKm, 0)
		end
		altitude = Planet.visualAltitude(km)
		center, rotation, scale = Planet.pose(km, anchor :: Vector3, restCenter)
	else
		anchor = nil
		lastFlightKm = 0
	end

	-- 멀리 있을 때는 초당 20번만 옮김 (움직임이 작아서 티가 나지 않음)
	local clock = os.clock()
	local hideProps = altitude > PROPS_HIDE_ALTITUDE
	if altitude > NEAR_ALTITUDE and lastApply > 0 and clock - lastApply < SLOW_INTERVAL then
		return
	end
	lastApply = clock
	applyPose(center, rotation, scale, hideProps)

	-- 하늘 천체는 고향 하늘(1단계)에서만 보이고, 폭풍 구름층으로 들어가며 사라짐
	setSkyFade(1 - smoothstep((km - 2.5) / 2))
end

-- 검사용
Planet._internal = {
	radius = RADIUS,
	restCenter = function(): Vector3
		return restCenter
	end,
	layers = layers,
}

return Planet
