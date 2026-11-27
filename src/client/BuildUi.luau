-- 부품 조립 화면: 조립(빌드) 단계에 승무원에게 따로 뜨는 화면.
-- 부품 종류마다 그리드가 있고(기획서 '부품 그리드' 그림처럼 발사·비행·버튼 입력 3열 × 2줄), 같은 색 그리드의
-- 열린 빈 칸(+)을 눌러 내 부품을 종류마다 1개씩 꽂습니다. 다른 승무원(봇 포함)이 꽂는 것도 바로 보이고,
-- 부품이 꽂힐수록 예상 거리가 오릅니다. 이미 꽂은 종류는 다른 빈 칸을 누르면 그 칸으로 옮깁니다.
-- 화면은 '닫기' / '부품 조립 열기' 버튼이나 B 키(게임패드 Y)로 껐다 켤 수 있고, 조립이 시작될 때마다 다시 열립니다.
-- 그리드는 서버가 RoundState.Grid 폴더의 속성으로 알려 줍니다 (서버 Assembly.luau 참고).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Net = require(Shared:WaitForChild("Net"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local BuildUi = {}

local C = Ui.Colors
local stateFolder: Instance = ReplicatedStorage:WaitForChild(Net.StateName)

-- 부품 종류별 색과 짧은 설명 (기획서 부품 그리드 그림과 같은 색)
local TYPE_STYLE: { [string]: { Color: Color3, Desc: string } } = {
	engine = { Color = Color3.fromRGB(255, 128, 72), Desc = "발사 속도" },
	heat = { Color = Color3.fromRGB(172, 224, 90), Desc = "최대 출력 시간" },
	fuel = { Color = Color3.fromRGB(70, 160, 255), Desc = "추진 시간" },
	sail = { Color = Color3.fromRGB(48, 214, 180), Desc = "연료 뒤 추진" },
	nav = { Color = Color3.fromRGB(226, 230, 242), Desc = "미션 성공 가속" },
	core = { Color = Color3.fromRGB(255, 206, 84), Desc = "콤보 배율" },
}
BuildUi.TypeStyle = TYPE_STYLE -- 선실 부품 장착판(PartsBoard)도 같은 색을 씀
local STARS = { "★", "★★", "★★★", "★★★★" } -- 레어도 (일반·희귀·영웅·전설)
-- 내 부품 표시 색 (Nick 11-27: 현황판에서 내 부품은 구별되게). 부품 종류 색 6개 어디에도 없는 분홍으로,
-- 조립 화면·장착판·'내 부품' 패널이 같이 씀
local MINE_COLOR = Color3.fromRGB(255, 72, 196)
local TAKEN_FADE = 0.4 -- 남이 꽂은 칸은 이만큼 흐리게 (내 칸이 더 눈에 띄게)
BuildUi.Stars = STARS
BuildUi.MineColor = MINE_COLOR
BuildUi.TakenFade = TAKEN_FADE
local CELL_CLOSED = Color3.fromRGB(20, 24, 36)
local CELL_OPEN = Color3.fromRGB(32, 38, 56)
local INK = Color3.fromRGB(18, 22, 32) -- 꽂힌 칸(밝은 색) 위의 글자
local TOGGLE_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.B] = true, [Enum.KeyCode.ButtonY] = true }
local PENDING_TIMEOUT = 2 -- 누른 칸이 이 시간(초) 안에 서버에서 내 칸이 되지 않으면 다시 누르게 안내

-- 배치 (기준 1280x720 단위). 위쪽 안내(조립 남은 시간, 0~78) 바로 아래부터 화면 아래 가까이까지 씀
local PANEL_WIDTH = 940 -- 오른쪽 위 시점·디버그 버튼(오른쪽 끝에서 166)과 겹치지 않게
local PANEL_TOP = 82
local PANEL_BOTTOM = 10
local HEADER_HEIGHT = 56 -- 버튼 높이 44 (휴대폰에서도 누르기 쉽게)
local GAUGE_HEIGHT = 5
local NOTICE_TOP = HEADER_HEIGHT + GAUGE_HEIGHT + 2
local NOTICE_HEIGHT = 22
local CARDS_TOP = NOTICE_TOP + NOTICE_HEIGHT + 3
local CARD_GAP = 10
local CARD_PAD = 8
local CARD_TITLE = 26
local CELL_GAP = 4

