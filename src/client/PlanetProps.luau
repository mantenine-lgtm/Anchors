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

-- These four points are a tapered slope, with parallel upper and lower edges.
local function calderaFace(parent: Instance, base: CFrame, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	depth: number, color: Color3)
	local right = (b - a).Unit
	local bottom = (a + b) / 2
	local top = (c + d) / 2
	local rise = (top - bottom).Magnitude
	local up = (top - bottom).Unit
	local normal = right:Cross(up)
	local frame = base * CFrame.fromMatrix((bottom + top) / 2 - normal * depth / 2, right, up, normal)
	local width = (c - d).Magnitude
	local shoulder = ((b - a).Magnitude - width) / 2
	box(parent, "CalderaSlope", frame, Vector3.new(width, rise, depth), color, BASALT, true)
	for _, side in ipairs({ -1, 1 }) do
		local flank = frame.RightVector * side
		local towardFoot = -frame.UpVector
		local center = frame:PointToWorldSpace(Vector3.new(side * (width + shoulder) / 2, 0, 0))
		wedge(parent, "CalderaShoulder", CFrame.fromMatrix(center, flank:Cross(towardFoot), flank, towardFoot),
			Vector3.new(depth, shoulder, rise), color, BASALT, true)
	end
end

-- Offset the ridge coating from its matching rock plane to avoid coplanar faces.
local function glacialRidge(parent: Instance, base: CFrame, feet: { Vector3 }, tip: Vector3, s: number,
	stone: Color3, cover: Color3, surface: Enum.Material, coatedSide: number)
	local top = base:PointToWorldSpace(tip)
	local interior = base:PointToWorldSpace((feet[1] + feet[2] + feet[3] + tip) / 4)
	for side, corner in ipairs(feet) do
		local a = base:PointToWorldSpace(corner)
		local b = base:PointToWorldSpace(feet[side % 3 + 1])
		local depth = 12 * s
		triangle(parent, "KnifeRidge", a, b, top, depth, shade(stone, 0.81 + side * 0.1), ROCK)
		if side == coatedSide then
			local normal = (b - a):Cross(top - a).Unit
			if normal:Dot((a + b + top) / 3 - interior) < 0 then
				normal = -normal
			end
			local lift = normal * (depth / 2 + 0.6 * s)
			triangle(parent, "RidgeCover", a:Lerp(top, 0.66) + lift, b:Lerp(top, 0.48) + lift, top + lift,
				2.6 * s, cover, surface)
		end
	end
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
	box(parent, "FaultedSlab", at(frame, s, -3.8, 1.0, -1.2) * CFrame.Angles(-0.15, 0, -0.19),
		Vector3.new(span, 6.2, 9.1) * s, dark, mineral, true)
	wedge(parent, "ShearedCut", at(frame, s, 4.5, 2.6, 0.6) * CFrame.Angles(0.14, 0.66, 0.04),
		Vector3.new(span * 0.74, 9.0, 8.4) * s, bright, cut, true)
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
	local h = rng:NextNumber(16, 20)
	local crown = Vector3.new(3.9, h, 0) * s
	branch(parent, "LeafBridgeTrunk", frame, Vector3.new(-2, -2.6, 0) * s, crown,
		3.6 * s, colors[1], true)
	frond(parent, "BroadleafWing", frame, crown + Vector3.new(1.7, 3.45, -0.6) * s,
		Vector3.new(-10.6, h - 0.25, -2.0) * s, 13.6 * s, 11.8 * s, colors[2])
	frond(parent, "RaisedLeafWing", frame, crown + Vector3.new(-2.05, 6.2, -1.3) * s,
		Vector3.new(13.5, h + 2.7, 5.2) * s, 11.5 * s, 10.6 * s, colors[3])
	return 16.2 * s
end

PlanetProps.mushroom = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(9.5, 13.5)
	local tip = Vector3.new(-2.65, h, 0) * s
	segment(parent, "ShelfStalk", frame, Vector3.new(-4, -1.8, -1) * s, tip, 3.0 * s, 2.5 * s, colors[1], PAINT, false)
	local fan = at(frame, s, 1.25, h + 1.4, 0) * CFrame.Angles(0.09, -1.5, -0.16)
	wedge(parent, "Cap", fan, Vector3.new(13.3, 6.9, 13.7) * s, colors[2], NEON, false)
	wedge(parent, "ShelfCut", fan * CFrame.new(0.4 * s, 2.8 * s, 0.8 * s),
		Vector3.new(10.4, 4.35, 10.5) * s, colors[3], PAINT, false)
	return 11.2 * s
