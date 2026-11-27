export type Builder = (parent: Instance, base: CFrame, s: number, colors: { Color3 }, rng: Random) -> number

local PlanetProps: { [string]: Builder } = {}

local ROCK = Enum.Material.Rock
local SLATE = Enum.Material.Slate
local BASALT = Enum.Material.Basalt
local WOOD = Enum.Material.Wood
local GRASS = Enum.Material.Grass
local ICE = Enum.Material.Ice
local SNOW = Enum.Material.Snow
local SANDSTONE = Enum.Material.Sandstone
local PAINT = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local TURN = 2 * math.pi

local function shade(color: Color3, gain: number): Color3
	return Color3.new(math.clamp(color.R * gain, 0, 1), math.clamp(color.G * gain, 0, 1), math.clamp(color.B * gain, 0, 1))
end

local function part(parent: Instance, className: string, name: string, size: Vector3, frame: CFrame,
	color: Color3, material: Enum.Material, solid: boolean, shape: Enum.PartType?): BasePart
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
	item.Color = color
	item.Material = material
	item.Size = size
	item.CFrame = frame
	item.Parent = parent
	return item
end

local function box(parent: Instance, name: string, frame: CFrame, size: Vector3,
	color: Color3, material: Enum.Material, solid: boolean): BasePart
	return part(parent, "Part", name, size, frame, color, material, solid)
end

local function wedge(parent: Instance, name: string, frame: CFrame, size: Vector3,
	color: Color3, material: Enum.Material, solid: boolean)
	part(parent, "WedgePart", name, size, frame, color, material, solid)
end

local function at(base: CFrame, s: number, x: number, y: number, z: number): CFrame
	return base * CFrame.new(Vector3.new(x, y, z) * s)
end

local function pad(parent: Instance, name: string, frame: CFrame, radius: number, thickness: number, color: Color3)
	-- Turn the cylinder's X axis perpendicular to the face of the paddle.
	part(parent, "Part", name, Vector3.new(thickness, 2 * radius, 2 * radius),
		frame * CFrame.Angles(0, -math.pi / 2, 0), color, PAINT, false, Enum.PartType.Cylinder)
end

local function segment(parent: Instance, name: string, base: CFrame, a: Vector3, b: Vector3,
	width: number, depth: number, color: Color3, material: Enum.Material, solid: boolean)
	local axis = (b - a).Unit
	local reference = Vector3.zAxis
	if math.abs(axis.Z) > 0.93 then
		reference = Vector3.xAxis
	end
	local up = reference:Cross(axis).Unit
	local back = axis:Cross(up)
	box(parent, name, base * CFrame.fromMatrix((a + b) / 2, axis, up, back),
		Vector3.new((b - a).Magnitude + math.min(width, depth) * 0.25, width, depth), color, material, solid)
end

-- Planet's longest-edge split makes two wedge prisms with a shared diagonal.
-- These vertices describe the middle of the thickness, so both cliff faces stay solid.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, depth: number,
	color: Color3, material: Enum.Material)
	local ab, ac, bc = b - a, c - a, c - b
	local ab2, ac2, bc2 = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if ab2 >= ac2 and ab2 >= bc2 then
		c, a = a, c
	elseif ac2 >= bc2 then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local back = bc.Unit
	local up = back:Cross(right)
	local height = math.abs(ab:Dot(up))
	wedge(parent, name, CFrame.fromMatrix((a + b) / 2, right, up, back),
		Vector3.new(depth, height, math.abs(ab:Dot(back))), color, material, true)
	wedge(parent, name, CFrame.fromMatrix((a + c) / 2, -right, up, -back),
		Vector3.new(depth, height, math.abs(ac:Dot(back))), color, material, true)
end

local function cliff(parent: Instance, name: string, base: CFrame, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	depth: number, color: Color3, material: Enum.Material)
	local aw = base:PointToWorldSpace(a)
	local bw = base:PointToWorldSpace(b)
	local cw = base:PointToWorldSpace(c)
	local dw = base:PointToWorldSpace(d)
	triangle(parent, name, aw, bw, cw, depth, color, material)
	triangle(parent, name, aw, cw, dw, depth, color, material)
end

