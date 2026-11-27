export type Builder = (parent: Instance, base: CFrame, s: number, colors: { Color3 }, rng: Random) -> number

local PlanetProps: { [string]: Builder } = {}

local ROCK = Enum.Material.Rock
local SLATE = Enum.Material.Slate
local BASALT = Enum.Material.Basalt
local WOOD = Enum.Material.Wood
local GRASS = Enum.Material.Grass
local SNOW = Enum.Material.Snow
local SANDSTONE = Enum.Material.Sandstone
local PAINT = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local TAU = 2 * math.pi

local function shade(color: Color3, gain: number): Color3
	return Color3.new(math.clamp(color.R * gain, 0, 1), math.clamp(color.G * gain, 0, 1), math.clamp(color.B * gain, 0, 1))
end

local function part(parent: Instance, className: string, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean, shape: Enum.PartType?): BasePart
	local item = Instance.new(className) :: BasePart
	if shape then
		(item :: Part).Shape = shape
	end
	item.Name = name
	item.Anchored = true
	item.CanCollide = solid
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Size = size
	item.CFrame = frame
	item.Color = color
	item.Material = material
	item.Parent = parent
	return item
end

local function box(parent: Instance, name: string, frame: CFrame, size: Vector3, color: Color3, material: Enum.Material, solid: boolean): BasePart
	return part(parent, "Part", name, size, frame, color, material, solid)
end

local function wedge(parent: Instance, name: string, frame: CFrame, size: Vector3, color: Color3, material: Enum.Material, solid: boolean): BasePart
	return part(parent, "WedgePart", name, size, frame, color, material, solid)
end

local function ball(parent: Instance, name: string, base: CFrame, offset: Vector3, radius: number, color: Color3, material: Enum.Material)
	part(parent, "Part", name, Vector3.one * (2 * radius), base * CFrame.new(offset),
		color, material, false, Enum.PartType.Ball)
end

-- The local cylinder X axis follows the slope of the branch or the surface normal.
local function column(parent: Instance, name: string, base: CFrame, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material, solid: boolean): BasePart
	return part(parent, "Part", name, Vector3.new(y1 - y0, radius * 2, radius * 2),
		base * CFrame.new(0, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color, material, solid, Enum.PartType.Cylinder)
end

local function branch(parent: Instance, name: string, base: CFrame, a: Vector3, b: Vector3, r: number, color: Color3, solid: boolean)
	local along = (b - a).Unit
	local reference = Vector3.xAxis
	if math.abs(along.X) > 0.94 then
		reference = Vector3.zAxis
	end
	local back = along:Cross(reference).Unit
	local up = back:Cross(along)
	part(parent, "Part", name, Vector3.new((b - a).Magnitude, 2 * r, 2 * r),
		base * CFrame.fromMatrix((a + b) / 2, along, up, back),
		color, WOOD, solid, Enum.PartType.Cylinder)
end

-- Reuse Planet.triangle's longest-edge split and inward thickness offset.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, thickness: number, color: Color3, material: Enum.Material, solid: boolean)
	local normal = (b - a):Cross(c - a).Unit
	if normal:Dot((a + b + c) / 3 - inside) < 0 then
		normal = -normal
	end
	local shift = -normal * (thickness / 2)
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
	wedge(parent, name, CFrame.fromMatrix((a + b) / 2 + shift, right, up, back),
		Vector3.new(thickness, height, math.abs(ab:Dot(back))), color, material, solid)
	wedge(parent, name, CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back),
		Vector3.new(thickness, height, math.abs(ac:Dot(back))), color, material, solid)
end

local function radial(angle: number, r: number, y: number): Vector3
	return Vector3.new(math.sin(angle) * r, y, math.cos(angle) * r)
end