end

PlanetProps.bush = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local h = rng:NextNumber(6.4, 8.4)
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
	pad(parent, "CactusPaddle", at(frame, s, -1.7, 2.25, 0), 4.4 * s, 3.75 * s, shade(green, 0.79))
	pad(parent, "CactusPaddle", at(frame, s, 0.7, 7.25, 0.2) * CFrame.Angles(0.04, -0.16, 0), 4.3 * s, 3.6 * s, green)
	pad(parent, "CactusPaddle", at(frame, s, 4.5, 12.2 + rise, 0.65) * CFrame.Angles(0.09, 0.18, 0),
		3.9 * s, 3.25 * s, shade(green, 1.15))
	pad(parent, "CactusPaddle", at(frame, s, -4.8, 8 + rise, 0.35) * CFrame.Angles(-0.13, -0.24, 0),
		3.45 * s, 2.9 * s, shade(green, 0.91))
	return 9.6 * s
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
	wedge(parent, "LiftedHostRock", at(frame, s, -1.8, 2.1, 0.7) * CFrame.Angles(0.25, 0.49, 0.21),
		Vector3.new(14.7, 9.4, 11.35) * s, shade(colors[3], 0.31), SLATE, true)
	for i = 1, 3 do
		local sweep = (i - 2) * 4.15
		local size = rng:NextNumber(8.9, 11.7)
		local height = 19.4 - math.abs(i - 2) * 5.0
		local shard = at(frame, s, sweep, height * 0.49, 2.75 - i * 1.6)
			* CFrame.Angles(-0.18, (i - 2) * 0.62 - 0.25, (2 - i) * 0.42)
		wedge(parent, "Crystal", shard, Vector3.new(5.9, height, size) * s, colors[i], NEON, false)
	end
	return 14.5 * s
end

PlanetProps.palm = function(parent, base, s, colors, rng)
	local frame = base * CFrame.Angles(0, rng:NextNumber(0, TURN), 0)
	local joint = Vector3.new(1.4, 10.7, 0.25) * s
	local topY = rng:NextNumber(21.1, 24.9)
	local head = Vector3.new(7.7, topY, 1.3) * s
	branch(parent, "WindwardTrunk", frame, Vector3.new(-2.8, -2.45, -1) * s, joint, 3.5 * s, colors[1], true)
	branch(parent, "WindwardTrunk", frame, joint, head, 2.75 * s, shade(colors[1], 1.16), true)
	frond(parent, "PalmFan", frame, head + Vector3.new(-1.0, 2.2, 0) * s, Vector3.new(17.5, topY - 6.1, -3.1) * s,
		13.1 * s, 8.6 * s, colors[2])
	frond(parent, "PalmFan", frame, head + Vector3.new(1.2, 2.5, -1.8) * s, Vector3.new(-6.5, topY - 4.2, 8.8) * s,
		12.1 * s, 7.1 * s, shade(colors[2], 0.83))
	return 20 * s
end

PlanetProps.volcano = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(192, 218) * s
	local h = rng:NextNumber(239, 284) * s
	local stone, molten = colors[1], colors[2]
	local foot, lip = 0.685 * r, 0.252 * r
	local footY = -27
	local lower = {
		Vector3.new(-foot, footY, foot), Vector3.new(foot, footY, foot),
		Vector3.new(foot, footY, -foot), Vector3.new(-foot, footY, -foot),
	}
	local crest = {
		Vector3.new(-lip, h, lip), Vector3.new(lip, h, lip),
		Vector3.new(lip, h, -lip), Vector3.new(-lip, h, -lip),
	}
	for side = 2, 4 do
		local j = side % 4 + 1
		calderaFace(parent, base, lower[side], lower[j], crest[j], crest[side], 9 * s, shade(stone, 0.79 + 0.09 * side))
	end

	-- Two triangular flanks fall away from the broken lip, leaving a V-shaped outlet.
	local breachNormal = Vector3.xAxis:Cross(crest[1] - lower[1]).Unit
	local setback = breachNormal * (4.5 * s)
	local toewardLeft = lower[1]:Lerp(lower[2], 0.41)
	local toewardRight = lower[2]:Lerp(lower[1], 0.41)
	triangle(parent, "BrokenCalderaRim", base:PointToWorldSpace(lower[1] - setback),
		base:PointToWorldSpace(toewardLeft - setback), base:PointToWorldSpace(crest[1] - setback),
		9 * s, shade(stone, 1.10), BASALT)
	triangle(parent, "BrokenCalderaRim", base:PointToWorldSpace(toewardRight - setback),
		base:PointToWorldSpace(lower[2] - setback), base:PointToWorldSpace(crest[2] - setback),
		9 * s, shade(stone, 0.89), BASALT)

	-- The molten surface sits between the three intact rim walls.
	part(parent, "Part", "CalderaLake", Vector3.new(6.4 * s, 1.91 * lip, 1.91 * lip),
		base * CFrame.new(0, h - 2.0 * s, 0) * CFrame.Angles(0, 0, math.pi / 2),
		molten, NEON, false, Enum.PartType.Cylinder)
	segment(parent, "BreachLavafall", base, Vector3.new(0.09 * lip, h - 0.6 * s, lip * 0.75),
		Vector3.new(-0.09 * foot, 2.7 * s, foot + 5.1 * s), r * 0.139, 5.8 * s,
		molten, NEON, false)

	-- A hot seam on the opposite face remains visible when the mouth faces away.
	local rearStart = Vector3.new(-0.29 * lip, h + 0.45 * s, -lip - 0.6 * s)
	local rearEnd = rearStart:Lerp(Vector3.new(-0.25 * foot, footY, -foot - 1.6 * s), 0.83)
	segment(parent, "RearLavaSeam", base, rearStart, rearEnd, r * 0.078, 5.4 * s, shade(molten, 0.92), NEON, false)
	return r
