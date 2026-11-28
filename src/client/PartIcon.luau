--!strict
-- 부품 아이콘 (부품 도감 180종, Catalog.luau). 바탕 타일은 레어도 색 테두리, 뒤에는 빛 무늬(Look.Aura: 고리·날개·빛살 등).
-- 가운데 그림은 GPT 로 만든 모양(Look.Shape, 종류마다 5개)을 금속·칠·빛 세 층으로 겹쳐 부품 색으로 칠함
-- (Nick 11-28 "부품 이미지 GPT로 생성", "색 필터 바꿔서 애셋 사용을 줄여줘": 그림은 종류마다 1장, 모두 6장).
-- 그림 Id(Catalog.IconImages)가 비어 있으면 예전처럼 Frame 몇 개로 몸통(Look.Body)을 그림.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))

local Ui = require(script.Parent:WaitForChild("Ui"))

local PartIcon = {}

local SILHOUETTE = Color3.fromRGB(46, 52, 70)
local SILHOUETTE_BACK = Color3.fromRGB(22, 26, 38)
local imageArt: (Frame, Catalog.Variant, boolean) -> boolean -- 아래 (GPT 그림)

type Paint = { main: Color3, accent: Color3, glow: Color3, dark: boolean }

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local frame = Ui.frame(parent, "Piece", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
	})
	if props then
		for key, value in pairs(props) do
			(frame :: any)[key] = value
		end
	end
	return frame
end

local function round(frame: Frame, radius: number?)
	Ui.make("UICorner", { CornerRadius = if radius then UDim.new(radius, 0) else UDim.new(0.5, 0), Parent = frame })
end