type Cell = {
	button: TextButton,
	stroke: UIStroke,
	main: TextLabel?,
	sub: TextLabel?,
	who: TextLabel?,
	look: string, -- "closed" | "open" | "pending" | "mine" | "taken"
	value: number,
}
type Card = {
	frame: Frame,
	stroke: UIStroke,
	count: TextLabel,
	check: TextLabel,
	cells: { [number]: Cell },
}

local root: Frame
local panel: Frame
local mineLabel: TextLabel
local statusLabel: TextLabel
local autoButton: TextButton
local closeButton: TextButton
local gaugeFill: Frame
local noticeLabel: TextLabel
local expectLabel: TextLabel
local cardsFrame: Frame
local openButton: TextButton

local cards: { [string]: Card } = {}
local bound: Instance? = nil -- 지금 그려 둔 Grid 폴더
local boundTypes = 0 -- 그때 찾은 종류 폴더 수 (덜 왔으면 다시 그림)
local connections: { RBXScriptConnection } = {}
local dirty = false
local open = true -- 화면을 켜 둠 (조립이 시작될 때마다 다시 켬)
local pending: { [string]: { cell: number, at: number } } = {} -- 종류 -> 내가 누르고 서버를 기다리는 칸
local myCount = 0 -- 내가 꽂은 종류 수 (서버 기준)
local prevCount = 0 -- 지난번 refresh 때의 myCount (다 꽂은 순간을 알려고)
local statusUntil = 0
local warned = false -- 이번 조립에 선장에게 곧 카운트다운이라고 알렸는지
local lastExpected = -1

-- ------------------------------------------------------------ 작은 도구
local function say(text: string, color: Color3?, seconds: number?)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or C.Text
	statusUntil = os.clock() + (seconds or 3)
end

local function nameOf(seat: number): string
	local folder = bound
	local name = folder and folder:GetAttribute("Name" .. tostring(seat))
	return if type(name) == "string" then name else "다른 승무원"
end

local function gridNumber(name: string, default: number): number
	local folder = bound
	local value = folder and folder:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- 그 좌석 승무원의 그 종류 부품 레어도·레벨 ('각자 부품'이면 사람마다 다름. 없으면 이번 판 장비)
local function partOf(typeId: string, seat: number): (number, number)
	local folder = bound
	local typeFolder = folder and folder:FindFirstChild(typeId)
	local rarity = typeFolder and typeFolder:GetAttribute("Ra" .. tostring(seat))
	local level = typeFolder and typeFolder:GetAttribute("Lv" .. tostring(seat))
	return if type(rarity) == "number" then rarity else gridNumber("Rarity", 1),
		if type(level) == "number" then level else gridNumber("Level", 1)
end

-- 칸에 쓰는 레벨 (만렙은 MAX)
local function levelText(level: number): string
	if level >= Config.Progress.MaxLevel then
		return "MAX"
	end
	return "Lv" .. tostring(math.floor(level))
end
BuildUi.levelText = levelText

local function setOpen(value: boolean)
	if open ~= value then
		open = value
		State.emit("Sound", "Press")
	end
end