local function branch(parent: Instance, name: string, base: CFrame, a: Vector3, b: Vector3,
	width: number, color: Color3, solid: boolean)
	segment(parent, name, base, a, b, width, width * 0.82, color, WOOD, solid)
end

local function frond(parent: Instance, name: string, base: CFrame, root: Vector3, tip: Vector3, width: number,
	thickness: number, color: Color3)
	-- A frond's thick +Z end grows from the trunk, tapering toward the tip.
	local back = (root - tip).Unit
	local right = Vector3.yAxis:Cross(back).Unit
	local up = back:Cross(right)
	local frame = base * CFrame.fromMatrix((root + tip) / 2, right, up, back)
	wedge(parent, name, frame, Vector3.new(width, thickness, (tip - root).Magnitude), color, GRASS, false)
end

PlanetProps.rock = function(parent, base, s, colors, rng)
	local dark, bright = colors[1], colors[2]
	local mineral = ROCK
	local cut = SLATE
	if bright.B > 0.8 then
		mineral, cut = SLATE, ICE
	elseif dark.R > 0.65 then
		mineral, cut = SANDSTONE, SANDSTONE
	elseif dark.R > dark.B * 1.3 and dark.R < 0.34 then
		mineral, cut = BASALT, BASALT
	elseif dark.B > dark.R * 1.25 then
		mineral = SLATE
	end

	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local span = rng:NextNumber(10.5, 14)
	box(parent, "FaultedSlab", at(frame, s, -3.8, 0.3, -1.2) * CFrame.Angles(-0.15, 0, -0.19),
		Vector3.new(span, 4.5, 9.1) * s, dark, mineral, true)
	wedge(parent, "ShearedCut", at(frame, s, 4.5, 1.5, 0.6) * CFrame.Angles(0.14, 0.66, 0.04),
		Vector3.new(span * 0.74, 6.8, 8.4) * s, bright, cut, true)
	return 16 * s
end

PlanetProps.spike = function(parent, base, s, colors, rng)
	local color = colors[1]
	local h = rng:NextNumber(19, 25)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	if color.B > 0.55 then
		wedge(parent, "FoldedIceFace", at(frame, s, -2.5, h * 0.34, 0) * CFrame.Angles(-0.28, -0.32, 0.19),
			Vector3.new(10.25, h, 11.3) * s, color, ICE, false)
		wedge(parent, "FoldedIceFace", at(frame, s, 4.85, h * 0.16, -1.6) * CFrame.Angles(0.12, 0.96, -0.22),
			Vector3.new(8.8, h * 0.66, 12.75) * s, shade(color, 0.78), ICE, false)
		box(parent, "IceSeam", at(frame, s, -2.0, h * 0.26, 4.1) * CFrame.Angles(-0.4, -0.22, 0.26),
			Vector3.new(2.2, h * 0.76, 3.1) * s, shade(color, 1.2), ICE, false)
	else
		for i = 0, 2 do
			local height = h * (0.93 - i * 0.23)
			wedge(parent, "ObsidianTooth", at(frame, s, (i - 1) * 5.25, height / 2 - 2.3, i * 0.92)
				* CFrame.Angles(0.15 + i * 0.09, 0.49 + i * 0.15, 0.18 + i * 0.07),
				Vector3.new(5.25 - i * 0.52, height, 8.4 - i) * s, shade(color, 0.84 + i * 0.13), BASALT, false)
		end
	end
	return 15 * s
end

PlanetProps.pool = function(parent, base, s, colors, rng)
	local span = rng:NextNumber(17, 24)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local color = Color3.fromRGB(49, 37, 35)
	box(parent, "Pool", at(frame, s, 0, 0.44, 0),
		Vector3.new(7.5, 1.12, span * 2) * s, colors[1], NEON, false)
	wedge(parent, "FissureLip", at(frame, s, -5.2, 0.32, -2.2) * CFrame.Angles(0, -0.087, 0),
		Vector3.new(5.9, 3.4, span * 1.84) * s, shade(color, 0.9), BASALT, true)
	wedge(parent, "FissureLip", at(frame, s, 5.9, 0.55, 1.45) * CFrame.Angles(0, math.pi + 0.095, 0.09),
		Vector3.new(5.6, 3.9, span * 1.72) * s, shade(color, 1.17), BASALT, true)
	return (span + 2.5) * s