-- A slab and two triangular prisms fill the exact planar trapezoid.
-- a→b and d→c must be parallel, with the top lying over the bottom span.
local function cliffFace(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	thickness: number, color: Color3, material: Enum.Material)
	local lowerWidth = (b - a).Magnitude
	local upperWidth = (c - d).Magnitude
	local lowerMid = (a + b) / 2
	local rise = (c + d) / 2 - lowerMid
	local right = (b - a).Unit
	local slide = rise:Dot(right)
	local heightVector = rise - right * slide
	local up = heightVector.Unit
	local outward = right:Cross(up)
	local center = lowerMid + heightVector / 2 - outward * (thickness / 2)
	local frame = CFrame.fromMatrix(center, right, up, outward)
	box(parent, name, frame * CFrame.new(slide, 0, 0),
		Vector3.new(upperWidth, heightVector.Magnitude, thickness), color, material, true)
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = (lowerWidth - upperWidth) / 2 - side * slide
		local at = frame:PointToWorldSpace(Vector3.new(slide + side * (upperWidth + shoulder) / 2, 0, 0))
		local wedgeUp = side * right
		local wedgeBack = -up
		wedge(parent, name, CFrame.fromMatrix(at, wedgeUp:Cross(wedgeBack), wedgeUp, wedgeBack),
			Vector3.new(thickness, shoulder, heightVector.Magnitude), color, material, true)
	end
end

local function squareCliff(parent: Instance, name: string, base: CFrame, bottom: Vector3, top: Vector3,
	lowRadius: number, highRadius: number, thickness: number, color: Color3, material: Enum.Material)
	for face = 0, 3 do
		local first, last = (face - 0.5) * math.pi / 2, (face + 0.5) * math.pi / 2
		local a = base:PointToWorldSpace(bottom + radial(first, lowRadius, 0))
		local b = base:PointToWorldSpace(bottom + radial(last, lowRadius, 0))
		local c = base:PointToWorldSpace(top + radial(last, highRadius, 0))
		local d = base:PointToWorldSpace(top + radial(first, highRadius, 0))
		cliffFace(parent, name, a, b, c, d, thickness, shade(color, 0.88 + face * 0.07), material)
	end
end

local function chisel(parent: Instance, name: string, frame: CFrame, width: number, depth: number, height: number,
	color: Color3, material: Enum.Material)
	for _, side in ipairs({ -1, 1 }) do
		local yaw = (side + 1) * math.pi / 2
		wedge(parent, name, frame * CFrame.new(0, height / 2, side * depth / 4) * CFrame.Angles(0, yaw, 0),
			Vector3.new(width, height, depth / 2), shade(color, 0.98 + side * 0.045), material, false)
	end
end

PlanetProps.rock = function(parent, base, s, colors, rng)
	local width = rng:NextNumber(11, 16) * s
	local height = rng:NextNumber(5.5, 8.5) * s
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TAU), rng:NextNumber(-0.19, 0.19))
	box(parent, "Boulder", frame * CFrame.new(0, height * 0.17, 0),
		Vector3.new(width, height, width * 0.82), colors[1], SLATE, true)
	wedge(parent, "BoulderCrown", frame * CFrame.new(0, height * 0.97, 0),
		Vector3.new(width * 0.985, height * 0.62, width * 0.807), colors[2], ROCK, true)
	return 16 * s
end

PlanetProps.spike = function(parent, base, s, colors, rng)
	local material = BASALT
	if colors[1].B > 0.55 then
		material = Enum.Material.Ice
	end
	local h = rng:NextNumber(24, 29) * s
	local yaw = rng:NextNumber(0, TAU)
	local frame = base * CFrame.new(0, -2.8 * s, 0) * CFrame.Angles(0, yaw, 0)
	chisel(parent, "SpikePoint", frame * CFrame.Angles(0.16, 0, 0), h * 0.28, h * 0.42, h, colors[1], material)
	wedge(parent, "SpikePoint",
		frame * CFrame.new(3.8 * s, h * 0.29, 5.4 * s) * CFrame.Angles(-0.25, 0.75, 0),
		Vector3.new(h * 0.18, h * 0.65, h * 0.22), shade(colors[1], 0.84), material, false)
	return 15 * s
end

PlanetProps.pool = function(parent, base, s, colors, rng)
	local radius = rng:NextNumber(14, 24) * s
	local stone = Color3.fromRGB(53, 42, 43)
	column(parent, "PoolRim", base, radius + 2.5 * s, -2.2 * s, 0.35 * s, stone, BASALT, true)
	column(parent, "Pool", base, radius, 0.3 * s, 0.78 * s, colors[1], NEON, false)
	return radius + 2.5 * s
end

