local LaunchPad = {}

export type Opts = {
	plazaRadius: number,
	mountRadius: number,
	mountY: number,
	hullRadius: number,
	armY: number,
	spawnDistance: number,
}

local CONCRETE = Enum.Material.Concrete
local METAL = Enum.Material.Metal
local TREAD = Enum.Material.DiamondPlate
local COOLED = Enum.Material.CorrodedMetal
local NEON = Enum.Material.Neon
local PAINT = Enum.Material.SmoothPlastic

local FOOTING = Color3.fromRGB(64, 70, 72)
local PIER = Color3.fromRGB(137, 146, 146)
local CAP = Color3.fromRGB(88, 102, 105)
local STEEL = Color3.fromRGB(126, 139, 143)
local ARMOR = Color3.fromRGB(36, 46, 53)
local OPERATIONS = Color3.fromRGB(153, 160, 157)
local CLADDING = Color3.fromRGB(182, 184, 172)
local TRAY = Color3.fromRGB(47, 53, 54)
local ASPHALT = Color3.fromRGB(74, 81, 83)
local GUIDE = Color3.fromRGB(214, 141, 78)
local PALE = Color3.fromRGB(170, 180, 169)
local RIM = Color3.fromRGB(142, 232, 217)
local LAMP = Color3.fromRGB(255, 239, 201)

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function radialFrame(angle: number, radius: number): CFrame
	local theta = math.rad(angle)
	return CFrame.new(math.sin(theta) * radius, 0, math.cos(theta) * radius) * CFrame.Angles(0, theta, 0)
end

local function finish(part: BasePart, parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean)
	part.Name = name
	part.Anchored = true
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = solid
	part.CastShadow = solid
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Material = material
	part.Size = size
	part.CFrame = frame
	part.Parent = parent
end

local function block(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean): Part
	local part = Instance.new("Part")
	finish(part, parent, name, size, frame, color, material, solid)
	return part
end

local function wedge(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean)
	finish(Instance.new("WedgePart"), parent, name, size, frame, color, material, solid)
end