end

PlanetProps.pine = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(18, 22)
	branch(parent, "WindBentTrunk", frame, Vector3.new(-3.7, -2.4, 0) * s, Vector3.new(3.3, h, 0.6) * s,
		2.5 * s, Color3.fromRGB(94, 76, 65), true)
	wedge(parent, "ShelteredNeedles", at(frame, s, 4.7, h * 0.64, 0) * CFrame.Angles(0.09, -1.52, -0.13),
		Vector3.new(9.4, 7.7, 15) * s, shade(colors[1], 0.87), GRASS, false)
	wedge(parent, "SweptCrown", at(frame, s, 3.45, h * 0.80, -0.6) * CFrame.Angles(0.39, -1.77, 0.03),
		Vector3.new(7.4, 9.2, 11.3) * s, colors[1], GRASS, false)
	wedge(parent, "DriftedSnow", at(frame, s, 1.9, h * 0.92, -0.5) * CFrame.Angles(0.38, -1.77, 0.03),
		Vector3.new(7.6, 4.5, 9.4) * s, colors[2], SNOW, false)
	return 13.5 * s
end

PlanetProps.tree = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(13, 17)
	local crown = Vector3.new(3.9, h, 0) * s
	branch(parent, "LeafBridgeTrunk", frame, Vector3.new(-2, -2.6, 0) * s, crown,
		2.9 * s, colors[1], true)
	frond(parent, "BroadleafWing", frame, crown + Vector3.new(1.7, 1.45, 0) * s,
		Vector3.new(-9.8, h - 0.25, -1.45) * s, 13.6 * s, 6.8 * s, colors[2])
	frond(parent, "RaisedLeafWing", frame, crown + Vector3.new(-2.15, 3.15, -0.7) * s,
		Vector3.new(14, h + 4.2, 4.3) * s, 9.8 * s, 5.2 * s, colors[3])
	return 16.2 * s
end

PlanetProps.mushroom = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(7.8, 11.1)
	local tip = Vector3.new(-2.65, h, 0) * s
	segment(parent, "ShelfStalk", frame, Vector3.new(-4, -1.8, -1) * s, tip, 2.7 * s, 2.2 * s, colors[1], PAINT, false)
	local fan = at(frame, s, 1.25, h + 0.1, 0) * CFrame.Angles(0.09, -1.5, -0.16)
	wedge(parent, "Cap", fan, Vector3.new(12.8, 4.05, 13.3) * s, colors[2], NEON, false)
	wedge(parent, "ShelfCut", fan * CFrame.new(0.8 * s, 1.4 * s, 0.9 * s),
		Vector3.new(9.8, 2.34, 10.4) * s, colors[3], PAINT, false)
	return 10.6 * s
end

PlanetProps.bush = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(4.5, 6.5)
	if colors[2].G > 0.66 then
		h *= 0.7
	end
	wedge(parent, "GroundLeaf", at(frame, s, 0, h * 0.16, 3.1) * CFrame.Angles(0, 0.26, 0.13),
		Vector3.new(8.2, h * 0.78, 10.8) * s, colors[1], GRASS, false)
	wedge(parent, "FoldedLeaf", at(frame, s, -4.7, h * 0.32, -1.9) * CFrame.Angles(-0.18, 2.04, 0),
		Vector3.new(7.5, h * 1.24, 11.5) * s, colors[2], GRASS, false)
	wedge(parent, "FoldedLeaf", at(frame, s, 4.05, h * 0.2, -0.85) * CFrame.Angles(0.22, -1.92, -0.08),
		Vector3.new(7.6, h, 10.4) * s, shade(colors[2], 0.81), GRASS, false)
	return 12 * s
end

PlanetProps.cactus = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local rise = rng:NextNumber(0, 2)
	local green = colors[1]
	pad(parent, "CactusPaddle", at(frame, s, -1.7, 2.25, 0), 4.4 * s, 2.7 * s, shade(green, 0.79))
	pad(parent, "CactusPaddle", at(frame, s, 0.7, 7.25, 0.2) * CFrame.Angles(0.04, -0.16, 0), 4.3 * s, 2.45 * s, green)
	pad(parent, "CactusPaddle", at(frame, s, 4.5, 12.2 + rise, 0.65) * CFrame.Angles(0.09, 0.18, 0),
		3.9 * s, 2.12 * s, shade(green, 1.15))
	pad(parent, "CactusPaddle", at(frame, s, -4.8, 8 + rise, 0.35) * CFrame.Angles(-0.13, -0.24, 0),
		3.45 * s, 1.95 * s, shade(green, 0.91))
	return 9.3 * s
