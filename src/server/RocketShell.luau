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
local STEEL = Color3.fromRGB(193, 204, 209)
local SATIN = Color3.fromRGB(177, 190, 198)
local CHINE = Color3.fromRGB(146, 162, 173)
local WELD = Color3.fromRGB(111, 130, 142)
local DARK = Color3.fromRGB(64, 76, 84)
local CASING = Color3.fromRGB(141, 133, 121)
local BELL_LIP = Color3.fromRGB(212, 184, 145)
local FACETS = 12
local SEAMS = { 3, 5, 9, 11 }
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function ringPoint(angle: number, radius: number, y: number): Vector3
	local theta = math.rad(angle)
	return Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius)
end

local function place(parent: Instance, part: BasePart, name: string, size: Vector3, frame: CFrame,
	color: Color3, material: Enum.Material, solid: boolean): BasePart
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
	part.Parent = parent
	return part
end

local function box(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, solid: boolean): BasePart
	return place(parent, Instance.new("Part"), name, size, frame, color, METAL, solid)
end

local function wedge(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3): BasePart
	return place(parent, Instance.new("WedgePart"), name, size, frame, color, METAL, true)
end

local function cylinder(parent: Instance, name: string, radius: number, x: number, z: number,
	y0: number, y1: number, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	return place(parent, part, name, Vector3.new(y1 - y0, 2 * radius, 2 * radius),
		CFrame.new(x, (y0 + y1) / 2, z) * UPRIGHT, color, material, true)
end

local function station(y: number, radius: number, offsetZ: number): { Vector3 }
	local vertices = {}
	for side = 1, FACETS do
		vertices[side] = ringPoint((side - 1.5) * 360 / FACETS, radius, y) + Vector3.new(0, 0, offsetZ)
	end
	return vertices
end

-- Parallel edges define the outer plane. The plate and its two wedge ends share that plane.
local function plate(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	depth: number, color: Color3, heat: number?): BasePart
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
		CFrame.fromMatrix(origin + across * ((left + right) / 2), across, up, outward), color, true)
	if heat then
		center:SetAttribute("Heat", heat)
	end
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
			local endPlate = wedge(parent, name, Vector3.new(depth, lift.Magnitude, math.abs(difference)),
				CFrame.fromMatrix(at, wedgeUp:Cross(back), wedgeUp, back), color)
			if heat then
				endPlate:SetAttribute("Heat", heat)
			end
		end
	end
	return center
end

-- The terrain helper's longest-edge split, centered through the thickness of the armor rib.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3,
	depth: number, color: Color3): (BasePart, BasePart)
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
	local first = wedge(parent, name, Vector3.new(depth, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2, right, up, back), color)
	local second = wedge(parent, name, Vector3.new(depth, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back), color)
	return first, second
end

local function shellCourse(parent: Instance, name: string, lower: { Vector3 }, upper: { Vector3 },
	depth: number): { BasePart }
	local parts = {}
	local tints = { STEEL, STEEL, SATIN, CHINE, SATIN, STEEL, STEEL, STEEL, SATIN, CHINE, SATIN, STEEL }
	for side = 1, FACETS do
		local nextSide = side % FACETS + 1
		parts[side] = plate(parent, name, lower[side], lower[nextSide], upper[nextSide], upper[side],
			depth, tints[side])
	end
	return parts
end

local function surfaceSeam(parent: Instance, panel: BasePart)
	local frame = panel.CFrame * CFrame.new(0, 0, panel.Size.Z / 2 + 0.043)
	box(parent, "LongitudinalWeld", Vector3.new(0.55, panel.Size.Y - 0.34, 0.16), frame, WELD, false)
end

local function buildColumn(parent: Instance, opts: Opts): BasePart
	local r = opts.hullRadius
	local sill = opts.cabinFloorY - 3.8
	local lintel = opts.cabinCeilY + 2
	local casingBottom = opts.baseY + 0.33 * r
	local outer = 1.012 * r
	local lower = cylinder(parent, "LowerHull", 0.895 * r, 0, 0,
		opts.baseY, sill + 0.03, CHINE, METAL)
	cylinder(parent, "CabinSill", r, 0, 0, sill, opts.cabinFloorY, SATIN, METAL)
	cylinder(parent, "CabinLintel", r, 0, 0, opts.cabinCeilY, lintel, SATIN, METAL)
	local upper = cylinder(parent, "UpperHull", 0.9745 * r, 0, 0, lintel - 0.03, opts.topY, CHINE, METAL)
	upper:SetAttribute("Heat", 0.3)

	shellCourse(parent, "ThrustBevel", station(opts.baseY, 0.931 * r, 0),
		station(casingBottom, outer, 0), 0.038 * r)
	local lowerPlates = shellCourse(parent, "LowerCasing", station(casingBottom, outer, 0),
		station(sill, outer, 0), 0.036 * r)
	local upperPlates = shellCourse(parent, "UpperCasing", station(lintel, outer, 0),
		station(opts.topY, outer, 0), 0.036 * r)
	for _, side in ipairs(SEAMS) do
		surfaceSeam(parent, lowerPlates[side])
		surfaceSeam(parent, upperPlates[side])
	end
	return lower
end