local function pill(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local frame = box(parent, x, y, w, h, color, props)
	round(frame)
	return frame
end

local function circle(parent: Instance, x: number, y: number, d: number, color: Color3, transparency: number?): Frame
	return pill(parent, x, y, d, d, color, { BackgroundTransparency = transparency or 0 })
end

local function ring(parent: Instance, x: number, y: number, d: number, color: Color3, thickness: number, transparency: number?): Frame
	local frame = pill(parent, x, y, d, d, color, { BackgroundTransparency = 1 })
	Ui.stroke(frame, color, thickness, transparency or 0)
	return frame
end

-- 기울어진 타원 테두리 (궤도)
local function orbit(parent: Instance, x: number, y: number, w: number, h: number, rotation: number, color: Color3, thickness: number, transparency: number?): Frame
	local frame = pill(parent, x, y, w, h, color, { BackgroundTransparency = 1, Rotation = rotation })
	Ui.stroke(frame, color, thickness, transparency or 0)
	return frame
end

-- ------------------------------------------------------------ 뒤 빛 무늬 (Look.Aura)
local function aura(holder: Frame, kind: string, paint: Paint, px: number)
	local glow = paint.glow
	local soft = if paint.dark then 0 else 0.35
	local thin = math.max(1, math.floor(px / 40))
	if kind == "ring" then
		ring(holder, 0.5, 0.5, 0.84, glow, thin + 1, soft)
	elseif kind == "rings" then
		ring(holder, 0.5, 0.5, 0.86, glow, thin, soft)
		ring(holder, 0.5, 0.5, 0.68, glow, thin, soft + 0.15)
	elseif kind == "orbit" then
		orbit(holder, 0.5, 0.52, 0.96, 0.32, -22, glow, thin + 1, soft)
	elseif kind == "wings" then
		for _, side in ipairs({ -1, 1 }) do
			pill(holder, 0.5 + side * 0.3, 0.42, 0.34, 0.16, glow, { Rotation = side * -28, BackgroundTransparency = soft })
			pill(holder, 0.5 + side * 0.28, 0.58, 0.26, 0.12, glow, { Rotation = side * -10, BackgroundTransparency = soft + 0.2 })
		end
	elseif kind == "burst" then
		for i = 0, 3 do
			box(holder, 0.5, 0.5, 0.05, 0.92, glow, { Rotation = i * 45, BackgroundTransparency = soft + 0.15 })
		end
	elseif kind == "bolt" then
		box(holder, 0.18, 0.3, 0.05, 0.24, glow, { Rotation = 25, BackgroundTransparency = soft })
		box(holder, 0.2, 0.5, 0.05, 0.22, glow, { Rotation = -35, BackgroundTransparency = soft })
		box(holder, 0.17, 0.7, 0.05, 0.24, glow, { Rotation = 25, BackgroundTransparency = soft })
		box(holder, 0.82, 0.36, 0.05, 0.22, glow, { Rotation = -25, BackgroundTransparency = soft })
		box(holder, 0.8, 0.56, 0.05, 0.2, glow, { Rotation = 35, BackgroundTransparency = soft })
	elseif kind == "dots" then
		circle(holder, 0.18, 0.26, 0.1, glow, soft)
		circle(holder, 0.84, 0.3, 0.08, glow, soft)
		circle(holder, 0.2, 0.76, 0.07, glow, soft)
		circle(holder, 0.82, 0.74, 0.11, glow, soft)
	elseif kind == "grid" then
		for i = 1, 3 do
			box(holder, i * 0.25, 0.5, 0.02, 0.8, glow, { BackgroundTransparency = soft + 0.25 })
			box(holder, 0.5, i * 0.25, 0.8, 0.02, glow, { BackgroundTransparency = soft + 0.25 })
		end
	elseif kind == "flame" then
		circle(holder, 0.5, 0.86, 0.36, glow, soft)
		box(holder, 0.5, 0.74, 0.24, 0.24, glow, { Rotation = 45, BackgroundTransparency = soft })
	end
end

-- ------------------------------------------------------------ 종류별 몸통 4가지 (Look.Body)
local function flame(holder: Frame, paint: Paint, x: number, size: number, tall: number?)
	circle(holder, x, 0.8, size, paint.glow, if paint.dark then 0 else 0.1)
	box(holder, x, 0.8 - size * 0.35 - (tall or 0) / 2, size * 0.7, size * 0.7 + (tall or 0), paint.glow, { Rotation = if tall then 0 else 45 })
end

local function engine(holder: Frame, paint: Paint, body: string)
	if body == "twin" then
		for _, x in ipairs({ 0.34, 0.66 }) do
			flame(holder, paint, x, 0.18)
			pill(holder, x, 0.4, 0.2, 0.42, paint.main)
			box(holder, x, 0.62, 0.24, 0.09, paint.accent)
		end
		box(holder, 0.5, 0.4, 0.2, 0.08, paint.accent)
	elseif body == "pillar" then
		flame(holder, paint, 0.5, 0.2, 0.18)
		local tall = box(holder, 0.5, 0.36, 0.24, 0.56, paint.main)
		round(tall, 0.4)
		box(holder, 0.5, 0.28, 0.24, 0.05, paint.accent)
		box(holder, 0.5, 0.42, 0.24, 0.05, paint.accent)
		box(holder, 0.5, 0.64, 0.32, 0.08, paint.accent)
		circle(holder, 0.5, 0.12, 0.12, paint.glow)
	elseif body == "wide" then
		pill(holder, 0.5, 0.8, 0.56, 0.2, paint.glow, { BackgroundTransparency = if paint.dark then 0 else 0.1 })
		local hull = box(holder, 0.5, 0.42, 0.62, 0.32, paint.main)
		round(hull, 0.35)
		for _, x in ipairs({ 0.3, 0.5, 0.7 }) do
			box(holder, x, 0.64, 0.14, 0.12, paint.accent)
		end
		circle(holder, 0.5, 0.4, 0.14, paint.glow)
	else -- standard
		flame(holder, paint, 0.5, 0.26)
		local hull = box(holder, 0.5, 0.38, 0.34, 0.42, paint.main)
		round(hull, 0.25)
		circle(holder, 0.5, 0.18, 0.28, paint.accent)
		box(holder, 0.5, 0.61, 0.44, 0.12, paint.accent)
	end
end

local function heat(holder: Frame, paint: Paint, body: string)
	if body == "fan" then
		circle(holder, 0.5, 0.5, 0.62, paint.main)
		for i = 0, 2 do
			pill(holder, 0.5, 0.5, 0.12, 0.54, paint.accent, { Rotation = i * 60 })
		end
		circle(holder, 0.5, 0.5, 0.16, paint.glow)
	elseif body == "panels" then
		box(holder, 0.5, 0.5, 0.1, 0.66, paint.accent)
		for _, x in ipairs({ 0.27, 0.73 }) do
			local panel = box(holder, x, 0.5, 0.34, 0.56, paint.main)
			round(panel, 0.1)
			box(holder, x, 0.5, 0.34, 0.04, paint.glow)
			box(holder, x, 0.5, 0.04, 0.56, paint.accent)
		end
		circle(holder, 0.5, 0.5, 0.14, paint.glow)
	elseif body == "coil" then
		pill(holder, 0.5, 0.5, 0.16, 0.72, paint.main)
		for i = 0, 3 do
			pill(holder, 0.5, 0.31 + i * 0.13, 0.54, 0.08, if i % 2 == 0 then paint.accent else paint.main)
		end
		circle(holder, 0.5, 0.14, 0.14, paint.glow)
		circle(holder, 0.5, 0.86, 0.14, paint.glow)
	else -- fins
		local plate = box(holder, 0.5, 0.5, 0.6, 0.5, paint.main)
		round(plate, 0.12)
		for i = 0, 3 do
			box(holder, 0.32 + i * 0.12, 0.5, 0.06, 0.66, paint.accent)
		end
		box(holder, 0.5, 0.78, 0.5, 0.05, paint.glow)
	end
end

local function fuel(holder: Frame, paint: Paint, body: string)
	if body == "sphere" then
		box(holder, 0.5, 0.84, 0.36, 0.06, paint.accent)
		circle(holder, 0.5, 0.5, 0.6, paint.main)
		box(holder, 0.5, 0.5, 0.6, 0.07, paint.accent)
		circle(holder, 0.5, 0.5, 0.22, paint.glow)
	elseif body == "twin" then
		for _, x in ipairs({ 0.35, 0.65 }) do
			pill(holder, x, 0.52, 0.24, 0.64, paint.main)
			box(holder, x, 0.42, 0.24, 0.05, paint.accent)
			box(holder, x, 0.62, 0.24, 0.05, paint.accent)
		end
		circle(holder, 0.5, 0.52, 0.12, paint.glow)
	elseif body == "drum" then
		local drum = box(holder, 0.5, 0.53, 0.5, 0.58, paint.main)
		round(drum, 0.14)
		for _, y in ipairs({ 0.34, 0.53, 0.72 }) do
			box(holder, 0.5, y, 0.52, 0.05, paint.accent)
		end
		circle(holder, 0.62, 0.44, 0.12, paint.glow)
	else -- tank
		pill(holder, 0.5, 0.53, 0.42, 0.64, paint.main)
		box(holder, 0.5, 0.41, 0.42, 0.06, paint.accent)
		box(holder, 0.5, 0.65, 0.42, 0.06, paint.accent)
		box(holder, 0.5, 0.18, 0.18, 0.08, paint.accent)
		circle(holder, 0.5, 0.53, 0.14, paint.glow)
	end
end

local function sail(holder: Frame, paint: Paint, body: string)
	box(holder, 0.5, 0.55, 0.04, 0.76, paint.accent)
	if body == "square" then
		local cloth = box(holder, 0.5, 0.44, 0.52, 0.46, paint.main, { BackgroundTransparency = 0.1 })
		round(cloth, 0.12)
		box(holder, 0.5, 0.44, 0.32, 0.3, paint.glow, { BackgroundTransparency = 0.45 })
	elseif body == "dome" then
		-- 우산처럼 위 반원 (자르는 틀 안에 원을 넣어 아래 반을 숨김)
		local clip = Ui.frame(holder, "Dome", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.72, 0.36),
			ClipsDescendants = true,
		})
		local top = box(clip, 0.5, 1, 1, 2, paint.main, { BackgroundTransparency = 0.05 })
		round(top)
		local inner = box(clip, 0.5, 1, 0.56, 1.12, paint.glow, { BackgroundTransparency = 0.45 })
		round(inner)
		box(holder, 0.5, 0.52, 0.76, 0.05, paint.accent)
	elseif body == "double" then
		local upper = box(holder, 0.5, 0.29, 0.38, 0.24, paint.main, { BackgroundTransparency = 0.1 })
		round(upper, 0.15)
		local lower = box(holder, 0.5, 0.6, 0.56, 0.3, paint.main, { BackgroundTransparency = 0.1 })
		round(lower, 0.15)
		box(holder, 0.5, 0.29, 0.22, 0.12, paint.glow, { BackgroundTransparency = 0.45 })
		box(holder, 0.5, 0.6, 0.36, 0.16, paint.glow, { BackgroundTransparency = 0.45 })
	else -- diamond
		box(holder, 0.5, 0.42, 0.46, 0.46, paint.main, { Rotation = 45, BackgroundTransparency = 0.1 })
		box(holder, 0.5, 0.42, 0.28, 0.28, paint.glow, { Rotation = 45, BackgroundTransparency = 0.4 })
	end
