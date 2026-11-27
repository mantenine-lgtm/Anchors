local LaunchPad = {}

export type Opts = {
	plazaRadius: number,
	mountRadius: number,
	mountY: number,
	hullRadius: number,
	armY: number,
	spawnDistance: number,
}

local METAL = Enum.Material.Metal
local CONCRETE = Enum.Material.Concrete
local TREAD = Enum.Material.DiamondPlate
local PAINT = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local STEEL = Color3.fromRGB(115, 125, 135)
local DARK = Color3.fromRGB(49, 55, 63)
local CEMENT = Color3.fromRGB(113, 116, 118)
local PLAZA = Color3.fromRGB(96, 100, 110)
local TANK = Color3.fromRGB(182, 195, 201)
local YELLOW = Color3.fromRGB(232, 179, 59)
local TOWER = Color3.fromRGB(104, 78, 68)
local RIM = Color3.fromRGB(130, 228, 248)
local LAMP = Color3.fromRGB(255, 241, 207)

local function ringPoint(angleDeg: number, radius: number, y: number): Vector3
	local theta = math.rad(angleDeg)
	return Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius)
end

local function radialFrame(angle: number, radius: number, y: number): CFrame
	return CFrame.new(ringPoint(angle, radius, y)) * CFrame.Angles(0, math.rad(angle), 0)
end

local function part(parent: Instance, className: string, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean, shape: Enum.PartType?): BasePart
	local item = Instance.new(className) :: BasePart
	if shape then
		(item :: Part).Shape = shape
	end
	item.Name = name
	item.Anchored = true
	item.CanCollide = solid
	item.CanQuery = solid
	item.CanTouch = solid
	item.CastShadow = solid
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Size = size
	item.CFrame = frame
	item.Color = color
	item.Material = material
	item.Parent = parent
	return item
end

local function block(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean): BasePart
	return part(parent, "Part", name, size, frame, color, material, solid)
end

local function cylinderAlong(parent: Instance, name: string, a: Vector3, b: Vector3, radius: number, color: Color3, material: Enum.Material, solid: boolean): BasePart
	local axis = (b - a).Unit
	local reference = Vector3.yAxis
	if math.abs(axis.Y) > 0.99 then
		reference = Vector3.zAxis
	end
	local back = axis:Cross(reference).Unit
	local up = back:Cross(axis)
	return part(parent, "Part", name, Vector3.new((b - a).Magnitude, radius * 2, radius * 2),
		CFrame.fromMatrix((a + b) / 2, axis, up, back), color, material, solid, Enum.PartType.Cylinder)
end

local function truss(parent: Instance, name: string, a: Vector3, b: Vector3, normal: Vector3, color: Color3, solid: boolean)
	local offset = b - a
	local up = offset.Unit
	local right = up:Cross(normal).Unit
	-- TrussPart uses local Y for its length and builds in two-stud sections.
	local length = math.ceil(offset.Magnitude / 2) * 2
	part(parent, "TrussPart", name, Vector3.new(2, length, 2),
		CFrame.fromMatrix((a + b) / 2, right, up, right:Cross(up)), color, METAL, solid)
end

local function buildMount(parent: Instance, opts: Opts)
	local r, y = opts.mountRadius, opts.mountY
	cylinderAlong(parent, "MountFoundation", Vector3.new(0, -0.6, 0), Vector3.new(0, y - 0.75, 0),
		r, CEMENT, CONCRETE, true)
	cylinderAlong(parent, "Mount", Vector3.new(0, y - 0.75, 0), Vector3.new(0, y, 0),
		r, DARK, TREAD, true)

	local outlet = radialFrame(157, r + 12, 0)
	block(parent, "FlameChannel", Vector3.new(14, 0.14, 29),
		outlet * CFrame.new(0, 0.055, 0), DARK, Enum.Material.Basalt, false)
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "ChannelWall", Vector3.new(2.6, 2.2, 29),
			outlet * CFrame.new(side * 8.1, 1.1, 0), CEMENT, CONCRETE, true)
	end
	part(parent, "WedgePart", "FlameDeflector", Vector3.new(13, y - 0.2, 12),
		outlet * CFrame.new(0, (y - 0.2) / 2, -7) * CFrame.Angles(0, math.pi, 0),
		STEEL, Enum.Material.CorrodedMetal, true)