end

PlanetProps.deadTree = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local joint = Vector3.new(-2.4, 5.4, -0.4) * s
	local cap = Vector3.new(5.8, rng:NextNumber(8.9, 12.8), 1.9) * s
	local bark = colors[1]
	branch(parent, "WindfallBole", frame, Vector3.new(-5.2, -2.5, -1) * s, joint, 3.05 * s, bark, true)
	branch(parent, "BentCrown", frame, joint, cap, 2.12 * s, shade(bark, 0.93), false)
	branch(parent, "Splinter", frame, joint:Lerp(cap, 0.43), Vector3.new(2.0, 12.55, -4.1) * s,
		1.18 * s, shade(bark, 1.16), false)
	branch(parent, "Splinter", frame, cap, cap + Vector3.new(3.55, 3.8, -1.15) * s,
		0.85 * s, bark, false)
	return 12 * s
end

PlanetProps.crystal = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	wedge(parent, "LiftedHostRock", at(frame, s, -1.8, 1.3, 0.7) * CFrame.Angles(0.25, 0.49, 0.21),
		Vector3.new(14.7, 7.25, 11.35) * s, shade(colors[3], 0.31), SLATE, true)
	for i = 1, 3 do
		local sweep = (i - 2) * 4.15
		local size = rng:NextNumber(8.3, 12.4)
		local shard = at(frame, s, sweep, 2.9 + (i % 2) * 1.45, 2.75 - i * 1.6)
			* CFrame.Angles(-0.42, (i - 2) * 0.73 - 0.25, (2 - i) * 0.50)
		wedge(parent, "Crystal", shard, Vector3.new(4.75, 9.3, size) * s, colors[i], NEON, false)
	end
	return 13 * s
end

PlanetProps.palm = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local joint = Vector3.new(1.8, 8.7, 0.25) * s
	local topY = rng:NextNumber(17.6, 20.4)
	local head = Vector3.new(7.7, topY, 1.3) * s
	branch(parent, "WindwardTrunk", frame, Vector3.new(-2.8, -2.45, -1) * s, joint, 2.85 * s, colors[1], true)
	branch(parent, "WindwardTrunk", frame, joint, head, 2.12 * s, shade(colors[1], 1.16), true)
	frond(parent, "PalmFan", frame, head + Vector3.new(-1.0, 0.9, 0) * s, Vector3.new(17.45, topY - 3.5, -3.5) * s,
		11.7 * s, 3.7 * s, colors[2])
	frond(parent, "PalmFan", frame, head + Vector3.new(2.1, 0.65, 0) * s, Vector3.new(-4.8, topY - 0.1, 8.7) * s,
		10.4 * s, 3.15 * s, shade(colors[2], 0.83))
	return 20 * s
end