end

local function nav(holder: Frame, paint: Paint, body: string)
	if body == "dish" then
		box(holder, 0.5, 0.84, 0.36, 0.07, paint.accent)
		box(holder, 0.5, 0.72, 0.08, 0.22, paint.main)
		pill(holder, 0.45, 0.48, 0.66, 0.3, paint.main, { Rotation = -25 })
		pill(holder, 0.45, 0.46, 0.46, 0.16, paint.accent, { Rotation = -25 })
		box(holder, 0.6, 0.32, 0.04, 0.3, paint.accent, { Rotation = 35 })
		circle(holder, 0.68, 0.2, 0.13, paint.glow)
	elseif body == "chip" then
		for i = -1, 1 do
			box(holder, 0.5, 0.5 + i * 0.13, 0.7, 0.05, paint.accent)
			box(holder, 0.5 + i * 0.13, 0.5, 0.05, 0.7, paint.accent)
		end
		local chip = box(holder, 0.5, 0.5, 0.48, 0.48, paint.main)
		round(chip, 0.12)
		box(holder, 0.5, 0.5, 0.26, 0.26, paint.accent, { BackgroundTransparency = 0.2 })
		circle(holder, 0.5, 0.5, 0.12, paint.glow)
	elseif body == "antenna" then
		box(holder, 0.62, 0.36, 0.04, 0.4, paint.accent, { Rotation = 12 })
		circle(holder, 0.66, 0.15, 0.12, paint.glow)
		local radio = box(holder, 0.5, 0.64, 0.5, 0.36, paint.main)
		round(radio, 0.2)
		for i = 0, 1 do
			box(holder, 0.38, 0.58 + i * 0.12, 0.16, 0.04, paint.accent)
		end
		circle(holder, 0.62, 0.64, 0.14, paint.glow)
	else -- screen
		local screen = box(holder, 0.5, 0.48, 0.66, 0.5, paint.main)
		round(screen, 0.15)
		local inner = box(holder, 0.5, 0.48, 0.54, 0.38, paint.accent)
		round(inner, 0.12)
		box(holder, 0.5, 0.48, 0.42, 0.03, paint.glow)
		box(holder, 0.5, 0.48, 0.03, 0.3, paint.glow)
		circle(holder, 0.62, 0.42, 0.08, paint.glow)
		box(holder, 0.5, 0.79, 0.3, 0.06, paint.main)
	end