local function disc(parent: Instance, name: string, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	finish(part, parent, name, Vector3.new(y1 - y0, 2 * radius, 2 * radius),
		CFrame.new(0, (y0 + y1) / 2, 0) * UPRIGHT, color, material, true)
end

local function lamp(parent: Instance, position: Vector3, target: Vector3)
	local aiming = CFrame.lookAt(position, target)
	block(parent, "MastHousing", Vector3.new(7.8, 2.9, 1.9), aiming, ARMOR, METAL, false)
	local lens = block(parent, "MastLamp", Vector3.new(6.8, 1.9, 0.18),
		aiming * CFrame.new(0, 0, -1), LAMP, NEON, false)
	local spotlight = Instance.new("SpotLight")
	spotlight.Face = Enum.NormalId.Front
	spotlight.Range = 60
	spotlight.Angle = 73
	spotlight.Brightness = 2.1
	spotlight.Color = LAMP
	spotlight.Shadows = false
	spotlight.Parent = lens
end

local function buildMount(parent: Instance, opts: Opts)
	local r, y = opts.mountRadius, opts.mountY
	disc(parent, "MountFoundation", r, -0.6, y - 1.05, FOOTING, CONCRETE)
	disc(parent, "Mount", r, y - 1.05, y, ARMOR, TREAD)

	local apron = radialFrame(303, r + 12)
	block(parent, "BlastApron", Vector3.new(37, 0.18, 46),
		apron * CFrame.new(0, 0.07, 0), ASPHALT, CONCRETE, false)
	block(parent, "SpillTray", Vector3.new(22, 0.26, 44),
		apron * CFrame.new(0, 0.20, 0.5), TRAY, COOLED, false)
	for _, side in ipairs({ -1, 1 }) do
		-- The wide end of each vane is under the mount lip.
		wedge(parent, "ApronVane", Vector3.new(4.6, 3.4, 32),
			apron * CFrame.new(side * 12.5, 1.7, -3) * CFrame.Angles(0, math.pi, 0), FOOTING, CONCRETE, true)
		block(parent, "ApronStripe", Vector3.new(1.5, 0.08, 13),
			apron * CFrame.new(side * 16.1, 0.178, 15), GUIDE, PAINT, false)
	end
end

local POST_OFFSET = 7.2

local function pierFrame(towerX: number, side: number): CFrame
	return CFrame.new(towerX - side * 8, 0, side * 15) * CFrame.Angles(0, math.rad(-8), 0)
end

local function gateBrace(parent: Instance, frame: CFrame, a: Vector3, b: Vector3)
	local start = frame:PointToWorldSpace(a)
	local finishPoint = frame:PointToWorldSpace(b)
	local along = (finishPoint - start).Unit
	local normal = frame.ZVector
	block(parent, "GateBrace", Vector3.new(1.7, 3.15, (finishPoint - start).Magnitude),
		CFrame.fromMatrix((start + finishPoint) / 2, normal, along:Cross(normal), along), CAP, METAL, false)
end

local function buildGantry(parent: Instance, opts: Opts)
	local x = math.max(87, opts.hullRadius + 42)
	for _, side in ipairs({ -1, 1 }) do
		local pier = pierFrame(x, side)
		local pierX, pierZ = pier.Position.X, pier.Position.Z
		block(parent, "PierFooting", Vector3.new(22, 8, 15),
			CFrame.new(pierX, 4, pierZ), FOOTING, CONCRETE, true)
		for _, postSide in ipairs({ -1, 1 }) do
			block(parent, "GatePier", Vector3.new(4.7, 162, 7.2),
				pier * CFrame.new(postSide * POST_OFFSET, 89, 0), PIER, CONCRETE, true)
		end
		-- The heel tapers upward against the outer post, beside the open portal.
		wedge(parent, "PierHeel", Vector3.new(11.5, 6.2, 65),
			CFrame.fromMatrix(Vector3.new(pierX + 9.95, 40.5, pierZ), -Vector3.zAxis, Vector3.xAxis, -Vector3.yAxis),
			CAP, CONCRETE, true)
		block(parent, "PierShoulder", Vector3.new(18.5, 10, 14.4),
			CFrame.new(pierX, 171, pierZ), ARMOR, METAL, true)
		block(parent, "PierGuide", Vector3.new(1.25, 96, 0.26),
			pier * CFrame.new(POST_OFFSET, 95, 3.68), STEEL, METAL, false)

		local deckY, braceLow, braceHigh = 58, 58, 104
		if side == -1 then
			deckY, braceLow, braceHigh = 147, 104, 147
		end
		for _, direction in ipairs({ -1, 1 }) do
			-- Offset the two chords so the cross has no coplanar faces.
			local z = direction * 0.87
			gateBrace(parent, pier, Vector3.new(-direction * POST_OFFSET, braceLow, z),
				Vector3.new(direction * POST_OFFSET, braceHigh, z))
		end
		block(parent, "MaintenanceDeck", Vector3.new(21.6, 2.8, 12.1),
			pier * CFrame.new(0, deckY, 0.32), ARMOR, TREAD, true)
		block(parent, "RimLight", Vector3.new(11.6, 0.88, 0.24),
			pier * CFrame.new(0, deckY, 6.44), RIM, NEON, false)
	end

	block(parent, "GateHeader", Vector3.new(36, 16, 46), CFrame.new(x, 184, 0), ARMOR, METAL, true)
	block(parent, "HeaderCap", Vector3.new(37.2, 2.5, 46.8), CFrame.new(x, 193.1, 0), STEEL, METAL, true)
	block(parent, "RimLight", Vector3.new(26, 1.52, 0.28), CFrame.new(x, 185, 23.08), RIM, NEON, false)

	local inner, outer = opts.hullRadius + 1, x + 3
	local y = opts.armY
	block(parent, "TransferGirder", Vector3.new(24, 4, 35.5), CFrame.new(x, y - 3, 0), ARMOR, METAL, true)
	block(parent, "TowerArm", Vector3.new(outer - inner, 2, 12.4),
		CFrame.new((inner + outer) / 2, y, 0), ARMOR, TREAD, true)
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "BridgeCurb", Vector3.new(outer - inner - 1.4, 1.7, 0.9),
			CFrame.new((inner + outer) / 2, y + 1.75, side * 5.6), GUIDE, METAL, true)
		local a = Vector3.new(inner + 10, y - 1.2, side * 4.6)
		local b = pierFrame(x, side):PointToWorldSpace(Vector3.new(-POST_OFFSET, y - 20, -side * 3.05))
		block(parent, "BridgeBrace", Vector3.new(1.7, 2.2, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b), CAP, METAL, false)
	end

	block(parent, "LampBracket", Vector3.new(5, 2.5, 5.5), CFrame.new(x - 16.2, 37, 16.3), CAP, METAL, false)
	lamp(parent, Vector3.new(x - 18, 36.6, 16.3), Vector3.new(31, 2, 30))