PlanetProps.pine = function(parent, base, s, colors, rng)
	column(parent, "PineTrunk", base, 1.5 * s, -2 * s, 20 * s, Color3.fromRGB(104, 79, 67), WOOD, true)
	local turn = rng:NextNumber(0, TAU)
	local tiers = { { 6, 10, 13 }, { 12.5, 8, 9.5 }, { 18, 5.8, 7.5 } }
	for i, tier in ipairs(tiers) do
		local color, material = shade(colors[1], 0.90 + 0.11 * i), GRASS
		if i == 3 then
			color, material = colors[2], SNOW
		end
		local leg = tier[3] * s
		-- Rotating about local X places the wedge's right angle at the middle of the peak.
		local frame = base * CFrame.new(0, tier[1] * s, 0) * CFrame.Angles(0, turn + (i - 1) * math.pi / 2, 0)
			* CFrame.Angles(-3 * math.pi / 4, 0, 0)
		wedge(parent, "PineCrownPoint", frame, Vector3.new(tier[2] * s, leg, leg), color, material, false)
	end
	return 12 * s
end

PlanetProps.tree = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(15, 21) * s
	local yaw = rng:NextNumber(0, TAU)
	local frame = base * CFrame.Angles(0, yaw, 0)
	branch(parent, "TreeTrunk", frame, Vector3.new(0, -2.1 * s, 0), Vector3.new(2.9 * s, h, 0), 2.2 * s, colors[1], true)
	ball(parent, "BroadleafCrown", frame, Vector3.new(0, h + 2 * s, -2.8 * s), 8.7 * s, colors[2], GRASS)
	ball(parent, "BroadleafCrown", frame, Vector3.new(5.2 * s, h + 4.5 * s, 3.8 * s), 7.5 * s, colors[3], GRASS)
	return 16 * s
end

PlanetProps.mushroom = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(10, 16) * s
	local r = rng:NextNumber(7.8, 10) * s
	column(parent, "MushroomStipe", base, 1.9 * s, -1.4 * s, h + 0.2 * s, colors[1], PAINT, false)
	column(parent, "Cap", base, r, h - 0.2 * s, h + 1.95 * s, colors[2], NEON, false)
	local spot = base * CFrame.new(r * 0.23, 0, -r * 0.15)
	column(parent, "LuminousSpot", spot, r * 0.29, h + 1.9 * s, h + 2.45 * s, colors[3], NEON, false)
	return r
end

PlanetProps.bush = function(parent, base, s, colors, rng)
	local turn = rng:NextNumber(0, TAU)
	local primary = rng:NextNumber(5.4, 6.2) * s
	ball(parent, "BushCore", base, radial(turn, 2.4 * s, primary * 0.64), primary, colors[1], GRASS)
	ball(parent, "BushGrowth", base, radial(turn + math.pi, 3.9 * s, 3.05 * s), 4.65 * s, colors[2], GRASS)
	return 10 * s
end

PlanetProps.cactus = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(15, 23) * s
	local r = 2.4 * s
	local color = colors[1]
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	column(parent, "CactusStem", frame, r, -2.1 * s, h, color, PAINT, false)
	local left = Vector3.new(-5.6 * s, h * 0.38, 0)
	local right = Vector3.new(5.1 * s, h * 0.52, 0)
	local axis = (right - left).Unit
	local back = Vector3.zAxis
	local tube = frame * CFrame.fromMatrix((left + right) / 2, axis, back:Cross(axis), back)
	local armR = r * 0.68
	part(parent, "Part", "CactusElbow", Vector3.new((right - left).Magnitude + armR, 2 * armR, 2 * armR),
		tube, color, PAINT, false, Enum.PartType.Cylinder)
	for _, elbow in ipairs({ left, right }) do
		column(parent, "CactusArm", frame * CFrame.new(elbow), armR, -armR * 0.8,
			rng:NextNumber(4.3, 7.4) * s, color, PAINT, false)
	end
	return 8 * s
end

PlanetProps.deadTree = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(16, 22) * s
	local yaw = rng:NextNumber(0, TAU)
	local top = radial(yaw, 2.2 * s, h)
	branch(parent, "DeadTrunk", base, Vector3.new(0, -2.7 * s, 0), top, 1.65 * s, colors[1], true)
	for i = 1, 2 do
		local root = top * (0.46 + i * 0.14)
		local endpoint = root + radial(yaw + i * math.pi, rng:NextNumber(5.7, 8.3) * s, (3.8 + i * 0.9) * s)
		branch(parent, "DryBranch", base, root, endpoint, 0.82 * s, shade(colors[1], 0.93 + i * 0.09), false)
	end
	return 12 * s