end

PlanetProps.mountain = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(188, 222) * s
	local h = rng:NextNumber(271, 320) * s
	local cold = colors[2].R > 0.8
	local surface = SNOW
	local short = 0.76
	if not cold then
		h *= 0.92
		short = 0.82
		surface = GRASS
	end

	local forwardPeak = Vector3.new(-0.35 * r, h, -0.21 * r)
	local crossedPeak = Vector3.new(0.47 * r, h * short, 0.34 * r)
	local forwardFeet = {
		Vector3.new(-0.96 * r, -24, -0.38 * r), Vector3.new(0.45 * r, -24, -0.62 * r),
		Vector3.new(-0.42 * r, -24, 0.80 * r),
	}
	local crossedFeet = {
		Vector3.new(-0.48 * r, -25, -0.37 * r), Vector3.new(0.73 * r, -25, -0.68 * r),
		Vector3.new(0.88 * r, -25, 0.59 * r),
	}
	glacialRidge(parent, base, forwardFeet, forwardPeak, s, colors[1], colors[2], surface, 1)
	glacialRidge(parent, base, crossedFeet, crossedPeak, s,
		shade(colors[1], 0.9), shade(colors[2], 0.94), surface, 3)
	return 1.12 * r
end

PlanetProps.giantTree = function(parent, base, s, colors, rng)
	local h = rng:NextNumber(208, 241) * s
	local bark = colors[1]
	local short = Vector3.new(48 * s, h * 0.83, -15 * s)
	local tall = Vector3.new(-46 * s, h, 1.5 * s)
	for _, side in ipairs({ -1, 1 }) do
		local head = tall
		if side == 1 then
			head = short
		end
		local foot = Vector3.new(side * 36 * s, -26, side * -8 * s)
		local elbow = head * 0.53 + Vector3.new(side * -12 * s, 0, 10 * s)
		branch(parent, "CanopyBridgeBole", base, foot, elbow, 29 * s, bark, true)
		branch(parent, "CanopyBridgeBole", base, elbow, head, 23.6 * s, shade(bark, 1.14), true)
		for _, rootSide in ipairs({ -1, 1 }) do
			local root = foot + Vector3.new(side * 19 * s, 1.8, rootSide * 24 * s)
			branch(parent, "RootSpur", base, root, elbow:Lerp(foot, 0.66), 12 * s,
				shade(bark, 0.92 + rootSide * 0.07), true)
		end
		local wing = head + Vector3.new(side * 28 * s, -5 * s, 17 * s)
		branch(parent, "LeafSpanBranch", base, elbow:Lerp(head, 0.55), wing, 15.6 * s, shade(bark, 0.87), false)
		frond(parent, "OuterCrown", base, head + Vector3.new(side * -14 * s, 9 * s, -16 * s),
			wing + Vector3.new(side * 16 * s, -8 * s, 22 * s), 76 * s, 55 * s, colors[2])
		frond(parent, "RaisedCrown", base, head + Vector3.new(side * -18 * s, 29 * s, 22 * s),
			head + Vector3.new(side * 34 * s, 8 * s, -42 * s), 67 * s, 40 * s, colors[3])
	end
	frond(parent, "SpanCrown", base, tall + Vector3.new(-5 * s, 14 * s, -2 * s),
		short + Vector3.new(21 * s, 25 * s, -8 * s), 66 * s, 39 * s, shade(colors[2], 0.87))
	frond(parent, "SpanCrown", base, short + Vector3.new(-10 * s, 39 * s, 19 * s),
		tall + Vector3.new(-23 * s, -9 * s, 34 * s), 60 * s, 35 * s, shade(colors[3], 0.92))
	return 118 * s