local function buildThrustRibs(parent: Instance, opts: Opts)
	local r, y = opts.hullRadius, opts.baseY
	local highest = math.min(68, y + 1.50 * r)
	for index, angle in ipairs({ 49, 131, 229, 311 }) do
		local root = ringPoint(angle, 0.85 * r, y + 0.095 * r)
		local heel = ringPoint(angle, 1.145 * r, y + 0.095 * r)
		local shoulder = ringPoint(angle, 1.31 * r, y + 0.43 * r)
		local crown = ringPoint(angle, 0.945 * r, highest)
		local width = 0.165 * r
		triangle(parent, "ThrustRib", root, heel, shoulder, width, CHINE)
		local first, second = triangle(parent, "ThrustRib", root, shoulder, crown, width, SATIN)
		if index == 1 or index == 3 then
			local edge = first
			if second.Size.Y * second.Size.Z > first.Size.Y * first.Size.Z then
				edge = second
			end
			edge.Name = "LeadingEdge"
			edge:SetAttribute("Heat", 0.5)
		end
	end
end

local function raisedEdge(part: BasePart): number
	local frame, size = part.CFrame, part.Size
	return frame.Position.Y + (
		math.abs(frame.RightVector.Y) * size.X
		+ math.abs(frame.UpVector.Y) * size.Y
		+ math.abs(frame.ZVector.Y) * size.Z
	) / 2
end

local function buildNose(parent: Instance, opts: Opts)
	local r, y = opts.hullRadius, opts.topY
	local rim = station(y, 1.012 * r, 0)
	local tip = Vector3.new(0.016 * r, y + 1.775 * r, -0.29 * r)
	local depth = 0.042 * r
	for side = 1, FACETS do
		local a, b = rim[side], rim[side % FACETS + 1]
		local point = tip
		local color = STEEL:Lerp(CHINE, 0.17 + ((side + 1) % 4) * 0.165)
		if side == 2 then
			-- The forward face reaches a fraction higher along the same rake.
			point += Vector3.new(0.001 * r, 0.014 * r, -0.002 * r)
		end
		local inward = -(b - a):Cross(point - a).Unit * (depth / 2)
		local first, second = triangle(parent, "RakedNose", a + inward, b + inward, point + inward, depth, color)
		local high, low = first, second
		if raisedEdge(second) > raisedEdge(first) then
			high, low = second, first
		end
		if side == 2 then
			high.Name = "NoseTip"
			high:SetAttribute("Heat", 1)
		elseif side % 2 == 1 then
			high:SetAttribute("Heat", 0.84)
			low:SetAttribute("Heat", 0.63)
		end
	end
end

local function windowInlay(parent: Instance, opts: Opts, name: string, angle: number, half: number,
	y0: number, y1: number, color: Color3)
	local depth = 0.20
	local outer = opts.hullRadius + 0.28
	local theta = math.rad(half)
	local halfChord = outer * math.sin(theta)
	local apothem = outer * math.cos(theta)
	if y0 <= opts.windowTopY and y1 >= opts.windowBottomY then
		local halfSpan = math.deg(math.atan2(halfChord, apothem - depth))
		for _, window in ipairs(opts.windows) do
			local gap = math.abs((angle - window.centerDeg + 180) % 360 - 180)
			if gap <= window.halfDeg + halfSpan + 0.4 then
				return
			end
		end
	end
	local center = ringPoint(angle, apothem - depth / 2, (y0 + y1) / 2)
	local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(angle), 0)
	box(parent, name, Vector3.new(2 * halfChord, y1 - y0, depth), frame, color, false)
end

local function buildCabinDetails(parent: Instance, opts: Opts)
	local above = opts.cabinCeilY - opts.windowTopY
	local below = opts.windowBottomY - opts.cabinFloorY
	for _, window in ipairs(opts.windows) do
		for i = -2, 2 do
			windowInlay(parent, opts, "BrowInlay", window.centerDeg + i * window.halfDeg / 2.65, 4.3,
				opts.windowTopY + above * 0.20, opts.windowTopY + above * 0.68, STEEL)
		end
		for i = -1, 1 do
			windowInlay(parent, opts, "SillInlay", window.centerDeg + i * window.halfDeg * 0.65, 4.1,
				opts.cabinFloorY + below * 0.20, opts.cabinFloorY + below * 0.72, CHINE)
		end
	end
	for _, side in ipairs(SEAMS) do
		windowInlay(parent, opts, "CabinWeld", (side - 1) * 360 / FACETS, 0.56,
			opts.cabinFloorY + 0.30, opts.cabinCeilY - 0.30, WELD)
	end
end

local function buildEngines(parent: Instance, opts: Opts)
	local limit = opts.hullRadius - 6
	local span = opts.baseY - opts.mountY
	local lipTop = opts.mountY + 0.235 * span
	local bellTop = opts.mountY + 0.71 * span
	local neckTop = opts.baseY + 0.22
	for _, row in ipairs({ -1, 1 }) do
		local z = limit * 0.306 * row
		for i = -1, 1 do
			local x = i * 0.517 * limit
			local radius = 0.224 * limit
			if i == 0 then
				radius = 0.264 * limit
			end
			cylinder(parent, "EngineBell", radius, x, z, opts.mountY, lipTop, BELL_LIP, METAL)
			cylinder(parent, "BellCasing", radius * 0.89, x, z, lipTop, bellTop, CASING, METAL)
			cylinder(parent, "EngineNeck", radius * 0.58, x, z, bellTop, neckTop, DARK, Enum.Material.CorrodedMetal)
		end
	end
end

function RocketShell.build(rocket: Model, opts: Opts): BasePart
	local lower = buildColumn(rocket, opts)
	buildThrustRibs(rocket, opts)
	buildNose(rocket, opts)
	buildCabinDetails(rocket, opts)
	buildEngines(rocket, opts)
	rocket.PrimaryPart = lower
	return lower
end

return RocketShell