-- ------------------------------------------------------------ 칸 그리기
local function paint(cell: Cell, look: string, value: number, typeId: string)
	if cell.look == look and cell.value == value then
		return
	end
	local before = cell.look
	cell.look = look
	cell.value = value
	local color = (TYPE_STYLE[typeId] or { Color = C.Cyan }).Color
	local button = cell.button
	local stroke = cell.stroke
	local main, sub, who = cell.main, cell.sub, cell.who
	local mainText, subText, whoText = "", "", ""
	button.Text = ""
	if look == "closed" then
		button.BackgroundColor3 = CELL_CLOSED
		button.BackgroundTransparency = 0.3
		stroke.Enabled = false
	elseif look == "open" then
		button.BackgroundColor3 = CELL_OPEN
		button.BackgroundTransparency = 0
		stroke.Enabled = true
		stroke.Color = color
		stroke.Thickness = 1.5
		stroke.Transparency = 0.25
		if main then
			mainText = "+"
		else
			button.Text = "+"
			button.TextColor3 = color
		end
	elseif look == "pending" then
		button.BackgroundColor3 = color
		button.BackgroundTransparency = 0.55
		stroke.Enabled = true
		stroke.Color = C.White
		stroke.Thickness = 2
		stroke.Transparency = 0
		mainText = "…"
	else
		-- 꽂힌 칸: 종류 색, 그 사람 부품의 레벨과 레어도(별), 꽂은 사람.
		-- 내 칸은 분홍 굵은 테두리와 분홍 '나' 딱지, 남의 칸은 조금 흐리게
		local mine = look == "mine"
		local rarity, level = partOf(typeId, value)
		button.BackgroundColor3 = color
		button.BackgroundTransparency = if mine then 0 else TAKEN_FADE
		stroke.Enabled = mine
		stroke.Color = MINE_COLOR
		stroke.Thickness = 4
		stroke.Transparency = 0
		mainText = levelText(level)
		subText = STARS[math.clamp(math.floor(rarity), 1, #STARS)]
		whoText = if mine then "나" else nameOf(value)
		if before == "open" or before == "pending" then
			-- 장착 연출: 꽂히는 순간 잠깐 밝게
			button.BackgroundColor3 = C.White
			Ui.tween(button, 0.35, { BackgroundColor3 = color })
		end
	end
	if main then
		main.Text = mainText
		main.TextColor3 = if look == "open" then color else INK
	end
	if sub then
		sub.Text = subText
	end
	if who then
		local badge = look == "mine"
		who.Text = whoText
		who.TextColor3 = if badge then C.White else INK
		who.BackgroundColor3 = MINE_COLOR
		who.BackgroundTransparency = if badge then 0 else 1
	end
end

-- 칸 하나 (TextButton). mode: "big"(이름까지) | "mid"(레벨·별) | "small"(색만)
local function makeCell(parent: Instance, typeId: string, index: number, size: number, mode: string): Cell
	local row = math.floor((index - 1) / size)
	local col = (index - 1) % size
	local button = Ui.make("TextButton", {
		Name = string.format("Cell_%s_%d", typeId, index),
		AutoButtonColor = false,
		BackgroundColor3 = CELL_CLOSED,
		BorderSizePixel = 0,
		Font = Ui.Font,
		Text = "",
		TextSize = 14,
		TextColor3 = C.Text,
		Position = UDim2.new(col / size, CELL_GAP / 2, row / size, CELL_GAP / 2),
		Size = UDim2.new(1 / size, -CELL_GAP, 1 / size, -CELL_GAP),
		Parent = parent,
	})
	Ui.corner(button, if mode == "small" then 3 else 6)
	local stroke = Ui.stroke(button, C.White, 2, 0)
	stroke.Enabled = false
	local cell: Cell = { button = button, stroke = stroke, main = nil, sub = nil, who = nil, look = "", value = -1 }
	if mode ~= "small" then
		local big = mode == "big"
		local mainSize = if big then (if size <= 3 then 24 else 19) else 15
		cell.main = Ui.label(button, "Main", "", mainSize, {
			Position = UDim2.new(0, 2, if big then 0.06 else 0.1, 0),
			Size = UDim2.new(1, -4, if big then 0.42 else 0.5, 0),
			TextColor3 = INK,
			TextStrokeTransparency = 1,
			TextScaled = true, -- "Lv9999" 처럼 길어지면 칸 안에 들게 줄임
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = mainSize, Parent = cell.main })
		cell.sub = Ui.label(button, "Sub", "", if big then 12 else 10, {
			Position = UDim2.fromScale(0, if big then 0.46 else 0.6),
			Size = UDim2.fromScale(1, if big then 0.22 else 0.3),
			TextColor3 = INK,
			TextStrokeTransparency = 1,
		})
		if big then
			cell.who = Ui.label(button, "Who", "", 11, {
				Position = UDim2.new(0, 2, 0.7, 0),
				Size = UDim2.new(1, -4, 0.26, 0),
				Font = Ui.FontLight,
				TextColor3 = INK,
				TextStrokeTransparency = 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Ui.corner(cell.who, 4)
		end
	end
	return cell
end

local onCellClick: (string, number) -> ()

-- 종류마다 카드(제목 + 그리드) 하나. 발사·비행·버튼 입력 순으로 3열, 열마다 2종류
local function makeCards(size: number)
	cardsFrame:ClearAllChildren()
	table.clear(cards)
	local mode = if size <= 4 then "big" elseif size <= 5 then "mid" else "small"
	for index, info in ipairs(Config.Parts.Types) do
		local style = TYPE_STYLE[info.Id] or { Color = C.Cyan, Desc = "" }
		local col = math.ceil(index / 2)
		local row = (index - 1) % 2 + 1
		local frame = Ui.frame(cardsFrame, "Card_" .. info.Id, {
			Position = UDim2.new((col - 1) / 3, (col - 1) * CARD_GAP / 3, (row - 1) / 2, (row - 1) * CARD_GAP / 2),
			Size = UDim2.new(1 / 3, -2 * CARD_GAP / 3, 1 / 2, -CARD_GAP / 2),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.35,
		})
		Ui.corner(frame, 10)
		-- 내 부품을 아직 안 꽂은 종류는 카드 테두리를 종류 색으로 (어디에 꽂을지 보이게)
		local stroke = Ui.stroke(frame, style.Color, 2, 0)
		local dot = Ui.frame(frame, "Dot", {
			Position = UDim2.fromOffset(CARD_PAD + 2, 8),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = style.Color,
			BackgroundTransparency = 0,
		})
		Ui.corner(dot, 3)
		Ui.label(frame, "Title", string.format('%s  <font size="13" color="#A8B0C4">%s</font>', info.Name, style.Desc), 17, {
			Position = UDim2.fromOffset(CARD_PAD + 20, 1),
			Size = UDim2.new(1, -(CARD_PAD + 20 + 74), 0, CARD_TITLE - 2),
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local check = Ui.label(frame, "Check", "", 17, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(CARD_PAD + 48), 0, 1),
			Size = UDim2.fromOffset(24, CARD_TITLE - 2),
			TextColor3 = C.Green,
		})
		local count = Ui.label(frame, "Count", "", 15, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -CARD_PAD, 0, 1),
			Size = UDim2.fromOffset(48, CARD_TITLE - 2),
			TextColor3 = C.Dim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local gridFrame = Ui.frame(frame, "Grid", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, CARD_TITLE),
			Size = UDim2.new(1, -2 * CARD_PAD, 1, -(CARD_TITLE + CARD_PAD)),
		})
		Ui.make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = gridFrame })
		local card: Card = { frame = frame, stroke = stroke, count = count, check = check, cells = {} }
		for cellIndex = 1, size * size do
			local cell = makeCell(gridFrame, info.Id, cellIndex, size, mode)
			card.cells[cellIndex] = cell
			local typeId = info.Id
			cell.button.Activated:Connect(function()
				onCellClick(typeId, cellIndex)
			end)
		end
		cards[info.Id] = card
	end