end

local function core(holder: Frame, paint: Paint, body: string)
	local thin = 2
	if body == "battery" then
		local cell = box(holder, 0.5, 0.54, 0.34, 0.56, paint.main)
		round(cell, 0.15)
		box(holder, 0.5, 0.22, 0.14, 0.07, paint.accent)
		box(holder, 0.5, 0.62, 0.24, 0.24, paint.glow, { BackgroundTransparency = 0.2 })
	elseif body == "crystal" then
		box(holder, 0.28, 0.62, 0.16, 0.16, paint.accent, { Rotation = 45 })
		box(holder, 0.72, 0.62, 0.16, 0.16, paint.accent, { Rotation = 45 })
		box(holder, 0.5, 0.5, 0.36, 0.36, paint.main, { Rotation = 45 })
		box(holder, 0.5, 0.5, 0.18, 0.18, paint.glow, { Rotation = 45 })
	elseif body == "atom" then
		for _, angle in ipairs({ 0, 60, -60 }) do
			orbit(holder, 0.5, 0.5, 0.82, 0.3, angle, paint.accent, thin)
		end
		circle(holder, 0.5, 0.5, 0.28, paint.main)
		circle(holder, 0.5, 0.5, 0.12, paint.glow)
	else -- orb
		ring(holder, 0.5, 0.5, 0.68, paint.accent, 3)
		circle(holder, 0.5, 0.5, 0.46, paint.main)
		circle(holder, 0.5, 0.5, 0.2, paint.glow)
	end
