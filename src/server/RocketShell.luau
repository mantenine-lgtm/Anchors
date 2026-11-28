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
local STEEL = Color3.fromRGB(178, 182, 188)
local WELD = Color3.fromRGB(129, 132, 137)
local SOOT = Color3.fromRGB(93, 83, 82)
local CHARCOAL = Color3.fromRGB(43, 42, 44)
local TILE = Color3.fromRGB(29, 30, 33)
local NOZZLE = Color3.fromRGB(112, 100, 91)
local TILE_CENTER = 75
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function ringPoint(angleDeg: number, radius: number, y: number): Vector3
	local theta = math.rad(angleDeg)
	return Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius)
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
	part.Size = size
	part.CFrame = frame
	part.Color = color
	part.Material = material
	part.Parent = parent
end

local function block(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean): Part
	local part = Instance.new("Part")
	finish(part, parent, name, size, frame, color, material, solid)
	return part
end

local function wedge(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean): WedgePart
	local part = Instance.new("WedgePart")
	finish(part, parent, name, size, frame, color, material, solid)
	return part
end

local function cylinder(parent: Instance, name: string, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material, solid: boolean, axis: Vector3?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	local center = (axis or Vector3.zero) + Vector3.new(0, (y0 + y1) / 2, 0)
	finish(part, parent, name, Vector3.new(y1 - y0, 2 * radius, 2 * radius), CFrame.new(center) * UPRIGHT, color, material, solid)
	return part
end

-- Planet.triangle's longest-edge split. The input is the middle plane of the flap.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3)
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
	wedge(parent, name, Vector3.new(thickness, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2, right, up, back), color, METAL, true)
	wedge(parent, name, Vector3.new(thickness, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back), color, METAL, true)
end

local function radialFrame(angle: number, radius: number, y: number): CFrame
	return CFrame.new(ringPoint(angle, radius, y)) * CFrame.Angles(0, math.rad(angle), 0)
end

-- The far corners of a chord tile sit 0.285 studs above the nominal cylinder.
local function tileCourse(parent: Instance, opts: Opts, y0: number, y1: number, rows: number)
	local radius = opts.hullRadius
	local halfAngle = 4.25
	local outer = radius + 0.285
	local width = 2 * outer * math.sin(math.rad(halfAngle))
	local depth = 0.24
	local standOff = outer * math.cos(math.rad(halfAngle)) - depth / 2
	local pitch = (y1 - y0) / rows
	for column = 0, 1 do
		local angle = TILE_CENTER + (column - 0.5) * 9
		local stagger = column * pitch * 0.27
		for row = 0, rows - 1 do
			local bottom = y0 + row * pitch + stagger
			local top = bottom + pitch
			if row == 0 then
				bottom = y0
			end
			if row == rows - 1 then
				top = y1
			end
			bottom += 0.07
			top -= 0.07
			local clear = true
			if top >= opts.windowBottomY and bottom <= opts.windowTopY then
				-- The inward corners subtend a slightly larger angle.
				local cornerAngle = math.deg(math.atan2(width / 2, standOff - depth / 2))
				for _, window in ipairs(opts.windows) do
					local separation = math.abs((angle - window.centerDeg + 180) % 360 - 180)
					if separation <= window.halfDeg + cornerAngle then
						clear = false
						break
					end
				end
			end
			if clear then
				local color = TILE:Lerp(CHARCOAL, ((row + 2 * column) % 4) * 0.18)
				block(parent, "HeatTile", Vector3.new(width, top - bottom, depth),
					radialFrame(angle, standOff, (bottom + top) / 2), color, Enum.Material.Slate, false)
			end
		end
	end
end

local function plateHull(parent: Instance, radius: number, y0: number, y1: number, bays: number)
	local height = (y1 - y0) / bays
	for bay = 0, bays - 1 do
		local angle = 12 + bay * 13
		local color = STEEL:Lerp(WELD, 0.07 + bay * 0.05)
		block(parent, "MillFinishPanel", Vector3.new(radius * 0.17, height - 0.34, 0.21),
			radialFrame(angle, radius - 0.075, y0 + (bay + 0.5) * height), color, METAL, false)
	end
	for seam = 1, bays - 1 do
		local y = y0 + height * seam
		cylinder(parent, "CircumferentialWeld", radius + 0.14, y - 0.10, y + 0.10, WELD, METAL, false)
	end
	for _, angle in ipairs({ -49, 31 }) do
		block(parent, "LongitudinalWeld", Vector3.new(0.18, y1 - y0 - 0.20, 0.18),
			radialFrame(angle, radius + 0.045, (y0 + y1) / 2), WELD, METAL, false)
	end
end

local function scorchBand(parent: Instance, radius: number, baseY: number)
	cylinder(parent, "Scorch", radius + 0.18, baseY + 0.07, baseY + radius * 0.19,
		SOOT:Lerp(CHARCOAL, 0.45), Enum.Material.CorrodedMetal, false)

	-- The overlapping washes have slanted edges. Axial thickness contributes
	-- halfHeight * sin(tilt) to the radial envelope.
	for _, wash in ipairs({ { 0.15, 0.11, 0.22, 3, 20 }, { 0.13, 0.075, 0.195, 4, 137 } }) do
		local fringe = Instance.new("Part")
		fringe.Shape = Enum.PartType.Cylinder
		local tilt = CFrame.Angles(0, math.rad(wash[5]), 0) * CFrame.Angles(math.rad(wash[4]), 0, 0)
		local frame = CFrame.new(0, baseY + radius * wash[3], 0) * tilt * UPRIGHT
		local diameter = 2 * (radius + wash[1])
		local tint = SOOT:Lerp(STEEL, 0.13 + wash[4] * 0.055)
		finish(fringe, parent, "Scorch", Vector3.new(radius * wash[2], diameter, diameter),
			frame, tint, Enum.Material.CorrodedMetal, false)
	end
end

local function finishHull(parent: Instance, opts: Opts)
	local r = opts.hullRadius
	plateHull(parent, r, opts.baseY, opts.cabinFloorY, 3)
	plateHull(parent, r, opts.cabinCeilY, opts.topY, 2)
	cylinder(parent, "AftPanelRing", r + 0.23, opts.baseY + 0.18, opts.baseY + 1.26, WELD, METAL, false)
	cylinder(parent, "ShoulderWeld", r + 0.15, opts.topY - 0.42, opts.topY - 0.22, WELD, METAL, false)
	for _, seamY in ipairs({ opts.baseY + (opts.cabinFloorY - opts.baseY) / 3, (opts.cabinCeilY + opts.topY) / 2 }) do
		for _, angle in ipairs({ 18, 24, 30 }) do
			local rivet = Instance.new("Part")
			rivet.Shape = Enum.PartType.Ball
			finish(rivet, parent, "Rivet", Vector3.new(0.42, 0.42, 0.42),
				CFrame.new(ringPoint(angle, r + 0.035, seamY + 0.62)), STEEL:Lerp(WELD, 0.45), METAL, false)
		end
	end
	scorchBand(parent, r, opts.baseY)
	tileCourse(parent, opts, opts.baseY + 1.4, opts.cabinFloorY, 5)
	tileCourse(parent, opts, opts.cabinFloorY, opts.cabinCeilY, 2)
	tileCourse(parent, opts, opts.cabinCeilY, opts.topY - 0.45, 2)
end

-- Exterior hexagon on a sloping nose panel. Each pair of wedges ends in a point.
local function noseTile(parent: Instance, face: CFrame, width: number, length: number, color: Color3)
	local depth = 0.20
	local body = width * 0.62
	local sideWidth = (width - body) / 2
	block(parent, "NoseHeatTile", Vector3.new(body, length, depth), face, color, Enum.Material.Slate, false)
	for _, side in ipairs({ -1, 1 }) do
		for _, half in ipairs({ -1, 1 }) do
			local at = face:PointToWorldSpace(Vector3.new(side * (body + sideWidth) / 2, half * length / 4, 0))
			local up = half * face.UpVector
			local back = -side * face.RightVector
			wedge(parent, "NoseHeatTileBevel", Vector3.new(depth, length / 2, sideWidth),
				CFrame.fromMatrix(at, up:Cross(back), up, back), color, Enum.Material.Slate, false)
		end
	end
end

local function buildNose(parent: Instance, radius: number, topY: number)
	-- A tangent ogive joined internally tangent to a spherical cap.
	local curveR = radius * (1 + 1.9 ^ 2) / 2
	local capR = radius * 0.25
	local centerOffset = curveR - radius
	local capY = math.sqrt((curveR - capR) ^ 2 - centerOffset ^ 2)
	local joinY = capY * curveR / (curveR - capR)
	local levels = { 0, 0.27, 0.52, 0.77, 1 }
	local sides = 10
	local half = math.pi / sides
	local thickness = radius * 0.04
	for row = 1, #levels - 1 do
		local y0 = joinY * levels[row]
		local y1 = joinY * levels[row + 1]
		local r0 = math.sqrt(curveR ^ 2 - y0 ^ 2) - centerOffset
		local r1 = math.sqrt(curveR ^ 2 - y1 ^ 2) - centerOffset
		local width0 = 2 * r0 * math.sin(half)
		local width1 = 2 * r1 * math.sin(half)
		local wing = (width0 - width1) / 2
		-- The shallow courses can lap at the side seams. Tapered courses
		-- keep the steeper upper silhouette clean around the cap.
		local tapered = row >= 3
		local plateWidth = width0
		if tapered then
			plateWidth = width1
		end
		for side = 0, sides - 1 do
			local angle = TILE_CENTER + side * 360 / sides
			local low = ringPoint(angle, r0 * math.cos(half), topY + y0)
			local high = ringPoint(angle, r1 * math.cos(half), topY + y1)
			local rise = high - low
			local right = ringPoint(angle + 90, 1, 0)
			local up = rise.Unit
			local outward = right:Cross(up)
			local face = CFrame.fromMatrix((low + high) / 2, right, up, outward)
			local color = STEEL:Lerp(WELD, ((side + row * 2) % 5) * 0.045)
			local plate = block(parent, "NosePanel", Vector3.new(plateWidth, rise.Magnitude, thickness),
				face * CFrame.new(0, 0, -thickness / 2), color, METAL, true)
			if side == 2 or side == 6 or side == 9 then
				plate:SetAttribute("Heat", 0.60 + 0.12 * (row - 1))
			end
			if tapered then
				for _, sign in ipairs({ -1, 1 }) do
					local at = face:PointToWorldSpace(Vector3.new(sign * (width1 + wing) / 2, 0, -thickness / 2))
					local wedgeUp = sign * right
					local wedgeBack = -up
					wedge(parent, "NosePanelTaper", Vector3.new(thickness, wing, rise.Magnitude),
						CFrame.fromMatrix(at, wedgeUp:Cross(wedgeBack), wedgeUp, wedgeBack), color, METAL, true)
				end
			end
			if side == 0 then
				local tileFrame = face * CFrame.new(0, 0, 0.12)
				local width = math.min((width0 + width1) * 0.235, width1 * 0.96)
				local length = rise.Magnitude - 0.24
				if row == 1 then
					noseTile(parent, tileFrame, width, length, TILE)
				else
					local tint = TILE:Lerp(CHARCOAL, row % 2 * 0.25)
					block(parent, "NoseHeatTile", Vector3.new(width, length, 0.20),
						tileFrame, tint, Enum.Material.Slate, false)
				end
			end
		end
	end
	local tip = Instance.new("Part")
	tip.Shape = Enum.PartType.Ball
	finish(tip, parent, "NoseTip", Vector3.one * (2 * capR), CFrame.new(0, topY + capY, 0), STEEL, METAL, true)
	tip:SetAttribute("Heat", 1)
end

local function flap(parent: Instance, angle: number, r: number, originY: number, forward: boolean)
	local name = "AftFlap"
	local profile = { { 0.95, 0.42 }, { 1.69, 0.14 }, { 1.65, 0.71 }, { 0.95, 1.34 } }
	local thickness = 0.075 * r
	if forward then
		name = "ForwardFlap"
		profile = { { 0.89, 0.08 }, { 1.41, -0.12 }, { 1.37, 0.25 }, { 0.84, 0.68 } }
		thickness = 0.061 * r
	end
	local points = {}
	for i, pair in ipairs(profile) do
		points[i] = ringPoint(angle, pair[1] * r, originY + pair[2] * r)
	end
	local a, b, c, d = points[1], points[2], points[3], points[4]
	triangle(parent, name, a, b, c, thickness, STEEL)
	triangle(parent, name, a, c, d, thickness, STEEL)
	local tangent = ringPoint(angle + 90, 1, 0)
	local hinge = d - a
	block(parent, name .. "Hinge", Vector3.new(thickness * 1.75, hinge.Magnitude, r * 0.13),
		CFrame.fromMatrix((a + d) / 2, tangent, hinge.Unit, tangent:Cross(hinge.Unit)), WELD, METAL, true)
	local leading = c - d
	local edge = block(parent, name .. "LeadingEdge", Vector3.new(r * 0.031, thickness * 1.15, leading.Magnitude),
		CFrame.lookAt((c + d) / 2, c, tangent), STEEL:Lerp(WELD, 0.32), METAL, true)
	if forward then
		edge:SetAttribute("Heat", 0.5)
	end
end

local function bell(parent: Instance, center: Vector3, radius: number, mountY: number, baseY: number)
	local shoulderY = mountY + (baseY - mountY) * 0.43
	cylinder(parent, "BellFlare", radius, mountY, shoulderY,
		NOZZLE, Enum.Material.CorrodedMetal, true, center)
	cylinder(parent, "BellCollar", radius * 0.70, shoulderY, baseY + 0.32,
		CHARCOAL:Lerp(NOZZLE, 0.47), METAL, true, center)
end

local function buildEngines(parent: Instance, opts: Opts)
	local limit = opts.hullRadius - 6
	cylinder(parent, "EngineSkirt", limit, opts.baseY - 0.8, opts.baseY + 0.15,
		CHARCOAL, Enum.Material.DiamondPlate, true)
	cylinder(parent, "SkirtFlange", limit - 0.23, opts.baseY - 1.2, opts.baseY - 0.69, NOZZLE, METAL, true)
	for i = 0, 7 do
		bell(parent, ringPoint(i * 45, limit * 0.74, 0), limit * 0.25, opts.mountY, opts.baseY)
	end
	for i = 0, 2 do
		bell(parent, ringPoint(15 + i * 120, limit * 0.24, 0), limit * 0.17, opts.mountY, opts.baseY)
	end
end

function RocketShell.build(rocket: Model, opts: Opts): BasePart
	local r = opts.hullRadius
	local lower = cylinder(rocket, "LowerHull", r, opts.baseY, opts.cabinFloorY, STEEL, METAL, true)
	rocket.PrimaryPart = lower
	local upper = cylinder(rocket, "UpperHull", r, opts.cabinCeilY, opts.topY, STEEL, METAL, true)
	upper:SetAttribute("Heat", 0.3)
	finishHull(rocket, opts)
	buildNose(rocket, r, opts.topY)
	for _, angle in ipairs({ 120, 300 }) do
		flap(rocket, angle, r, opts.topY, true)
		flap(rocket, angle, r, opts.baseY, false)
	end
	buildEngines(rocket, opts)
	return lower
end

return RocketShell