end

PlanetProps.crystal = function(parent, base, s, colors, rng)
	local yaw = rng:NextNumber(0, TAU)
	local h = rng:NextNumber(24, 29) * s
	local foot = base * CFrame.new(0, -2.65 * s, 0)
	local frame = foot * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0.12, 0, 0)
	chisel(parent, "Crystal", frame, h * 0.24, h * 0.41, h, colors[1], NEON)
	for i = 2, 3 do
		local azimuth = yaw + (i - 1) * TAU / 3
		local height = rng:NextNumber(9, 15) * s
		local side = foot * CFrame.Angles(0, azimuth, 0) * CFrame.new(0, height * 0.43, 4.2 * s)
			* CFrame.Angles(-0.25, 0, 0)
		wedge(parent, "Crystal", side, Vector3.new(height * 0.32, height, height * 0.50), colors[i], NEON, false)
	end
	return 13 * s
end

PlanetProps.palm = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(19, 24) * s
	local turn = rng:NextNumber(0, TAU)
	local top = radial(turn, 4.3 * s, h)
	branch(parent, "PalmTrunk", base, Vector3.new(0, -2.4 * s, 0), top, 1.6 * s, colors[1], true)
	for i = 0, 2 do
		local azimuth = turn + i * TAU / 3 + rng:NextNumber(-0.11, 0.11)
		local spoke = base * CFrame.new(top) * CFrame.Angles(0, azimuth, 0) * CFrame.Angles(0.16 + i * 0.16, 0, 0)
		local length = rng:NextNumber(12.5, 15) * s
		local at = spoke:PointToWorldSpace(Vector3.new(0, 0, length / 2 - 1.3 * s))
		local width = spoke.RightVector * ((-1) ^ i)
		local back = -spoke.ZVector
		wedge(parent, "PalmFrond", CFrame.fromMatrix(at, width:Cross(back), width, back),
			Vector3.new(0.72 * s, 8.0 * s, length), shade(colors[2], 0.86 + 0.11 * i), GRASS, false)
	end
	return 20 * s
end

PlanetProps.volcano = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(174, 222) * s
	local h = rng:NextNumber(214, 274) * s
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local sink = -27
	local mouth = r * 0.29
	squareCliff(parent, "VolcanoSlope", frame, Vector3.new(0, sink, 0), Vector3.new(0, h, 0), r, mouth, 7 * s, colors[1], BASALT)
	local floorY = h - 8 * s
	local width = math.sqrt(2) * (mouth + (r - mouth) * (h - floorY) / (h - sink)) - 1.8 * s
	box(parent, "Caldera", frame * CFrame.new(0, floorY - 2 * s, 0),
		Vector3.new(width, 4 * s, width), shade(colors[1], 0.61), BASALT, true)
	box(parent, "CalderaLava", frame * CFrame.new(0, floorY + 0.7 * s, 0),
		Vector3.new(width * 0.89, 1.65 * s, width * 0.89), colors[2], NEON, false)

	local first = rng:NextInteger(0, 3)
	for i = 0, 1 do
		local direction = (first + i * 3) * math.pi / 2
		local face = frame * CFrame.Angles(0, direction, 0)
		local a = Vector3.new(rng:NextNumber(-6, 6) * s, h, mouth / math.sqrt(2))
		local b = Vector3.new(rng:NextNumber(-24, 24) * s, sink, r / math.sqrt(2))
		local to = a:Lerp(b, rng:NextNumber(0.76, 0.93))
		local normal = Vector3.xAxis:Cross(a - b).Unit
		local offset = normal * 0.48 * s
		local start, finish = face:PointToWorldSpace(a + offset), face:PointToWorldSpace(to + offset)
		box(parent, "LavaFlow", CFrame.lookAt((start + finish) / 2, finish, face:VectorToWorldSpace(normal)),
			Vector3.new(rng:NextNumber(8, 13) * s, 1.25 * s, (start - finish).Magnitude),
			shade(colors[2], 1 - 0.12 * i), NEON, false)
	end
	return r
end