end

-- 서버가 알려 준 그리드를 다시 읽어 칸·숫자를 맞춤
local function refresh()
	dirty = false
	local folder = bound
	if not folder then
		return
	end
	local mySeat = State.myNumber("Seat")
	local placedAll, openAll = 0, 0
	local placedNow = false -- 이번에 누른 칸이 내 칸이 됨 (꽂는 소리를 냄)
	myCount = 0
	for _, info in ipairs(Config.Parts.Types) do
		local card = cards[info.Id]
		local typeFolder = folder:FindFirstChild(info.Id)
		if card and typeFolder then
			local attrs = typeFolder:GetAttributes()
			local placed, opened = 0, 0
			local myCell: number? = nil
			local waiting = pending[info.Id]
			for index, cell in pairs(card.cells) do
				local value = attrs["C" .. tostring(index)]
				local look = "closed"
				local seat = 0
				if type(value) == "number" then
					opened += 1
					seat = value
					if value == 0 then
						look = if waiting and waiting.cell == index then "pending" else "open"
					else
						placed += 1
						if value == mySeat and mySeat > 0 then
							look = "mine"
							myCell = index
						else
							look = "taken"
						end
					end
				end
				paint(cell, look, seat, info.Id)
			end
			-- 누르고 기다리던 칸: 내 칸이 됐으면 끝, 다른 사람이 먼저 꽂았거나 오래 걸리면 다시 누르게 안내
			if waiting then
				if myCell == waiting.cell then
					pending[info.Id] = nil
					say(info.Name .. " 꽂음!", C.Green, 2)
					State.emit("Sound", "PartPlace")
					placedNow = true
				elseif attrs["C" .. tostring(waiting.cell)] ~= 0 then
					pending[info.Id] = nil
					say("다른 승무원이 먼저 꽂았습니다. 다른 빈 칸(+)을 누르세요", C.Orange)
					State.emit("Sound", "Wrong")
				elseif os.clock() - waiting.at > PENDING_TIMEOUT then
					pending[info.Id] = nil
					say("꽂지 못했습니다. 다시 눌러 보세요", C.Orange)
				end
			end
			if myCell then
				myCount += 1
			end
			card.count.Text = string.format("%d/%d", placed, opened)
			card.check.Text = if myCell then "✓" else ""
			card.stroke.Enabled = myCell == nil
			placedAll += placed
			openAll += opened
		end
	end
	-- 방금 다 꽂음 (직접 또는 자동 꽂기): 바로 알림
	local total = #Config.Parts.Types
	if myCount >= total and prevCount < total then
		say("모두 꽂았습니다! 다른 빈 칸을 누르면 옮길 수 있어요", C.Green, 3)
		if not placedNow then
			State.emit("Sound", "PartPlace")
		end
	end
	prevCount = myCount
	gaugeFill.Size = UDim2.fromScale(if openAll > 0 then placedAll / openAll else 0, 1)
	expectLabel.Text = string.format("로켓 조립 %d/%d · 예상 거리 %s", placedAll, openAll, Fmt.km(State.number("ExpectedKm")))
