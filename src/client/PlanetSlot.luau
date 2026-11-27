-- 다음 행성 슬롯: 판이 끝나 정산 화면을 얼마간 보여 준 뒤, 다음 판 행성을 뽑는 슬롯이 돌아가다가
-- 서버가 미리 뽑아 둔 행성에서 멈춥니다. 칸마다 행성 썸네일·이름·확률을 보여 주고, 아래에 후보 전체의 확률표를 둡니다.
--
--  · 서버(Round.luau)는 정산을 시작할 때 NextPlanet(뽑힌 행성), SlotFrom(뺀 행성 = 지금 행성), SlotSeed(칸 순서),
--    SlotStartAt(돌기 시작) · SlotStopAt(멈춤) 을 RoundState 속성으로 알리고, 판이 끝나면 그 행성으로 바꿉니다.
--  · 모든 화면이 서버 시각으로 같은 칸을 보여 주므로, 도중에 들어온 사람도 같은 자리를 봅니다.
--  · 확률은 Planets.odds (서버의 뽑기와 같은 표). 확률이 Config.PlanetSlot.RarePercent % 이하면 '희귀'.
--  · 썸네일은 Planets.luau 의 Thumb (Roblox 이미지). 아직 비어 있으면 행성 색으로 그린 둥근 그림을 씁니다.
--  · 슬롯 판은 정산 판(Hud)과 같은 자리에 조금 더 크게, 그 위 층에 그려 정산 판을 가립니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Planets = require(Shared:WaitForChild("Planets"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local PlanetSlot = {}

local C = Ui.Colors
local S = Config.PlanetSlot

-- ------------------------------------------------------------ 배치 (기준 1280x720 단위)
local PANEL_W = 760 -- 정산 판(700x496, 같은 가운데)을 다 덮는 크기
local PANEL_H = 520
local REEL_X = 30
local REEL_Y = 80
local REEL_W = 700
local REEL_H = 232
local CELL_W = 176 -- 칸 하나의 너비 (창에 약 4칸)
local CELL_PAD = 8
local THUMB = 128
local START_CELL = 2 -- 돌기 전 가운데 칸 (왼쪽에도 두 칸이 보이게)
local TAIL_CELLS = 3 -- 멈춘 칸 오른쪽에 더 만들어 두는 칸
local POP_SECONDS = 0.18
local TICK_GAP = 0.045 -- 칸이 지나갈 때 나는 소리의 최소 간격(초)

-- 썸네일이 없을 때 그리는 무늬 (원 안의 비율 자리: x, y, 지름)
local SPOTS = {
	{ 0.3, 0.6, 0.28 },
	{ 0.62, 0.32, 0.2 },
	{ 0.66, 0.7, 0.16 },
	{ 0.42, 0.24, 0.1 },
}

-- ------------------------------------------------------------ 상태
local holder: Frame
local panel: Frame
local panelScale: UIScale
local panelStroke: UIStroke
local subLabel: TextLabel
local reel: Frame
local strip: Frame
local marker: Frame
local markerStroke: UIStroke
local resultLabel: TextLabel
local chipsRow: Frame
local footLabel: TextLabel

type Slot = {
	key: string,
	startAt: number,
	stopAt: number,
	target: string,
	from: string,
	order: { Planets.Odds },
	targetCell: number,
	cells: { Frame },
	chips: { [string]: Frame },
	shownAt: number,
	landed: boolean,
	lastCell: number,
	lastTick: number,
}

local slot: Slot? = nil

-- ------------------------------------------------------------ 그리기 도구
local function round(frame: GuiObject)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
end

-- 0.154 -> "15.4%", 0.25 -> "25%"
function PlanetSlot.percentText(chance: number): string
	local p = chance * 100
	local rounded = math.floor(p + 0.5)
	if math.abs(p - rounded) < 0.05 then
		return string.format("%d%%", rounded)
	end
	return string.format("%.1f%%", p)
end

function PlanetSlot.isRare(chance: number): boolean
	return chance * 100 <= S.RarePercent + 1e-9
end

-- 행성 썸네일 (size x size). 이미지가 있으면 그 이미지, 없으면 행성 색으로 그린 둥근 행성.
local function drawPlanet(parent: Instance, planet: Planets.Planet, size: number, props: { [string]: any }?): Frame
	local box = Ui.frame(parent, "Thumb", { Size = UDim2.fromOffset(size, size) })
	if props then
		for key, value in pairs(props) do
			(box :: any)[key] = value
		end
	end
	if planet.Thumb ~= "" then
		Ui.make("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Image = planet.Thumb,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			Parent = box,
		})
		return box
	end
	-- 바다가 많은 행성은 바다 바탕에 섬, 아니면 땅 바탕에 호수(용암 행성은 용암 호수)
	local seaWorld = planet.SeaShare >= 0.5
	local ball = Ui.frame(box, "Ball", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = if seaWorld then planet.Sea else planet.Ground[2],
		BackgroundTransparency = 0,
	})
	round(ball)
	Ui.make("UIStroke", {
		Color = planet.Crack,
		Thickness = math.max(2, math.floor(size * 0.03 + 0.5)),
		Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ball,
	})
	local spotColor = if seaWorld then planet.Ground[3] else planet.Sea
	for i, spot in ipairs(SPOTS) do
		local color = if i == #SPOTS then planet.Peak else spotColor
		local dot = Ui.frame(ball, "Spot", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromScale(spot[3], spot[3]),
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			ZIndex = 1,
		})
		round(dot)
	end
	-- 오른쪽 아래가 어두운 그늘과 왼쪽 위의 빛
	local shade = Ui.frame(ball, "Shade", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0,
		ZIndex = 2,
	})
	round(shade)
	Ui.make("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Parent = shade,
	})
	local shine = Ui.frame(ball, "Shine", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.32, 0.28),
		Size = UDim2.fromScale(0.24, 0.24),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.72,
		ZIndex = 3,
	})
	round(shine)
	return box