PlanetProps.volcano = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(172, 195) * s
	local h = rng:NextNumber(190, 228) * s
	local stone, molten = colors[1], colors[2]
	local floorY = -27
	cliff(parent, "SplitCalderaWall", base,
		Vector3.new(-0.94 * r, floorY, -0.11 * r), Vector3.new(-0.12 * r, floorY, -0.11 * r),
		Vector3.new(-0.31 * r, h, -0.11 * r), Vector3.new(-0.67 * r, h * 0.88, -0.11 * r),
		0.87 * r, stone, BASALT)
	cliff(parent, "FallenCalderaWall", base,
		Vector3.new(0.115 * r, floorY, 0.1 * r), Vector3.new(0.91 * r, floorY, 0.1 * r),
		Vector3.new(0.76 * r, h * 0.67, 0.1 * r), Vector3.new(0.33 * r, h * 0.77, 0.1 * r),
		0.81 * r, shade(stone, 0.8), BASALT)

	-- The outflow crosses the gap in both directions. The walls never cap it.
	box(parent, "CalderaBreach", base * CFrame.new(-0.012 * r, 1.25 * s, 0.08 * r),
		Vector3.new(0.47 * r, 3.3 * s, 1.40 * r), molten, NEON, false)
	local nearLeft = 0.325 * r + 0.45 * s
	local nearRight = 0.505 * r + 0.45 * s
	segment(parent, "LavaRibbon", base, Vector3.new(-0.186 * r, 2.5 * s, nearLeft),
		Vector3.new(-0.38 * r, 0.87 * h, nearLeft), 11 * s, 2.4 * s, molten, NEON, false)
	segment(parent, "LavaRibbon", base, Vector3.new(0.197 * r, 2.5 * s, nearRight),
		Vector3.new(0.42 * r, 0.67 * h, nearRight), 8 * s, 2.1 * s, shade(molten, 0.87), NEON, false)

	wedge(parent, "CollapsedRim", base * CFrame.new(-0.58 * r, 7 * s, 0.48 * r) * CFrame.Angles(0.15, 0.69, 0.08),
		Vector3.new(0.49 * r, 69 * s, 0.40 * r), shade(stone, 1.12), BASALT, true)
	wedge(parent, "CollapsedRim", base * CFrame.new(0.63 * r, 8 * s, -0.45 * r) * CFrame.Angles(-0.16, -0.57, -0.12),
		Vector3.new(0.37 * r, 62 * s, 0.44 * r), shade(stone, 0.9), BASALT, true)
	return 1.12 * r
end

PlanetProps.mountain = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(185, 225) * s
	local h = rng:NextNumber(191, 251) * s
	local cold = colors[2].R > 0.8
	local crest1, crest2 = 1, 0.71
	local crown = SNOW
	if not cold then
		h *= 0.72
		crest1, crest2 = 0.83, 0.61
		crown = GRASS
	end
	local nearZ, farZ = -0.18 * r, 0.14 * r
	local nearDepth, farDepth = 0.78 * r, 0.70 * r
	local leftTop = Vector3.new(-0.68 * r, (crest1 - 0.11) * h, nearZ)
	local leftCrown = Vector3.new(-0.31 * r, crest1 * h, nearZ)
	local rightCrown = Vector3.new(0.29 * r, crest2 * h, farZ)
	local rightTop = Vector3.new(0.65 * r, (crest2 - 0.09) * h, farZ)
	cliff(parent, "RaisedGlacialRidge", base,
		Vector3.new(-0.91 * r, -28, nearZ), Vector3.new(-0.075 * r, -28, nearZ),
		leftCrown, leftTop, nearDepth, colors[1], ROCK)
	cliff(parent, "BrokenGlacialRidge", base,
		Vector3.new(0.075 * r, -26, farZ), Vector3.new(0.94 * r, -26, farZ),
		rightTop, rightCrown, farDepth, shade(colors[1], 0.86), ROCK)

	segment(parent, "CrestShelf", base, leftTop - Vector3.new(0, 0.047 * h, 0),
		leftCrown - Vector3.new(0, 0.055 * h, 0), h * 0.125, nearDepth + 2.2 * s, colors[2], crown, true)
	segment(parent, "CrestShelf", base, rightCrown - Vector3.new(0, 0.042 * h, 0),
		rightTop - Vector3.new(0, 0.052 * h, 0), h * 0.101, farDepth + 1.8 * s, shade(colors[2], 0.91), crown, true)
	local strata = ICE
	if not cold then
		strata = ROCK
	end
	wedge(parent, "RidgeSaddle", base * CFrame.new(0.03 * r, -4 * s, -0.04 * r) * CFrame.Angles(0, 1.45, 0.06),
		Vector3.new(0.75 * r, 0.43 * h, 0.74 * r), shade(colors[1], 0.71), strata, true)
	wedge(parent, "ShearedMoraine", base * CFrame.new(0.21 * r, -6 * s, 0.44 * r) * CFrame.Angles(0, -1.11, -0.14),
		Vector3.new(0.39 * r, 0.27 * h, 0.53 * r), shade(colors[1], 1.13), strata, true)
	return 1.08 * r
end

