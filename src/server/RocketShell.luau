local RocketShell = {}

export type Opts = {
	hullRadius: number,
	mountY: number,
	baseY: number,
	cabinFloorY: number,
	cabinCeilY: number,
	topY: number,
	windowBottomY: number,
	windowTopY: number,
	windows: { { centerDeg: number, halfDeg: number } },
}

local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate
local SATIN = Color3.fromRGB(178, 190, 195)
local NOSE = Color3.fromRGB(201, 212, 216)
local CHINE = Color3.fromRGB(126, 144, 153)
local SHADE = Color3.fromRGB(89, 108, 119)
local THERMAL = Color3.fromRGB(39, 48, 54)
local BRONZE = Color3.fromRGB(128, 104, 78)
local SILT = Color3.fromRGB(77, 63, 50)
local CYLINDER_UP = CFrame.Angles(0, 0, math.pi / 2)

local function place(parent: Instance, part: BasePart, name: string, size: Vector3, frame: CFrame,
	color: Color3, material: Enum.Material, solid: boolean, heat: number?): BasePart
	part.Name = name
	part.Size = size
	part.CFrame = frame
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid
	part.CanTouch = solid
	part.CanQuery = solid
	part.CastShadow = solid
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if heat then
		part:SetAttribute("Heat", heat)
	end
	part.Parent = parent
	return part
end

local function box(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3,
	material: Enum.Material, solid: boolean, heat: number?): BasePart
	return place(parent, Instance.new("Part"), name, size, frame, color, material, solid, heat)
end

local function wedge(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3,
	material: Enum.Material, heat: number?): BasePart
	return place(parent, Instance.new("WedgePart"), name, size, frame, color, material, true, heat)
end

local function cylinder(parent: Instance, name: string, radius: number, x: number, z: number,
	y0: number, y1: number, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	return place(parent, part, name, Vector3.new(y1 - y0, 2 * radius, 2 * radius),
		CFrame.new(x, (y0 + y1) / 2, z) * CYLINDER_UP, color, material, true)
end

local function octagon(y: number, x: number, z: number, bevel: number): { Vector3 }
	return {
		Vector3.new(-x + bevel, y, z), Vector3.new(x - bevel, y, z),
		Vector3.new(x, y, z - bevel), Vector3.new(x, y, -z + bevel),
		Vector3.new(x - bevel, y, -z), Vector3.new(-x + bevel, y, -z),
		Vector3.new(-x, y, -z + bevel), Vector3.new(-x, y, z - bevel),
	}
end

-- The upper and lower edges are parallel. The common width is a single steel
-- plate. The remaining triangles lie on the exact same outer plane.
local function panel(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	depth: number, color: Color3, material: Enum.Material, heat: number?): BasePart
	local across = (b - a).Unit
	local lowerRight = (b - a).Magnitude
	local upperLeft = (d - a):Dot(across)
	local upperRight = (c - a):Dot(across)
	local lift = d - a - across * upperLeft
	local up = lift.Unit
	local outward = across:Cross(up)
	local origin = a + lift / 2 - outward * (depth / 2)
	local left = math.max(0, upperLeft)
	local right = math.min(lowerRight, upperRight)
	local center = box(parent, name, Vector3.new(right - left, lift.Magnitude, depth),
		CFrame.fromMatrix(origin + across * ((left + right) / 2), across, up, outward), color, material, true, heat)

	for side, ends in ipairs({ { 0, upperLeft }, { lowerRight, upperRight } }) do
		local bottom, top = ends[1], ends[2]
		local difference = top - bottom
		if math.abs(difference) > 0.005 then
			local back = across
			if side == 2 then
				back = -across
			end
			local wedgeUp = up
			if difference * across:Dot(back) < 0 then
				wedgeUp = -up
			end
			local at = origin + across * ((bottom + top) / 2)
			wedge(parent, name, Vector3.new(depth, lift.Magnitude, math.abs(difference)),
				CFrame.fromMatrix(at, wedgeUp:Cross(back), wedgeUp, back), color, material, heat)
		end
	end
	return center
end

-- The tested terrain helper's longest-edge split closes the crown ends.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, inside: Vector3,
	depth: number, color: Color3, heat: number?)
	local normal = (b - a):Cross(c - a).Unit
	if normal:Dot((a + b + c) / 3 - inside) < 0 then
		normal = -normal
	end
	local inward = -normal * (depth / 2)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd >= acd and abd >= bcd then
		c, a = a, c
	elseif acd >= bcd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local back = bc.Unit
	local up = back:Cross(right)
	local height = math.abs(ab:Dot(up))
	wedge(parent, name, Vector3.new(depth, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2 + inward, right, up, back), color, METAL, heat)
	wedge(parent, name, Vector3.new(depth, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2 + inward, -right, up, -back), color, METAL, heat)
end