end

function onCellClick(typeId: string, index: number)
	local folder = bound
	if not folder or State.phase() ~= "Build" or State.role() ~= "Crew" then
		return
	end
	local typeFolder = folder:FindFirstChild(typeId)
	local value = typeFolder and typeFolder:GetAttribute("C" .. tostring(index))
	if type(value) ~= "number" then
		say("닫힌 칸입니다. 테두리가 있는 빈 칸(+)에 꽂으세요", C.Orange)
		State.emit("Sound", "Wrong")
		return
	end
	if value ~= 0 then
		if value == State.myNumber("Seat") then
			say("이미 내 부품이 꽂힌 칸입니다", C.Dim)
		else
			say(nameOf(value) .. " 님이 꽂은 칸입니다. 다른 빈 칸(+)을 누르세요", C.Orange)
			State.emit("Sound", "Wrong")
		end
		return
	end
	pending[typeId] = { cell = index, at = os.clock() }
	dirty = true
	State.emit("Sound", "Press")
	Net.event("PlacePart"):FireServer(typeId, index)
end

-- 새 Grid 폴더(새 판)를 그림. 아직 덜 왔으면 다음 프레임에 다시.
local function bind(folder: Instance?)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(pending)
	cardsFrame:ClearAllChildren()
	table.clear(cards)
	bound = nil
	boundTypes = 0
	myCount = 0
	prevCount = 0
	lastExpected = -1
	if folder == nil then
		return
	end
	local size = folder:GetAttribute("Size")
	if type(size) ~= "number" or size < 1 then
		return
	end
	bound = folder
	makeCards(size)
	local function mark(_name: string)
		dirty = true
	end
	table.insert(connections, folder.AttributeChanged:Connect(mark))
	for _, info in ipairs(Config.Parts.Types) do
		local typeFolder = folder:FindFirstChild(info.Id)
		if typeFolder then
			boundTypes += 1
			table.insert(connections, typeFolder.AttributeChanged:Connect(mark))
		end
	end
	dirty = true