end

PlanetSlot.drawPlanet = drawPlanet

-- ------------------------------------------------------------ 칸 순서
-- 후보(목록 순서)를 씨앗으로 섞은 순서. 모든 화면에서 같은 순서가 나옵니다.
local function shuffled(list: { Planets.Odds }, seed: number): { Planets.Odds }
	local out = table.clone(list)
	local rng = Random.new(seed)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- 칸 순서와 멈출 칸: 순서를 계속 되풀이해 늘어놓고, START_CELL 에서 Cycles 바퀴 돈 뒤 처음 나오는 뽑힌 행성 칸에서 멈춤.
-- (뽑힌 행성이 후보에 없으면(디버그로 그사이 행성이 바뀜) 순서 끝에 확률 0 으로 넣음)
function PlanetSlot.layout(from: string, target: string, seed: number): ({ Planets.Odds }, number)
	local order = shuffled(Planets.odds(from), seed)
	local found = false
	for _, entry in ipairs(order) do
		if entry.Planet.Id == target then
			found = true
		end
	end
	if not found then
		table.insert(order, { Planet = Planets.get(target), Chance = 0 })
	end
	local n = #order
	local cell = START_CELL + S.Cycles * n
	while order[cell % n + 1].Planet.Id ~= target do
		cell += 1
	end
	return order, cell
end

-- 칸 i(0부터)에 오는 후보
local function entryAt(order: { Planets.Odds }, i: number): Planets.Odds
	return order[i % #order + 1]
end

-- 시간 비율 u(0~1)일 때 가운데에 오는 칸 위치 (소수). 처음에 빠르고 끝에 천천히 멈춤.
function PlanetSlot.position(u: number, targetCell: number): number
	local t = math.clamp(u, 0, 1)
	local ease = 1 - (1 - t) ^ 3
	return START_CELL + (targetCell - START_CELL) * ease
end

-- ------------------------------------------------------------ 슬롯 판 만들기
local function makeCell(i: number, entry: Planets.Odds): Frame
	local planet = entry.Planet
	local cell = Ui.frame(strip, "Cell" .. tostring(i), {
		Position = UDim2.fromOffset(i * CELL_W + CELL_PAD, CELL_PAD),
		Size = UDim2.fromOffset(CELL_W - CELL_PAD * 2, REEL_H - CELL_PAD * 2),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.1,
	})
	cell:SetAttribute("PlanetId", planet.Id)
	Ui.corner(cell, 10)
	Ui.stroke(cell, planet.Crack, 2, 0.55)
	local inner = CELL_W - CELL_PAD * 2
	drawPlanet(cell, planet, THUMB, {
		Position = UDim2.fromOffset(math.floor((inner - THUMB) / 2), 6),
	})
	Ui.label(cell, "Name", planet.Name, 21, {
		Position = UDim2.fromOffset(0, THUMB + 8),
		Size = UDim2.new(1, 0, 0, 28),
	})
	Ui.label(cell, "Chance", PlanetSlot.percentText(entry.Chance), 22, {
		Position = UDim2.fromOffset(0, THUMB + 38),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = planet.Crack,
	})
	if entry.Chance > 0 and PlanetSlot.isRare(entry.Chance) then
		local badge = Ui.label(cell, "Rare", "희귀", 15, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(46, 22),
			BackgroundColor3 = C.Yellow,
			BackgroundTransparency = 0,
			TextColor3 = C.Black,
			TextStrokeTransparency = 1,
			ZIndex = 4,
		})
		Ui.corner(badge, 6)
	end
	return cell