local function loft(parent: Instance, name: string, lower: { Vector3 }, upper: { Vector3 },
	depth: number, colors: { Color3 }, material: Enum.Material): { BasePart }
	local panels = {}
	for side = 1, 8 do
		local nextSide = side % 8 + 1
		panels[side] = panel(parent, name, lower[side], lower[nextSide], upper[nextSide], upper[side],
			depth, colors[side], material)
	end
	return panels
end

local function armorMark(parent: Instance, plate: BasePart, offsetX: number, lean: number)
	local thickness = 0.18
	local frame = plate.CFrame * CFrame.new(offsetX * plate.Size.X, -plate.Size.Y * 0.11, plate.Size.Z / 2 + 0.05)
		* CFrame.Angles(0, 0, math.rad(lean))
	box(parent, "ForgingMark", Vector3.new(plate.Size.X * 0.053, plate.Size.Y * 0.32, thickness),
		frame, BRONZE, METAL, false)
end

local function buildLower(parent: Instance, opts: Opts): BasePart
	local r = opts.hullRadius
	local y0, y1 = opts.baseY, opts.cabinFloorY
	local height = y1 - y0
	local sill = y1 - 9
	local miter = math.pi / 8
	local round = math.cos(miter)
	local clip = round - math.sin(miter)

	local lower = cylinder(parent, "LowerHull", 0.87 * r, 0, 0, y0, sill + 0.03, SHADE, METAL)
	local heel = octagon(y0, 0.91 * r, 0.88 * r, 0.48 * r)
	local chine = octagon(y0 + 0.19 * height, 1.177 * r, 1.096 * r, 0.543 * r)
	local belt = octagon(y0 + 0.50 * height, 1.183 * r, 1.074 * r, 0.551 * r)
	local waist = octagon(sill, round * r, round * r, clip * r)

	loft(parent, "ThermalHeel", heel, chine, 0.042 * r,
		{ THERMAL, THERMAL, SILT, THERMAL, THERMAL, THERMAL, SILT, THERMAL }, PLATE)
	loft(parent, "ThrustArmor", chine, belt, 0.044 * r,
		{ THERMAL, SHADE, THERMAL, THERMAL, THERMAL, SHADE, THERMAL, THERMAL }, METAL)
	local shoulders = loft(parent, "ShoulderArmor", belt, waist, 0.043 * r,
		{ SATIN, CHINE, SHADE, CHINE, SATIN, CHINE, SHADE, CHINE }, METAL)
	armorMark(parent, shoulders[1], 0.23, -13)
	armorMark(parent, shoulders[5], 0.23, -13)

	cylinder(parent, "CabinSill", r, 0, 0, sill, y1 - 2.4, SHADE, METAL)
	cylinder(parent, "SillEdge", r, 0, 0, y1 - 2.4, y1, BRONZE, METAL)
	return lower
end

local function buildUpper(parent: Instance, opts: Opts): { Vector3 }
	local r = opts.hullRadius
	local collarTop, sectionBase, roofSeat = opts.cabinCeilY + 5, opts.cabinCeilY + 22, opts.topY
	local x, z, bevel = 0.996 * r, 0.923 * r, 0.52 * r
	local round = math.cos(math.pi / 8)
	local clip = round - math.sin(math.pi / 8)
	local upperSeat = octagon(sectionBase, x, z, bevel)
	cylinder(parent, "CabinLintel", r, 0, 0, opts.cabinCeilY, collarTop, CHINE, METAL)
	loft(parent, "LintelArmor", octagon(collarTop, round * r, round * r, clip * r), upperSeat, 0.037 * r,
		{ CHINE, SATIN, SHADE, CHINE, CHINE, SATIN, SHADE, CHINE }, METAL)

	local midpoint, height = (sectionBase + roofSeat) / 2, roofSeat - sectionBase
	box(parent, "UpperHull", Vector3.new(2 * (x - bevel), height, 2 * z), CFrame.new(0, midpoint, 0),
		SATIN, METAL, true, 0.3)
	for _, sideX in ipairs({ -1, 1 }) do
		box(parent, "FlankArmor", Vector3.new(bevel, height, 2 * (z - bevel)),
			CFrame.new(sideX * (x - bevel / 2), midpoint, 0), SHADE, METAL, true)
		for _, sideZ in ipairs({ -1, 1 }) do
			local up = Vector3.zAxis * sideZ
			local back = Vector3.xAxis * -sideX
			local at = Vector3.new(sideX * (x - bevel / 2), midpoint, sideZ * (z - bevel / 2))
			local name, heat = "FlankChine", nil
			if sideZ > 0 then
				name, heat = "LeadingEdge", 0.5
			end
			wedge(parent, name, Vector3.new(height, bevel, bevel),
				CFrame.fromMatrix(at, up:Cross(back), up, back), CHINE, METAL, heat)
		end
	end
	return octagon(roofSeat, x, z, bevel)
end