end

-- ------------------------------------------------------------ 만들기
local function buildPanel()
	panel = Ui.panel(root, "BuildPanel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PANEL_TOP),
		Size = UDim2.new(0, PANEL_WIDTH, 1, -(PANEL_TOP + PANEL_BOTTOM)),
		BackgroundTransparency = 0.08,
		Visible = false,
	})
	Ui.stroke(panel, C.Line, 2, 0)

	Ui.label(panel, "Title", "부품 조립", 24, {
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.fromOffset(120, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	mineLabel = Ui.label(panel, "Mine", "", 18, {
		Position = UDim2.fromOffset(140, 9),
		Size = UDim2.fromOffset(150, 26),
		TextColor3 = C.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	statusLabel = Ui.label(panel, "Status", "", 15, {
		Position = UDim2.fromOffset(16, 35),
		Size = UDim2.new(1, -420, 0, 18),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	closeButton = Ui.button(panel, "BuildClose", "닫기 (B)", 18, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(130, 44),
		Modal = true, -- 이 버튼이 보이는 동안은 마우스가 풀려 있음
	})
	Ui.stroke(closeButton, C.Line, 2, 0)
	autoButton = Ui.button(panel, "AutoPlace", "남은 부품 자동으로 꽂기", 17, C.Purple, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 6),
		Size = UDim2.fromOffset(240, 44),
	})
	Ui.stroke(autoButton, C.White, 2, 0.5)

	-- 로켓 전체 조립 진행 (꽂힌 부품 / 열린 칸)
	local _, fill = Ui.bar(panel, "Gauge", C.Cyan, {
		Position = UDim2.fromOffset(12, HEADER_HEIGHT),
		Size = UDim2.new(1, -24, 0, GAUGE_HEIGHT),
	})
	gaugeFill = fill
	noticeLabel = Ui.label(panel, "Notice", "", 16, {
		Position = UDim2.fromOffset(16, NOTICE_TOP),
		Size = UDim2.new(0.58, -16, 0, NOTICE_HEIGHT),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	expectLabel = Ui.label(panel, "Expect", "", 16, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, NOTICE_TOP),
		Size = UDim2.new(0.42, -16, 0, NOTICE_HEIGHT),
		TextColor3 = C.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	cardsFrame = Ui.frame(panel, "Cards", {
		Position = UDim2.fromOffset(CARD_GAP, CARDS_TOP),
		Size = UDim2.new(1, -2 * CARD_GAP, 1, -(CARDS_TOP + CARD_GAP)),
	})

	-- 화면을 닫았을 때 다시 여는 버튼 (화면 아래 가운데, 탑승 버튼 자리)
	openButton = Ui.button(root, "BuildOpen", "", 20, C.PanelLight, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(400, 58),
		BackgroundTransparency = 0.1,
		Modal = true,
		Visible = false,
	})
	Ui.stroke(openButton, C.Cyan, 2, 0.2)

	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	openButton.Activated:Connect(function()
		setOpen(true)
	end)
	autoButton.Activated:Connect(function()
		if State.phase() == "Build" and State.role() == "Crew" then
			State.emit("Sound", "Press")
			say("남은 부품을 빈 칸에 꽂는 중...", C.Dim, 1.5)
			Net.event("AutoPlace"):FireServer()
		end
	end)
end

function BuildUi.init()
	local _, base = Ui.screen("RoflyBuild", 15)
	root = base
	buildPanel()

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if TOGGLE_KEYS[input.KeyCode] and not State.typing() and State.phase() == "Build" and State.role() == "Crew" then
			setOpen(not open)
		end
	end)
	State.on("Phase", function(phase: string)
		if phase == "Build" then
			-- 조립이 시작될 때마다 화면을 다시 엶
			open = true
			warned = false
			statusUntil = 0
			table.clear(pending)
		end
	end)
	-- 서버의 한 줄 안내(장착 알림, 자동 장착, 디버그 답)는 조립 화면이 가리므로 화면 안 안내 줄에도 띄움
	State.on("Announce", function(text: any)
		if type(text) == "string" and panel.Visible then
			say(text, C.Yellow, 4)
		end
	end)
end

function BuildUi.update(_dt: number)
	local folder = stateFolder:FindFirstChild("Grid")
	if folder ~= bound or (bound ~= nil and boundTypes < #Config.Parts.Types) then
		bind(folder)
	end
	local active = State.phase() == "Build" and State.role() == "Crew" and bound ~= nil
	panel.Visible = active and open
	openButton.Visible = active and not open
	if not active then
		return
	end
	if next(pending) ~= nil then
		dirty = true -- 기다리는 칸이 있으면 시간 초과를 보려고 매 프레임 확인
	end
	if dirty then
		refresh()
	end
	local total = #Config.Parts.Types
	local clock = os.clock()

	-- 내 진행과 안내
	mineLabel.Text = string.format("내 부품 %d/%d", myCount, total)
	mineLabel.TextColor3 = if myCount >= total then C.Green else C.Yellow
	autoButton.Visible = myCount < total
	if clock > statusUntil then
		if myCount >= total then
			statusLabel.Text = "모두 꽂았습니다! 다른 빈 칸을 누르면 옮길 수 있어요"
			statusLabel.TextColor3 = C.Green
		else
			statusLabel.Text = "테두리가 빛나는 그리드의 빈 칸(+)을 눌러 종류마다 1개씩 꽂으세요"
			statusLabel.TextColor3 = C.Dim
		end
	end
	openButton.Text = string.format("부품 조립 열기 (B) · 내 부품 %d/%d", myCount, total)
	openButton.TextColor3 = if myCount >= total then C.Text else C.Yellow

	-- 예상 거리가 오르면 잠깐 노랗게 (기획서 '장착 연출': 꽂으면 예상 거리 게이지가 km로 오름)
	local expected = State.number("ExpectedKm")
	if expected ~= lastExpected then
		if lastExpected >= 0 and expected > lastExpected then
			expectLabel.TextColor3 = C.Yellow
			Ui.tween(expectLabel, 0.6, { TextColor3 = C.Cyan })
		end
		lastExpected = expected
		dirty = true
	end

	-- 선장: 조립이 끝나 가면 곧 카운트다운이라고 미리 알림 (화면을 닫아 둬도 소리는 남)
	local left = State.phaseLeft()
	if State.isCaptain() then
		if left > 0 and left <= Config.Captain.BuildWarnSeconds then
			if not warned then
				warned = true
				State.emit("Sound", "LaunchAlert")
			end
			noticeLabel.Text = string.format("곧 발사 카운트다운! 선장님, 발사 버튼 준비 (%d초)", math.ceil(left))
			noticeLabel.TextColor3 = if math.floor(clock * 4) % 2 == 0 then C.Orange else C.Yellow
		else
			noticeLabel.Text = "당신이 선장! 조립이 끝나면 카운트다운 0초에 발사 버튼"
			noticeLabel.TextColor3 = C.Yellow
		end
	else
		local captain = State.text("CaptainName")
		noticeLabel.Text = if captain ~= "" then string.format("선장 %s · 조립이 끝나면 선장이 발사합니다", captain) else "조립이 끝나면 자동으로 발사됩니다"
		noticeLabel.TextColor3 = C.Dim
	end
end

return BuildUi