end

PlanetProps.mesa = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(136, 160) * s
	local h = rng:NextNumber(172, 215) * s
	local strata, ledge, plateau = colors[1], colors[2], colors[3]
	for _, side in ipairs({ -1, 1 }) do
		local capHeight = h
		local z = -0.19 * r
		local depth = 0.94 * r
		if side == 1 then
			capHeight *= 0.72
			z = 0.20 * r
			depth = 0.77 * r
		end
		local outer = Vector3.new(side * 0.95 * r, -26, z)
		local inner = Vector3.new(side * -0.04 * r, -26, z)
		local capInside = Vector3.new(side * 0.20 * r, capHeight * 0.91, z)
		local capOutside = Vector3.new(side * 0.72 * r, capHeight, z)
		cliff(parent, "BrokenMesa", base, outer, inner, capInside, capOutside,
			depth, shade(strata, 1 + side * 0.06), SANDSTONE)

		local benchInside = inner:Lerp(capInside, 0.68) - Vector3.new(side * 2.9 * s, 0, -1.7 * s)
		local benchOutside = outer:Lerp(capOutside, 0.68) + Vector3.new(side * 4.8 * s, 0, 1.7 * s)
		segment(parent, "HangingStratum", base, benchInside, benchOutside,
			22 * s, depth + 7.8 * s, ledge, SANDSTONE, true)
		segment(parent, "ShearedPlateau", base, capInside + Vector3.new(side * -2.1 * s, -5.4 * s, 0),
			capOutside + Vector3.new(side * 3.1 * s, -5.5 * s, 0), 19 * s, depth + 9 * s, plateau, SANDSTONE, true)
		wedge(parent, "ShearedScree", base * CFrame.new(side * 0.68 * r, 41.5 * s - 23, side * 0.53 * r)
			* CFrame.Angles(0.07, side * 2.97, 0.10 * side),
			Vector3.new(0.48 * r, 83 * s, 0.58 * r), shade(ledge, 0.70 + side * 0.07), SANDSTONE, true)
	end
	return 1.22 * r
end

PlanetProps.arch = function(parent, base, s, colors, rng)
	local r = rng:NextNumber(95, 108) * s
	local h = rng:NextNumber(151, 181) * s
	local sandstone = colors[1]
	local leftZ, rightZ = -12 * s, 15 * s
	cliff(parent, "WindCutAbutment", base,
		Vector3.new(-0.97 * r, -26, leftZ), Vector3.new(-0.43 * r, -26, leftZ),
		Vector3.new(-0.13 * r, 0.92 * h, leftZ), Vector3.new(-0.55 * r, 0.86 * h, leftZ),
		56 * s, sandstone, SANDSTONE)
	cliff(parent, "LeaningAbutment", base,
		Vector3.new(0.33 * r, -26, rightZ), Vector3.new(0.94 * r, -26, rightZ),
		Vector3.new(0.70 * r, 0.75 * h, rightZ), Vector3.new(0.32 * r, 0.69 * h, rightZ),
		51 * s, shade(sandstone, 0.79), SANDSTONE)
	local leftEnd = Vector3.new(-0.56 * r, 0.92 * h, leftZ)
	local rightEnd = Vector3.new(0.68 * r, 0.77 * h, rightZ)
	segment(parent, "FaultedLintel", base, leftEnd, rightEnd,
		38 * s, 63 * s, shade(sandstone, 1.12), SANDSTONE, true)
	segment(parent, "LintelCleavage", base, leftEnd + Vector3.new(3 * s, 15.7 * s, -11 * s),
		leftEnd:Lerp(rightEnd, 0.75) + Vector3.new(0, 14.8 * s, -12 * s),
		13.5 * s, 33 * s, shade(sandstone, 0.86), SANDSTONE, true)
	wedge(parent, "ArchBreakaway", base * CFrame.new(0.72 * r, 0.08 * h, 22 * s) * CFrame.Angles(0.18, 0.48, 0.16),
		Vector3.new(39, 68, 43) * s, shade(sandstone, 1.05), SANDSTONE, true)
	return 1.16 * r
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