end

local function buildMarkings(parent: Instance, opts: Opts)
	local radius = opts.mountRadius + 11
	cylinderAlong(parent, "YellowRing", Vector3.new(0, -0.03, 0), Vector3.new(0, 0.05, 0),
		radius, YELLOW, PAINT, false)
	cylinderAlong(parent, "YellowRingInner", Vector3.new(0, 0.015, 0), Vector3.new(0, 0.095, 0),
		radius - 1.45, PLAZA, CONCRETE, false)

	for _, angle in ipairs({ 82, 275 }) do
		local strip = radialFrame(angle, opts.mountRadius + 5, 0.12)
		for i = -1, 1 do
			local color = YELLOW
			if i == 0 then
				color = DARK
			end
			block(parent, "HazardStripe", Vector3.new(2.6, 0.08, 5.5),
				strip * CFrame.new(i * 3.0, 0, 0) * CFrame.Angles(0, math.rad(25), 0),
				color, PAINT, false)
		end
	end

	local spawn = Vector3.new(0, 0, opts.spawnDistance)
	local rimRadius = opts.plazaRadius - 3.4
	for i = 0, 11 do
		local angle = 52 + 256 * i / 11
		local at = ringPoint(angle, rimRadius, 0)
		if (at - spawn).Magnitude > 24 then
			block(parent, "RimLight", Vector3.new(6.2, 0.22, 1.5), radialFrame(angle, rimRadius, 0.1075), RIM, NEON, false)
		end
	end
end