PlanetProps.giantTree = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(143, 165) * s
	local bark = colors[1]
	local short = Vector3.new(54 * s, h * 0.77, -13 * s)
	local tall = Vector3.new(-48 * s, h, 2 * s)
	for _, side in ipairs({ -1, 1 }) do
		local head = tall
		if side == 1 then
			head = short
		end
		local foot = Vector3.new(side * 38 * s, -26, side * -7 * s)
		local elbow = head * 0.57 + Vector3.new(side * -14 * s, 0, 9 * s)
		branch(parent, "CanopyBridgeBole", base, foot, elbow, 23 * s, bark, true)
		branch(parent, "CanopyBridgeBole", base, elbow, head, 15.4 * s, shade(bark, 1.14), true)
		for _, rootSide in ipairs({ -1, 1 }) do
			local root = foot + Vector3.new(side * 15 * s, 1, rootSide * 22 * s)
			branch(parent, "RootSpur", base, root, elbow:Lerp(foot, 0.58), 9 * s,
				shade(bark, 0.92 + rootSide * 0.07), true)
		end
		local wing = head + Vector3.new(side * 36 * s, -5 * s, 20 * s)
		branch(parent, "LeafSpanBranch", base, elbow:Lerp(head, 0.53), wing, 10.5 * s, shade(bark, 0.87), false)
		frond(parent, "OuterCanopy", base, head + Vector3.new(side * -13 * s, 3 * s, -4 * s),
			wing + Vector3.new(side * 12 * s, -3 * s, 13 * s), 62 * s, 22 * s, colors[2])
		frond(parent, "RaisedCanopy", base, head + Vector3.new(side * -25 * s, 19 * s, 10 * s),
			head + Vector3.new(side * 29 * s, 12 * s, -31 * s), 51 * s, 18 * s, colors[3])
	end
	frond(parent, "CanopySpan", base, tall + Vector3.new(-10 * s, 10 * s, -4 * s),
		short + Vector3.new(21 * s, 20 * s, -8 * s), 44 * s, 16 * s, shade(colors[2], 0.93))
	return 118 * s
end

PlanetProps.mesa = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(117, 148) * s
	local h = rng:NextNumber(112, 145) * s
	local strata, ledge, plateau = colors[1], colors[2], colors[3]
	for _, side in ipairs({ -1, 1 }) do
		local capHeight = h
		if side == 1 then
			capHeight *= 0.67
		end
		local z = side * 0.17 * r
		local depth = r * (0.67 + side * 0.055)
		local outer = Vector3.new(side * 0.91 * r, -27, z)
		local inner = Vector3.new(side * 0.16 * r, -27, z)
		local capInside = Vector3.new(side * 0.20 * r, capHeight * 0.92, z)
		local capOutside = Vector3.new(side * 0.81 * r, capHeight, z)
		cliff(parent, "BrokenMesa", base, outer, inner, capInside, capOutside,
			depth, shade(strata, 1 + side * 0.06), SANDSTONE)

		local benchInside = inner:Lerp(capInside, 0.73) - Vector3.new(side * 1.8 * s, 0, -1.7 * s)
		local benchOutside = outer:Lerp(capOutside, 0.73) + Vector3.new(side * 4.2 * s, 0, 1.7 * s)
		segment(parent, "HangingStratum", base, benchInside, benchOutside,
			15 * s, depth + 5.8 * s, ledge, SANDSTONE, true)
		segment(parent, "ShearedPlateau", base, capInside + Vector3.new(side * -2.1 * s, -2.55 * s, 0),
			capOutside + Vector3.new(side * 3 * s, -2.9 * s, 0), 9.2 * s, depth + 6.2 * s, plateau, SANDSTONE, true)
		wedge(parent, "SlidSediment", base * CFrame.new(side * 0.69 * r, -10 * s, 0.43 * r)
			* CFrame.Angles(0.25, -side * 0.72, 0.09),
			Vector3.new(0.33 * r, 57 * s, 0.36 * r), shade(ledge, 0.84), SANDSTONE, true)
	end
	return 1.07 * r
end