local function buildCrown(parent: Instance, opts: Opts, seat: { Vector3 })
	local r, y = opts.hullRadius, opts.topY
	local depth = 0.047 * r
	local crestY, crestZ = y + 1.62 * r, -0.30 * r
	local left = Vector3.new(-0.65 * r, crestY, crestZ)
	local right = Vector3.new(0.65 * r, crestY, crestZ)
	local inside = Vector3.new(0, y + 0.2 * r, 0)

	panel(parent, "ForeCrown", seat[1], seat[2], right, left, depth, NOSE, METAL, 0.63)
	panel(parent, "AftCrown", seat[5], seat[6], left, right, depth, SATIN, METAL, 0.74)
	for side = 2, 4 do
		local heat = nil
		if side == 3 then
			heat = 0.87
		end
		triangle(parent, "CrownCheek", seat[side], seat[side + 1], right, inside, depth, CHINE, heat)
	end
	for side = 6, 8 do
		local heat = nil
		if side == 7 then
			heat = 0.87
		end
		triangle(parent, "CrownCheek", seat[side], seat[side % 8 + 1], left, inside, depth, CHINE, heat)
	end

	box(parent, "NoseTip", Vector3.new(1.27 * r, 0.084 * r, 0.108 * r),
		CFrame.new(0, crestY + 0.009 * r, crestZ), BRONZE, METAL, true, 1)
end

local function angularGap(a: number, b: number): number
	return math.abs((a - b + 180) % 360 - 180)
end

local function windowInlay(parent: Instance, opts: Opts, name: string, azimuth: number, halfWidth: number,
	y0: number, y1: number, color: Color3)
	local r, depth = opts.hullRadius, 0.21
	local outer = r + 0.285
	local theta = math.rad(halfWidth)
	local chord = outer * math.sin(theta)
	local apothem = outer * math.cos(theta)
	if y0 <= opts.windowTopY and y1 >= opts.windowBottomY then
		local edgeAngle = math.deg(math.atan2(chord, apothem - depth))
		for _, window in ipairs(opts.windows) do
			if angularGap(azimuth, window.centerDeg) <= window.halfDeg + edgeAngle + 0.35 then
				return
			end
		end
	end
	local aim = math.rad(azimuth)
	local radius = apothem - depth / 2
	local at = Vector3.new(math.sin(aim) * radius, (y0 + y1) / 2, math.cos(aim) * radius)
	box(parent, name, Vector3.new(2 * chord, y1 - y0, depth),
		CFrame.new(at) * CFrame.Angles(0, aim, 0), color, METAL, false)
end

local function buildWindowFrames(parent: Instance, opts: Opts)
	local above = opts.cabinCeilY - opts.windowTopY
	local below = opts.windowBottomY - opts.cabinFloorY
	for _, window in ipairs(opts.windows) do
		local center, half = window.centerDeg, window.halfDeg
		if above > 0 then
			for i = -2, 2 do
				windowInlay(parent, opts, "BrowInlay", center + i * half / 2.55, math.min(4.5, half / 10),
					opts.windowTopY + above * 0.22, opts.windowTopY + above * 0.85, SATIN)
			end
		end
		if below > 0 then
			for i = -1, 1 do
				windowInlay(parent, opts, "SillInlay", center + i * half * 0.65, math.min(4.4, half / 9),
					opts.cabinFloorY + below * 0.23, opts.cabinFloorY + below * 0.8, BRONZE)
			end
		end
		for _, sign in ipairs({ -1, 1 }) do
			windowInlay(parent, opts, "WindowJamb", center + sign * (half + 6.7), 4.4,
				opts.windowBottomY + 0.24, opts.windowTopY - 0.24, SHADE)
		end
	end
end

local function buildEngines(parent: Instance, opts: Opts)
	local limit = opts.hullRadius - 6
	local travel = opts.baseY - opts.mountY
	for _, row in ipairs({ -1, 1 }) do
		local z = limit * 0.28 * row
		local trough = math.max(1.4, 0.24 * travel)
		local top = opts.baseY + 0.16
		box(parent, "ThrustCassette", Vector3.new(1.52 * limit, trough, 0.45 * limit),
			CFrame.new(0, top - trough / 2, z), THERMAL, PLATE, true)
		for i = -1, 1 do
			local radius = limit * 0.215
			if i == 0 then
				radius = limit * 0.25
			end
			cylinder(parent, "EngineBell", radius, i * 0.515 * limit, z, opts.mountY, opts.baseY - 0.9,
				BRONZE, Enum.Material.CorrodedMetal)
		end
	end
end

function RocketShell.build(rocket: Model, opts: Opts): BasePart
	local lower = buildLower(rocket, opts)
	local roofSeat = buildUpper(rocket, opts)
	buildCrown(rocket, opts, roofSeat)
	buildWindowFrames(rocket, opts)
	buildEngines(rocket, opts)
	rocket.PrimaryPart = lower
	return lower
end

return RocketShell