end

local function buildOperations(parent: Instance)
	local site = CFrame.new(-107, 0, -10) * CFrame.Angles(0, math.rad(28), 0)
	block(parent, "OperationsFooting", Vector3.new(56, 1.35, 31),
		site * CFrame.new(0, 0.675, 0), FOOTING, CONCRETE, true)
	block(parent, "OperationsHall", Vector3.new(52, 9.2, 28),
		site * CFrame.new(0, 5.9, 0), OPERATIONS, CONCRETE, true)
	block(parent, "OperationsTerrace", Vector3.new(53, 0.9, 29.5),
		site * CFrame.new(0, 10.78, 0.25), ARMOR, METAL, true)
	block(parent, "ControlHall", Vector3.new(38, 8.15, 21),
		site * CFrame.new(-5, 15.27, -3), CLADDING, CONCRETE, true)
	block(parent, "ControlCanopy", Vector3.new(42, 1.7, 24),
		site * CFrame.new(-5, 20.1, -2.2), ARMOR, METAL, true)
	block(parent, "WindowRecess", Vector3.new(32.6, 3, 0.55),
		site * CFrame.new(-5, 15.45, 7.56), ARMOR, METAL, false)
	block(parent, "ControlWindow", Vector3.new(30.9, 2.23, 0.18),
		site * CFrame.new(-5, 15.45, 7.89), RIM, NEON, false)

	for _, x in ipairs({ -14.5, 4.5 }) do
		block(parent, "SealedBay", Vector3.new(12, 6.2, 0.52),
			site * CFrame.new(x, 4.62, 14.02), ARMOR, TREAD, false)
		block(parent, "RimLight", Vector3.new(10.8, 0.93, 0.24),
			site * CFrame.new(x, 6.35, 14.36), RIM, NEON, false)
		block(parent, "BayThreshold", Vector3.new(12.7, 0.25, 2.6),
			site * CFrame.new(x, 1.395, 15.0), GUIDE, METAL, false)
	end
	wedge(parent, "ShelfShoulder", Vector3.new(5.2, 8.2, 15),
		site * CFrame.new(29.1, 4.12, -1.2) * CFrame.Angles(0, -math.pi / 2, 0), OPERATIONS, CONCRETE, true)
	block(parent, "LampBracket", Vector3.new(4, 2.5, 4.5),
		site * CFrame.new(11.8, 20.9, 7.3), CAP, METAL, false)
	lamp(parent, site:PointToWorldSpace(Vector3.new(11.8, 22, 9.1)), Vector3.new(-53, 1, 23))
end

local function buildWayfinding(parent: Instance, opts: Opts)
	local entrance0 = opts.mountRadius + 2.5
	local entrance1 = opts.spawnDistance - 23
	local exit0 = opts.spawnDistance + 23
	local exit1 = opts.plazaRadius - 8
	for _, section in ipairs({ { entrance0, entrance1 }, { exit0, exit1 } }) do
		local z0, z1 = section[1], section[2]
		local width, length = 29, z1 - z0
		block(parent, "BoardingLane", Vector3.new(width, 0.12, length),
			CFrame.new(0, 0.052, (z0 + z1) / 2), ASPHALT, CONCRETE, false)
		for _, side in ipairs({ -1, 1 }) do
			for step = 0, 2 do
				local center = z0 + (step + 0.5) * length / 3
				block(parent, "LaneDash", Vector3.new(1.2, 0.08, length * 0.245),
					CFrame.new(side * 10.9, 0.144, center), GUIDE, PAINT, false)
			end
			block(parent, "LaneThreshold", Vector3.new(5.0, 0.08, 0.65),
				CFrame.new(side * 7.0, 0.144, z0 + 1.0), PALE, PAINT, false)
		end
	end
	for _, angle in ipairs({ 47, 63, 83, 108, 133, 159, 185, 217, 245, 272, 299, 322 }) do
		local frame = radialFrame(angle, opts.plazaRadius - 4.1)
		block(parent, "RimLight", Vector3.new(5.9, 0.24, 1.7),
			frame * CFrame.new(0, 0.113, 0), RIM, NEON, false)
	end
end

function LaunchPad.build(pad: Model, opts: Opts): ()
	buildMount(pad, opts)
	buildGantry(pad, opts)
	buildOperations(pad)
	buildWayfinding(pad, opts)
end

return LaunchPad