end

local function makeChip(index: number, count: number, entry: Planets.Odds): Frame
	local gap = 5
	local width = math.floor((REEL_W - gap * (count - 1)) / count)
	local planet = entry.Planet
	local chip = Ui.frame(chipsRow, "Chip_" .. planet.Id, {
		Position = UDim2.fromOffset((index - 1) * (width + gap), 0),
		Size = UDim2.fromOffset(width, 60),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.15,
	})
	Ui.corner(chip, 8)
	local stroke = Ui.stroke(chip, C.Yellow, 3, 1)
	stroke.Name = "Pick"
	drawPlanet(chip, planet, 44, { Position = UDim2.fromOffset(6, 8) })
	Ui.label(chip, "Name", planet.Name, 15, {
		Position = UDim2.fromOffset(54, 7),
		Size = UDim2.new(1, -58, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Dim,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(chip, "Chance", PlanetSlot.percentText(entry.Chance), 19, {
		Position = UDim2.fromOffset(54, 30),
		Size = UDim2.new(1, -58, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = planet.Crack,
	})
	return chip
end

local function clearSlot()
	strip:ClearAllChildren()
	chipsRow:ClearAllChildren()
	slot = nil
end

local function buildSlot(key: string, startAt: number, stopAt: number, target: string, from: string, seed: number)
	clearSlot()
	local order, targetCell = PlanetSlot.layout(from, target, seed)
	local cells: { Frame } = {}
	for i = 0, targetCell + TAIL_CELLS do
		table.insert(cells, makeCell(i, entryAt(order, i)))
	end
	-- 확률표는 목록 순서(섞지 않음), 뽑힌 행성이 후보에 없었으면 끝에
	local odds = Planets.odds(from)
	local listed: { Planets.Odds } = {}
	for _, entry in ipairs(odds) do
		table.insert(listed, entry)
	end
	if #listed < #order then
		table.insert(listed, order[#order])
	end
	local chips: { [string]: Frame } = {}
	for index, entry in ipairs(listed) do
		chips[entry.Planet.Id] = makeChip(index, #listed, entry)
	end
	local fromName = if Planets.has(from) then Planets.get(from).Name else ""
	subLabel.Text = if fromName ~= ""
		then string.format("지금 행성(%s)은 빼고, 나머지에서 확률대로 하나가 나옵니다", fromName)
		else "확률대로 하나가 나옵니다"
	resultLabel.Text = "두근두근..."
	resultLabel.TextColor3 = C.Dim
	panelStroke.Color = C.Line
	markerStroke.Color = C.Yellow
	slot = {
		key = key,
		startAt = startAt,
		stopAt = stopAt,
		target = target,
		from = from,
		order = order,
		targetCell = targetCell,
		cells = cells,
		chips = chips,
		shownAt = State.now(),
		landed = false,
		lastCell = START_CELL,
		lastTick = 0,
	}
end

local function land(current: Slot, quiet: boolean)
	current.landed = true
	local planet = Planets.get(current.target)
	local chance = 0
	for _, entry in ipairs(current.order) do
		if entry.Planet.Id == current.target then
			chance = entry.Chance
		end
	end
	local rare = chance > 0 and PlanetSlot.isRare(chance)
	resultLabel.Text = string.format("%s%s! (%s)", if rare then "희귀 " else "", planet.Name, PlanetSlot.percentText(chance))
	resultLabel.TextColor3 = if rare then C.Yellow else planet.Crack
	panelStroke.Color = planet.Crack
	markerStroke.Color = if rare then C.Yellow else planet.Crack
	local chip = current.chips[current.target]
	if chip then
		local pick = chip:FindFirstChild("Pick")
		if pick and pick:IsA("UIStroke") then
			pick.Transparency = 0
		end
	end
	if not quiet then
		if rare then
			State.emit("Sound", "Combo")
		end
		State.emit("Sound", "MissionSuccess")
	end
end

-- ------------------------------------------------------------ 매 프레임
function PlanetSlot.update(_dt: number)
	local startAt = State.number("SlotStartAt")
	local stopAt = State.number("SlotStopAt")
	local target = State.text("NextPlanet")
	local now = State.now()
	local active = State.phase() == "Results"
		and startAt > 0
		and stopAt > startAt
		and target ~= ""
		and now >= startAt - S.Intro
	if not active then
		if holder.Visible then
			holder.Visible = false
		end
		if slot ~= nil then
			clearSlot()
		end
		return
	end

	local seed = State.number("SlotSeed")
	local from = State.text("SlotFrom")
	local key = string.format("%s|%s|%d|%.3f", target, from, seed, startAt)
	if slot == nil or slot.key ~= key then
		buildSlot(key, startAt, stopAt, target, from, seed)
	end
	local current = slot :: Slot
	holder.Visible = true

	-- 처음 나올 때 살짝 커지며 나타남
	local shown = now - current.shownAt
	panelScale.Scale = 0.92 + 0.08 * math.clamp(shown / POP_SECONDS, 0, 1)

	local u = (now - startAt) / (stopAt - startAt)
	local position = PlanetSlot.position(u, current.targetCell)
	strip.Position = UDim2.fromOffset(math.floor(REEL_W / 2 - (position * CELL_W + CELL_W / 2) + 0.5), 0)

	-- 칸이 가운데를 지날 때마다 딸깍
	local centerCell = math.floor(position + 0.5)
	if centerCell ~= current.lastCell and u < 1 then
		current.lastCell = centerCell
		local clock = os.clock()
		if clock - current.lastTick >= TICK_GAP then
			current.lastTick = clock
			State.emit("Sound", "Press")
		end
	end

	if u >= 1 and not current.landed then
		-- 멈춘 뒤에 처음 보는 사람(도중 입장)에게는 소리를 내지 않음
		land(current, current.shownAt > stopAt + 0.3)
	end

	-- 멈춘 칸 테두리가 천천히 빛남
	if current.landed then
		markerStroke.Transparency = 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 6))
	else
		markerStroke.Transparency = 0
	end

	footLabel.Text = string.format("다음 판까지 %s · 판이 끝나면 이 행성에서 출발합니다", Fmt.clock(State.phaseLeft()))
end

function PlanetSlot.init()
	local _, root = Ui.screen("RoflyPlanetSlot", 13)
	holder = Ui.frame(root, "PlanetSlot", {
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	})
	panel = Ui.panel(holder, "SlotPanel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundTransparency = 0,
	})
	panelStroke = Ui.stroke(panel, C.Line, 3, 0)
	panelScale = Ui.make("UIScale", { Scale = 1, Parent = panel })

	Ui.label(panel, "Head", "다음 행성 뽑기", 28, {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = C.Yellow,
	})
	subLabel = Ui.label(panel, "Sub", "", 17, {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = C.Dim,
	})

	reel = Ui.frame(panel, "Reel", {
		Position = UDim2.fromOffset(REEL_X, REEL_Y),
		Size = UDim2.fromOffset(REEL_W, REEL_H),
		BackgroundColor3 = Color3.fromRGB(8, 10, 16),
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	})
	Ui.corner(reel, 10)
	strip = Ui.frame(reel, "Strip", {
		Size = UDim2.fromOffset(CELL_W, REEL_H),
		ZIndex = 1,
	})
	-- 양 끝을 어둡게 (가운데 칸에 눈이 가게)
	for _, side in ipairs({ "Left", "Right" }) do
		local shade = Ui.frame(reel, "Shade" .. side, {
			AnchorPoint = Vector2.new(if side == "Left" then 0 else 1, 0),
			Position = UDim2.fromScale(if side == "Left" then 0 else 1, 0),
			Size = UDim2.new(0, 150, 1, 0),
			BackgroundColor3 = Color3.fromRGB(8, 10, 16),
			BackgroundTransparency = 0,
			ZIndex = 3,
		})
		Ui.make("UIGradient", {
			Rotation = if side == "Left" then 0 else 180,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = shade,
		})
	end
	marker = Ui.frame(reel, "Marker", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CELL_W - 4, REEL_H - 6),
		ZIndex = 5,
	})
	Ui.corner(marker, 12)
	markerStroke = Ui.stroke(marker, C.Yellow, 4, 0)

	resultLabel = Ui.label(panel, "Result", "", 34, {
		Position = UDim2.fromOffset(0, REEL_Y + REEL_H + 10),
		Size = UDim2.new(1, 0, 0, 44),
	})
	Ui.label(panel, "OddsTitle", "확률", 16, {
		Position = UDim2.fromOffset(REEL_X, REEL_Y + REEL_H + 58),
		Size = UDim2.fromOffset(200, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Dim,
	})
	chipsRow = Ui.frame(panel, "Odds", {
		Position = UDim2.fromOffset(REEL_X, REEL_Y + REEL_H + 82),
		Size = UDim2.fromOffset(REEL_W, 60),
	})
	footLabel = Ui.label(panel, "Next", "", 17, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = C.Dim,
	})

	State.on("Phase", function(phase: string)
		if phase ~= "Results" then
			holder.Visible = false
			if slot ~= nil then
				clearSlot()
			end
		end
	end)
end

-- 검사용
PlanetSlot._internal = {
	cellWidth = CELL_W,
	reelWidth = REEL_W,
	startCell = START_CELL,
	current = function(): any
		return slot
	end,
}

return PlanetSlot