PlanetProps.arch = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(88, 101) * s
	local h = rng:NextNumber(105, 128) * s
	local sandstone = colors[1]
	cliff(parent, "WindCutAbutment", base,
		Vector3.new(-0.94 * r, -26, -1.2 * s), Vector3.new(-0.48 * r, -26, -1.2 * s),
		Vector3.new(-0.18 * r, 0.91 * h, -1.2 * s), Vector3.new(-0.52 * r, 0.86 * h, -1.2 * s),
		38 * s, sandstone, SANDSTONE)
	cliff(parent, "LeaningAbutment", base,
		Vector3.new(0.35 * r, -26, 2.1 * s), Vector3.new(0.89 * r, -26, 2.1 * s),
		Vector3.new(0.68 * r, 0.73 * h, 2.1 * s), Vector3.new(0.38 * r, 0.68 * h, 2.1 * s),
		34 * s, shade(sandstone, 0.79), SANDSTONE)
	local leftEnd = Vector3.new(-0.52 * r, 0.95 * h, 0)
	local rightEnd = Vector3.new(0.67 * r, 0.79 * h, 2.8 * s)
	segment(parent, "FaultedLintel", base, leftEnd, rightEnd,
		24 * s, 43 * s, shade(sandstone, 1.08), SANDSTONE, true)
	segment(parent, "LintelCleavage", base, leftEnd + Vector3.new(0, 11.2 * s, -8.1 * s),
		leftEnd:Lerp(rightEnd, 0.73) + Vector3.new(0, 10.2 * s, -8.1 * s),
		6.4 * s, 21 * s, shade(sandstone, 0.86), SANDSTONE, true)
	wedge(parent, "ArchBreakaway", base * CFrame.new(0.67 * r, 0.01 * h, 15 * s) * CFrame.Angles(0.23, 0.6, 0.22),
		Vector3.new(24, 42, 35) * s, shade(sandstone, 1.17), SANDSTONE, true)
	return 1.04 * r
end

PlanetProps.spire = function(parent, base, s, colors, rng)
	local r = 97 * s
	local h = rng:NextNumber(222, 268) * s
	local host = shade(colors[3], 0.36)
	local z1, z2 = -7 * s, 9 * s
	local depth1, depth2 = 46 * s, 53 * s
	wedge(parent, "RivenBedrock", base * CFrame.new(0, -10, 0) * CFrame.Angles(0, 0.17, 0.02),
		Vector3.new(1.66 * r, 35 * s, 0.93 * r), host, SLATE, true)
	cliff(parent, "ResonantBlade", base,
		Vector3.new(-0.91 * r, -26, z1), Vector3.new(-0.33 * r, -26, z1),
		Vector3.new(-0.18 * r, h, z1), Vector3.new(-0.34 * r, h * 0.89, z1),
		depth1, shade(colors[3], 0.50), SLATE)
	cliff(parent, "ResonantBlade", base,
		Vector3.new(0.36 * r, -25, z2), Vector3.new(0.94 * r, -25, z2),
		Vector3.new(0.52 * r, h * 0.74, z2), Vector3.new(0.17 * r, h * 0.88, z2),
		depth2, shade(colors[3], 0.36), SLATE)

	-- The exposed faces run through the blade so the same stripe is visible from behind.
	segment(parent, "CrystalCleavage", base, Vector3.new(-0.49 * r, 0.13 * h, z1),
		Vector3.new(-0.275 * r, 0.79 * h, z1), 14.5 * s, depth1 + 1.3 * s, colors[2], NEON, false)
	segment(parent, "CrystalCleavage", base, Vector3.new(0.49 * r, 0.07 * h, z2),
		Vector3.new(0.265 * r, 0.70 * h, z2), 12.7 * s, depth2 + 1.4 * s, colors[1], NEON, false)
	wedge(parent, "SuspendedShard", at(base, s, -2, h * 0.63 / s, 1.8) * CFrame.Angles(0.44, 0.34, -0.89),
		Vector3.new(20, 39, 17) * s, shade(colors[2], 1.08), NEON, false)
	return 105 * s
end