end

local BODY: { [string]: (Frame, Paint, string) -> () } = {
	engine = engine,
	heat = heat,
	fuel = fuel,
	sail = sail,
	nav = nav,
	core = core,
}

-- 아이콘 하나 (정사각형, 한 변 px). silhouette 이면 아직 못 모은 부품 (도감): 어두운 그림자와 '?'
-- GPT 그림 (Nick 11-28): 같은 칸에 금속·칠·빛 세 층을 겹쳐 ImageColor3 로 칠함. 그림 Id 가 없으면 false (Frame 으로 그림)
local LAYERS = { "Metal", "Paint", "Glow" }

function imageArt(art: Frame, variant: Catalog.Variant, silhouette: boolean): boolean
	local image = Catalog.IconImages[variant.Type]
	if image == nil or image == "" then
		return false
	end
	local look = variant.Look
	local tile = Catalog.IconTile
	local shape = math.clamp(math.floor(look.Shape), 1, Catalog.Shapes)
	local colors = {
		Color3.new(1, 1, 1):Lerp(look.Accent, 0.25), -- 금속: 장식 색을 조금
		look.Main, -- 칠
		look.Glow:Lerp(Color3.new(1, 1, 1), 0.15), -- 빛: 조금 더 밝게
	}
	for layer = 1, if silhouette then 1 else 3 do
		local n = (shape - 1) * 3 + (layer - 1)
		Ui.make("ImageLabel", {
			Name = LAYERS[layer],
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = image,
			ImageRectOffset = Vector2.new((n % Catalog.IconGrid) * tile, math.floor(n / Catalog.IconGrid) * tile),
			ImageRectSize = Vector2.new(tile, tile),
			ImageColor3 = if silhouette then SILHOUETTE else colors[layer],
			ZIndex = 1 + layer, -- 빛 무늬(1) 위에 금속 → 칠 → 빛
			Parent = art,
		})
	end
	return true
end

function PartIcon.make(parent: Instance, variant: Catalog.Variant, px: number, silhouette: boolean?): Frame
	local rarityColor = Catalog.RarityColors[math.clamp(variant.Rarity, 1, #Catalog.RarityColors)]
	local bright = variant.Rarity >= 3 and not silhouette -- 영웅·전설은 바탕도 레어도 빛으로
	local holder = Ui.frame(parent, "PartIcon", {
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = if silhouette
			then SILHOUETTE_BACK
			else rarityColor:Lerp(Color3.new(0, 0, 0), if bright then 0.55 else 0.78),
		BackgroundTransparency = 0,
	})
	holder:SetAttribute("Variant", variant.Id)
	holder:SetAttribute("Silhouette", silhouette == true)
	Ui.corner(holder, math.max(6, math.floor(px / 7)))
	Ui.stroke(holder, if silhouette then SILHOUETTE else rarityColor, math.max(2, math.floor(px / 30)), 0)
	if bright then
		-- 위는 밝고 아래로 갈수록 어둡게 (UIGradient 는 바탕색에 곱해짐)
		Ui.make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(90, 90, 90)),
			Parent = holder,
		})
	end
	local art = Ui.frame(holder, "Art", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
	})
	local look = variant.Look
	local paint: Paint = if silhouette
		then { main = SILHOUETTE, accent = SILHOUETTE, glow = SILHOUETTE, dark = true }
		else { main = look.Main, accent = look.Accent, glow = look.Glow, dark = false }
	aura(art, look.Aura, paint, px)
	if not imageArt(art, variant, silhouette == true) then
		local draw = BODY[variant.Type]
		if draw then
			draw(art, paint, look.Body)
		end
	end
	if silhouette then
		Ui.label(holder, "Unknown", "?", math.floor(px * 0.42), {
			TextColor3 = Color3.fromRGB(150, 160, 186),
			TextStrokeTransparency = 0.4,
			ZIndex = 2,
		})
	end
	return holder
end

return PartIcon