PlanetProps.mountain = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(175, 240) * s
	local h = rng:NextNumber(218, 296) * s
	local top = base:PointToWorldSpace(Vector3.new(rng:NextNumber(-0.17, 0.17) * r, h, rng:NextNumber(-0.17, 0.17) * r))
	local inside = base:PointToWorldSpace(Vector3.new(0, h * 0.18, 0))
	local turns = rng:NextNumber(0, TAU)
	local corners, snowline = {}, {}
	local capMaterial = SNOW
	if colors[2].G - colors[2].R > 0.04 then
		capMaterial = GRASS
	end
	local capOffset = base.UpVector * (1.15 * s)
	for i = 1, 4 do
		corners[i] = base:PointToWorldSpace(radial(turns + i * math.pi / 2, r * rng:NextNumber(0.9, 1.05), -28))
		snowline[i] = corners[i]:Lerp(top, rng:NextNumber(0.61, 0.75)) + capOffset
	end
	for i = 1, 4 do
		local j = i % 4 + 1
		triangle(parent, "MountainFlank", corners[i], corners[j], top, inside, 7 * s, shade(colors[1], 0.87 + 0.075 * i), ROCK, true)
		triangle(parent, "MountainCrown", snowline[i], snowline[j], top + capOffset, inside,
			8 * s, shade(colors[2], 0.95 + i * 0.016), capMaterial, true)
	end
	return r * 1.05
end

PlanetProps.giantTree = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(145, 191) * s
	local bark = colors[1]
	local turn = rng:NextNumber(0, TAU)
	local rise = radial(turn, 9 * s, h)
	branch(parent, "GiantTrunk", base, Vector3.new(0, -28, 0), rise, 16 * s, bark, true)
	for i = 0, 2 do
		local azimuth = turn + (i + 0.2) * TAU / 3
		local root = radial(azimuth, rng:NextNumber(37, 51) * s, -24)
		branch(parent, "ButtressRoot", base, root, rise * 0.29, 8 * s, shade(bark, 0.89 + 0.09 * i), true)
		local endPoint = radial(azimuth, rng:NextNumber(43, 62) * s, h * rng:NextNumber(0.74, 0.96))
		branch(parent, "GiantBranch", base, rise * 0.61, endPoint, 6.9 * s, bark, false)
		ball(parent, "OuterCanopy", base, endPoint + Vector3.new(0, 10 * s, 0), rng:NextNumber(34, 46) * s, colors[2], GRASS)
		ball(parent, "CanopyBuds", base, endPoint * 0.75 + Vector3.new(0, 55 * s, 0), 29 * s, colors[3], GRASS)
	end
	ball(parent, "GiantCanopy", base, rise + Vector3.new(0, 22 * s, 0), 49 * s, colors[3], GRASS)
	return 110 * s
end

PlanetProps.mesa = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(116, 166) * s
	local h = rng:NextNumber(125, 174) * s
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local shoulderY = h * 0.73
	local shoulder = r * 0.81
	squareCliff(parent, "MesaStratum", frame, Vector3.new(0, -25, 0), Vector3.new(0, shoulderY, 0), r, shoulder,
		8 * s, colors[1], SANDSTONE)
	local rim = shoulder * math.sqrt(2)
	local bandH = h * 0.15
	box(parent, "MesaRim", frame * CFrame.new(0, shoulderY + bandH / 2 - 0.2 * s, 0),
		Vector3.new(rim * 0.997, bandH + 0.4 * s, rim * 0.997), colors[2], SANDSTONE, true)
	box(parent, "MesaPlateau", frame * CFrame.new(2 * s, (h + shoulderY + bandH) / 2 - 0.2 * s, -1.1 * s),
		Vector3.new(rim * 0.94, h - shoulderY - bandH + 0.4 * s, rim * 0.92), colors[3], SANDSTONE, true)
	return r
end