local function buildTower(parent: Instance, opts: Opts)
	local x = math.max(opts.hullRadius + 34, opts.mountRadius + 18)
	local levels = { 6, 70, 134, 202 }
	local low, high = levels[1], levels[#levels]
	local corners = {
		Vector3.new(x - 8, 0, -8), Vector3.new(x + 8, 0, -8),
		Vector3.new(x + 8, 0, 8), Vector3.new(x - 8, 0, 8),
	}
	block(parent, "TowerBase", Vector3.new(27, low, 27), CFrame.new(x, low / 2, 0), CEMENT, CONCRETE, true)
	for side, a in ipairs(corners) do
		local b = corners[side % #corners + 1]
		local normal = Vector3.yAxis:Cross(b - a).Unit
		truss(parent, "TowerColumn", a + Vector3.yAxis * low, a + Vector3.yAxis * high, Vector3.zAxis, TOWER, true)
		for bay = 1, #levels - 1 do
			local y0 = Vector3.yAxis * levels[bay]
			local y1 = Vector3.yAxis * levels[bay + 1]
			local from, to = a, b
			if (bay + side) % 2 == 0 then
				from, to = b, a
			end
			truss(parent, "TowerDiagonal", from + y0, to + y1, normal, TOWER, false)
			if bay > 1 then
				truss(parent, "TowerCrossmember", a + y0, b + y0, normal, STEEL, false)
			end
		end
	end
	block(parent, "TowerCap", Vector3.new(21, 2.4, 21), CFrame.new(x, high + 1.2, 0), DARK, TREAD, true)
	block(parent, "HoistHousing", Vector3.new(11, 6.2, 9), CFrame.new(x, high + 5.5, 0), TOWER, METAL, false)
	block(parent, "HoistBeacon", Vector3.new(1.5, 0.55, 1.5), CFrame.new(x, high + 8.87, 0), YELLOW, NEON, false)

	local inner, outer = opts.hullRadius + 1, x + 3
	local y = opts.armY
	block(parent, "TowerArm", Vector3.new(outer - inner, 2, 7.2), CFrame.new((inner + outer) / 2, y, 0), DARK, TREAD, true)
	for _, side in ipairs({ -1, 1 }) do
		local z = side * 3.2
		truss(parent, "ArmRail", Vector3.new(inner + 1.3, y + 1.9, z), Vector3.new(outer - 1.2, y + 1.9, z),
			Vector3.zAxis, YELLOW, false)
		local a = Vector3.new(inner + 6, y - 1, z)
		local b = Vector3.new(x - 8, y - 15, z)
		block(parent, "ArmBrace", Vector3.new(1.45, 1.45, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b), TOWER, METAL, false)
	end
end

local function fuelTank(parent: Instance, angle: number, distance: number, radius: number, height: number, mountRadius: number)
	local base = ringPoint(angle, distance, 0)
	local cap = base + Vector3.yAxis * height
	cylinderAlong(parent, "FuelTank", base, cap, radius, TANK, METAL, true)
	part(parent, "Part", "TankDome", Vector3.one * (radius * 2), CFrame.new(cap), TANK, METAL, true, Enum.PartType.Ball)
	cylinderAlong(parent, "TankBand", base + Vector3.yAxis * (height * 0.58), base + Vector3.yAxis * (height * 0.58 + 1.8),
		radius + 0.18, YELLOW, PAINT, false)
	local start = ringPoint(angle, distance - radius + 0.8, 2.4)
	local finish = ringPoint(angle, mountRadius - 0.12, 2.4)
	cylinderAlong(parent, "FuelPipe", start, finish, 1.14, STEEL, METAL, false)
end

local function floodlight(parent: Instance, angle: number, distance: number, height: number)
	local base = ringPoint(angle, distance, 0)
	local top = base + Vector3.yAxis * height
	cylinderAlong(parent, "FloodlightMast", base, top, 1.24, STEEL, METAL, false)
	local aiming = CFrame.lookAt(top, ringPoint(angle, 93, 1))
	block(parent, "FloodlightHousing", Vector3.new(7.6, 3.4, 1.8), aiming, DARK, METAL, false)
	local lens = block(parent, "MastLamp", Vector3.new(6.6, 2.45, 0.2),
		aiming * CFrame.new(0, 0, -0.96), LAMP, NEON, false)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 86
	light.Range = 60
	light.Brightness = 2.1
	light.Shadows = false
	light.Color = LAMP
	light.Parent = lens
end

local function buildBunker(parent: Instance)
	local frame = radialFrame(120, 115, 0)
	block(parent, "ControlBunker", Vector3.new(27, 11, 16), frame * CFrame.new(0, 5.5, 0), CEMENT, CONCRETE, true)
	block(parent, "BunkerRoof", Vector3.new(29, 1.8, 18), frame * CFrame.new(0, 11.9, 0), DARK, METAL, true)
	block(parent, "BunkerDoor", Vector3.new(4, 6.7, 0.38), frame * CFrame.new(-9, 3.35, -8.1), DARK, TREAD, false)
	block(parent, "ControlWindow", Vector3.new(15.6, 2.55, 0.35), frame * CFrame.new(3.2, 7.5, -8.11),
		Color3.fromRGB(69, 111, 125), NEON, false)
end

local function buildCargo(parent: Instance)
	for _, spot in ipairs({ { 138, 102 }, { 144, 110 } }) do
		local frame = radialFrame(spot[1], spot[2], 0) * CFrame.Angles(0, math.rad(17), 0)
		block(parent, "CargoCrate", Vector3.new(5.4, 4.5, 4.6), frame * CFrame.new(0, 2.25, 0),
			Color3.fromRGB(139, 106, 72), Enum.Material.WoodPlanks, false)
	end
	local at = ringPoint(132, 107, 0)
	cylinderAlong(parent, "UtilityBarrel", at, at + Vector3.yAxis * 4.05, 1.54,
		Color3.fromRGB(92, 103, 110), Enum.Material.CorrodedMetal, false)
end

function LaunchPad.build(pad: Model, opts: Opts): ()
	buildMount(pad, opts)
	buildMarkings(pad, opts)
	buildTower(pad, opts)
	fuelTank(pad, 188, 111, 10.4, 28, opts.mountRadius)
	fuelTank(pad, 214, 103, 9.6, 33, opts.mountRadius)
	fuelTank(pad, 244, 112, 10.8, 25, opts.mountRadius)
	fuelTank(pad, 273, 107, 8.2, 30, opts.mountRadius)
	floodlight(pad, 62, 128, 42)
	floodlight(pad, 307, 126, 48)
	buildBunker(pad)
	buildCargo(pad)
end

return LaunchPad