PlanetProps.seaStack = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(40, 48) * s
	local h = rng:NextNumber(86, 105) * s
	local gray, grass = colors[1], colors[2]
	cliff(parent, "TideCutPier", base,
		Vector3.new(-0.86 * r, -27, 0), Vector3.new(-0.44 * r, -27, 0),
		Vector3.new(-0.29 * r, 0.85 * h, 0), Vector3.new(-0.58 * r, 0.93 * h, 0),
		0.86 * r, shade(gray, 0.87), ROCK)
	cliff(parent, "TideCutPier", base,
		Vector3.new(0.40 * r, -26, -0.08 * r), Vector3.new(0.91 * r, -26, -0.08 * r),
		Vector3.new(0.68 * r, 0.88 * h, -0.08 * r), Vector3.new(0.42 * r, 0.91 * h, -0.08 * r),
		0.62 * r, shade(gray, 0.81), ROCK)

	local roof = base * CFrame.new(0, 0.93 * h, -0.105 * r) * CFrame.Angles(0.072, -0.12, 0.034)
	box(parent, "TidalCanopy", roof, Vector3.new(1.65 * r, 0.23 * h, 0.96 * r), gray, ROCK, true)
	local gutter = 0.44 * r
	for _, side in ipairs({ -1, 1 }) do
		wedge(parent, "ErodedEave", roof * CFrame.new(0.77 * r * side, -0.022 * h, 0)
			* CFrame.Angles(0, side * -math.pi / 2, 0),
			Vector3.new(0.74 * r, 0.19 * h, 0.27 * r), shade(gray, 0.92), ROCK, true)
	end
	box(parent, "TideGrass", roof * CFrame.new(-0.085 * r, 0.115 * h + 2.2 * s, 0),
		Vector3.new(1.5 * r, 4.8 * s, gutter * 2), grass, GRASS, false)
	wedge(parent, "TideGrassLip", roof * CFrame.new(0.41 * r, 0.118 * h, -0.20 * r) * CFrame.Angles(0, -0.38, 0),
		Vector3.new(0.88 * r, 6.6 * s, 0.61 * r), shade(grass, 1.13), GRASS, false)
	return 1.17 * r
end

PlanetProps.lighthouse = function(parent, base, s, colors, rng)
	local white, red, amber = colors[1], colors[2], colors[3]
	local bedrock = Color3.fromRGB(81, 91, 98)
	local h = rng:NextNumber(57, 68) * s
	for _, side in ipairs({ -1, 1 }) do
		wedge(parent, "SplitBeaconFoot", base * CFrame.new(side * 16.1 * s, -7, -1.15 * s)
			* CFrame.Angles(0, side * -1.54, 0),
			Vector3.new(16.5 * s, 41 * s, 19.6 * s), bedrock, ROCK, true)
		wedge(parent, "SplitBeaconFoot", base * CFrame.new(side * 16.1 * s, -9, 7.0 * s)
			* CFrame.Angles(0, 0.27 * side, -0.14 * side),
			Vector3.new(16.4 * s, 35 * s, 13.5 * s), shade(bedrock, 0.76), ROCK, true)

		local foot = Vector3.new(side * 17.2 * s, 3 * s, -1.2 * s)
		local head = Vector3.new(side * 14.3 * s, h, 0)
		segment(parent, "BeaconPier", base, foot, head, 10.1 * s, 13.8 * s, white, PAINT, true)
		segment(parent, "BeaconPierStripe", base, foot:Lerp(head, 0.66), foot:Lerp(head, 0.79),
			10.27 * s, 14 * s, red, PAINT, false)
	end

	box(parent, "BeaconBase", base * CFrame.new(0, h + 1.5 * s, 0),
		Vector3.new(46.5, 10.5, 17.6) * s, red, PAINT, true)
	local lens = box(parent, "BeaconLens", base * CFrame.new(0.75 * s, h + 10.5 * s, 0.15 * s),
		Vector3.new(39, 8.1, 15.1) * s, amber, NEON, false)
	box(parent, "BeaconEave", base * CFrame.new(0, h + 15.9 * s, 0),
		Vector3.new(48, 3.5, 18.7) * s, white, PAINT, true)
	wedge(parent, "BeaconTop", base * CFrame.new(-1.2 * s, h + 19 * s, -0.3 * s) * CFrame.Angles(0, 0.03, 0),
		Vector3.new(43, 5.2, 16.6) * s, shade(white, 0.89), PAINT, false)

	local light = Instance.new("PointLight")
	light.Color = amber
	light.Range = 33
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = lens
	return 31 * s
end

return PlanetProps