PlanetProps.arch = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(62, 81) * s
	local rise = rng:NextNumber(52, 69) * s
	local spring = rng:NextNumber(54, 77) * s
	local thickness, depth = 27 * s, 37 * s
	local color = colors[1]
	for _, side in ipairs({ -1, 1 }) do
		local x = side * r
		box(parent, "ArchPier", base * CFrame.new(x, (spring - 22) / 2, 0),
			Vector3.new(thickness + 0.8 * s, spring + 30, depth), shade(color, 0.94 + 0.05 * side), SANDSTONE, true)
		wedge(parent, "ArchButtress", base * CFrame.new(x + side * 8 * s, 15 * s - 9, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Vector3.new(depth * 0.82, 49 * s, 25 * s), shade(color, 0.84), SANDSTONE, true)
	end
	local a = Vector3.new(r, spring, 0)
	for i = 1, 8 do
		local t = i * math.pi / 8
		local b = Vector3.new(r * math.cos(t), spring + rise * math.sin(t), 0)
		local chord = b - a
		local axis = chord.Unit
		local frame = base * CFrame.fromMatrix((a + b) / 2, axis, Vector3.zAxis:Cross(axis), Vector3.zAxis)
		-- The overlap covers the bevel between chords and leaves a real through-opening.
		box(parent, "ArchStone", frame, Vector3.new(chord.Magnitude + thickness * 0.42, thickness, depth * rng:NextNumber(0.91, 1.05)),
			shade(color, rng:NextNumber(0.91, 1.11)), SANDSTONE, true)
		a = b
	end
	return r + 29 * s
end

PlanetProps.spire = function(parent, base, s, colors, rng)
	column(parent, "SpireBedrock", base, 49 * s, -26, 7 * s, shade(colors[3], 0.28), SLATE, true)
	local turn = rng:NextNumber(0, TAU)
	local h = rng:NextNumber(234, 299) * s
	local main = base * CFrame.Angles(0, turn, 0) * CFrame.new(0, -26, 0) * CFrame.Angles(-0.16, 0, 0)
	local shaftH = h * 0.67 + 26
	local width, depth = h * 0.20, h * 0.255
	box(parent, "GiantCrystalShaft", main * CFrame.new(0, shaftH / 2, 0),
		Vector3.new(width, shaftH, depth), shade(colors[1], 0.83), Enum.Material.Ice, false)
	chisel(parent, "GiantCrystalPoint", main * CFrame.new(0, shaftH, 0), width, depth, h * 0.33, colors[1], NEON)
	for i = 2, 3 do
		local angle = turn + (i - 1) * TAU / 3
		local height = rng:NextNumber(106, 164) * s
		local child = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, -23, 33 * s) * CFrame.Angles(-0.21, 0, 0)
		chisel(parent, "GiantCrystalPoint", child, height * 0.22, height * 0.43, height + 23, colors[i], NEON)
	end
	return 105 * s
end

PlanetProps.seaStack = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(32, 49) * s
	local h = rng:NextNumber(98, 151) * s
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local top = Vector3.new(r * 0.14, h, -r * 0.10)
	local crest = r * 0.65
	squareCliff(parent, "SeaStackCliff", frame, Vector3.new(0, -27, 0), top, r, crest, 6 * s, colors[1], ROCK)
	local width = crest * math.sqrt(2) + 0.3 * s
	box(parent, "SeaStackTurf", frame * CFrame.new(top + Vector3.new(0, 1.45 * s, 0)),
		Vector3.new(width, 3.45 * s, width), colors[2], GRASS, true)
	return r + 4 * s
end

PlanetProps.lighthouse = function(parent, base, s, colors, _rng)
	local white, red, amber = colors[1], colors[2], colors[3]
	local dark = Color3.fromRGB(61, 58, 59)
	column(parent, "LighthouseBedrock", base, 23 * s, -27, 7.6 * s, dark, ROCK, true)
	local y = 7.5 * s
	for i = 1, 5 do
		local r = (14.3 - (i - 1) * 0.77) * s
		local color = white
		if i % 2 == 0 then
			color = red
		end
		column(parent, "LighthouseStripe", base, r, y, y + 19.6 * s, color, PAINT, true)
		y += 19.5 * s
	end
	column(parent, "LanternGallery", base, 15.3 * s, y, y + 2.55 * s, dark, Enum.Material.Metal, false)
	local lens = column(parent, "LanternLens", base, 8.25 * s, y + 2.4 * s, y + 13.3 * s, amber, NEON, false)
	local light = Instance.new("PointLight")
	light.Color = amber
	light.Range = 34
	light.Brightness = 1.7
	light.Shadows = false
	light.Parent = lens
	column(parent, "LanternRoof", base, 11.25 * s, y + 13.28 * s, y + 19 * s, red, Enum.Material.Metal, false)
	ball(parent, "LanternCrown", base, Vector3.new(0, y + 19 * s, 0), 5.7 * s, red, Enum.Material.Metal)
	return 26 * s
end

return PlanetProps
