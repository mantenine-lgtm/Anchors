-- 선실 부품 장착판: -X 벽의 큰 화면. 이번 판 부품 그리드 6개(종류마다 하나)에 누가 어디에 꽂았는지 보여 줍니다.
-- 조립 중에는 꽂히는 대로 바로 채워지고, 비행·정산 동안에는 장착한 그대로 남습니다.
-- 내 부품 칸은 분홍(BuildUi.MineColor) 굵은 테두리와 분홍 '나' 딱지, 남의 칸은 조금 흐리게 (Nick 11-27: 내 부품은 구별되게).
-- 비행 중 피버에 들어간 부품 칸은 금빛 테두리와 별빛이 반짝이고(FeverFx), 제목 줄에 피버 부품 수가 뜸 (Nick 11-28).
-- 그리드는 조립 화면(BuildUi)과 같은 서버 자료(RoundState.Grid 폴더의 속성, 서버 Assembly.luau)를 읽어 그립니다.
-- 화면은 클라이언트가 만들어 서버의 PartsBoard 파트 앞면에 붙입니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Net = require(Shared:WaitForChild("Net"))

local BuildUi = require(script.Parent:WaitForChild("BuildUi"))
local FeverFx = require(script.Parent:WaitForChild("FeverFx"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local PartsBoard = {}

local C = Ui.Colors
local PIXELS_PER_STUD = 30
local WIDTH = Config.World.PartsBoardWidth * PIXELS_PER_STUD
local HEIGHT = Config.World.PartsBoardHeight * PIXELS_PER_STUD
local HEADER = 84 -- 제목 줄 높이(픽셀)
local PAD = 18
local GAP = 16
local CARD_TITLE = 50
local CELL_GAP = 4
local REFRESH = 0.15 -- 칸을 다시 읽는 간격(초)
local CELL_CLOSED = Color3.fromRGB(16, 19, 30)
local CELL_OPEN = Color3.fromRGB(30, 36, 54)
local MINE = BuildUi.MineColor or Color3.fromRGB(255, 72, 196)
local TAKEN_FADE = BuildUi.TakenFade or 0.4

local stateFolder: Instance = ReplicatedStorage:WaitForChild(Net.StateName)

type Cell = { frame: Frame, stroke: UIStroke, mark: TextLabel?, look: string, fever: FeverFx.Glints? }
type Card = { count: TextLabel, cells: { [number]: Cell } }

local gui: SurfaceGui? = nil
local statusLabel: TextLabel
local idleLabel: TextLabel
local cardsFrame: Frame
local cards: { [string]: Card } = {}
local builtFolder: Instance? = nil
local builtSize = 0
local lastRefresh = 0

local function styleOf(typeId: string): Color3
	local style = BuildUi.TypeStyle and BuildUi.TypeStyle[typeId]
	return if style then style.Color else C.Cyan
end

local function gridFolder(): Instance?
	return stateFolder:FindFirstChild("Grid")
end

-- 종류마다 카드(제목 + 그리드). 조립 화면처럼 발사·비행·버튼 입력 순으로 3열, 열마다 2종류
local function makeCards(size: number)
	for _, card in pairs(cards) do
		for _, cell in pairs(card.cells) do
			if cell.fever then
				FeverFx.release(cell.fever)
			end
		end
	end
	cardsFrame:ClearAllChildren()
	table.clear(cards)
	local marks = size <= 6 -- 칸이 크면 내 칸에 '나'를 씀
	for index, info in ipairs(Config.Parts.Types) do
		local color = styleOf(info.Id)
		local col = math.ceil(index / 2)
		local row = (index - 1) % 2 + 1
		local frame = Ui.frame(cardsFrame, "Card_" .. info.Id, {
			Position = UDim2.new((col - 1) / 3, (col - 1) * GAP / 3, (row - 1) / 2, (row - 1) * GAP / 2),
			Size = UDim2.new(1 / 3, -2 * GAP / 3, 1 / 2, -GAP / 2),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.3,
		})
		Ui.corner(frame, 14)
		Ui.stroke(frame, color, 3, 0)
		Ui.label(frame, "Title", info.Name, 36, {
			Position = UDim2.fromOffset(16, 4),
			Size = UDim2.new(1, -150, 0, CARD_TITLE - 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
		})
		local count = Ui.label(frame, "Count", "", 30, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 6),
			Size = UDim2.fromOffset(130, CARD_TITLE - 8),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Dim,
		})
		local gridFrame = Ui.frame(frame, "Grid", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, CARD_TITLE),
			Size = UDim2.new(1, -24, 1, -(CARD_TITLE + 12)),
		})
		Ui.make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = gridFrame })
		local card: Card = { count = count, cells = {} }
		for cellIndex = 1, size * size do
			local r = math.floor((cellIndex - 1) / size)
			local c = (cellIndex - 1) % size
			local cellFrame = Ui.frame(gridFrame, "Cell" .. cellIndex, {
				Position = UDim2.new(c / size, CELL_GAP / 2, r / size, CELL_GAP / 2),
				Size = UDim2.new(1 / size, -CELL_GAP, 1 / size, -CELL_GAP),
				BackgroundColor3 = CELL_CLOSED,
				BackgroundTransparency = 0,
			})
			Ui.corner(cellFrame, if size <= 6 then 6 else 3)
			local stroke = Ui.stroke(cellFrame, MINE, if size <= 6 then 6 else 4, 0)
			stroke.Enabled = false
			local mark: TextLabel? = nil
			if marks then
				-- 내 칸 가운데의 분홍 '나' 딱지 (남의 칸에서는 숨김)
				mark = Ui.label(cellFrame, "Mark", "", if size <= 4 then 34 else 24, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.7, 0.55),
					BackgroundColor3 = MINE,
					BackgroundTransparency = 1,
					TextColor3 = C.White,
					TextStrokeTransparency = 1,
				})
				Ui.corner(mark :: TextLabel, 6)
			end
			card.cells[cellIndex] = { frame = cellFrame, stroke = stroke, mark = mark, look = "", fever = nil }
		end
		cards[info.Id] = card
	end
end

local function paint(cell: Cell, look: string, color: Color3)
	if cell.look == look then
		return
	end
	local before = cell.look
	cell.look = look
	local frame = cell.frame
	cell.stroke.Enabled = look == "mine"
	if look == "closed" then
		frame.BackgroundColor3 = CELL_CLOSED
		frame.BackgroundTransparency = 0.4
	elseif look == "open" then
		frame.BackgroundColor3 = CELL_OPEN
		frame.BackgroundTransparency = 0
	else
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = if look == "mine" then 0 else TAKEN_FADE
		if before == "open" then
			-- 꽂히는 순간 잠깐 밝게
			frame.BackgroundColor3 = C.White
			Ui.tween(frame, 0.35, { BackgroundColor3 = color })
		end
	end
	if cell.mark then
		cell.mark.Text = if look == "mine" then "나" else ""
		cell.mark.BackgroundTransparency = if look == "mine" then 0 else 1
	end
end

-- 피버 반짝임을 켜고 끔. 처음 켤 때 만들어 두고 다시 씀. 칸이 작을수록 별빛이 적고(3·2·1개) 테두리도 가늘게 (50명 판도 가볍게)
local function showFever(cell: Cell, on: boolean)
	local glints = cell.fever
	if glints == nil then
		if not on then
			return
		end
		local big = builtSize <= 6
		local stars = if builtSize <= 5 then 3 elseif builtSize <= 7 then 2 else 1
		glints = FeverFx.glints(cell.frame, stars, 0.6, if big then 8 else 5, if big then 4 else 2)
		cell.fever = glints
	end
	local g = glints :: FeverFx.Glints
	if g.on ~= on then
		FeverFx.show(g, on)
		-- 칸 밖으로 나온 테두리·별빛이 옆 칸에 가리지 않게 위로
		cell.frame.ZIndex = if on then 2 else 1
	end
end

-- 서버 자료를 다시 읽어 칸·숫자·제목 줄을 맞춤
local function refresh()
	local folder = gridFolder()
	local phase = State.phase()
	if folder == nil then
		cardsFrame.Visible = false
		idleLabel.Visible = true
		builtFolder = nil
		builtSize = 0
		statusLabel.Text = ""
		return
	end
	local size = folder:GetAttribute("Size")
	if type(size) ~= "number" or size < 1 then
		return
	end
	if folder ~= builtFolder or size ~= builtSize then
		builtFolder = folder
		builtSize = size
		makeCards(size)
	end
	cardsFrame.Visible = true
	idleLabel.Visible = false
	local mySeat = if State.role() == "Crew" then State.myNumber("Seat") else 0
	local flying = phase == "Flight"
	local placedAll, openAll, feverAll = 0, 0, 0
	for _, info in ipairs(Config.Parts.Types) do
		local card = cards[info.Id]
		local typeFolder = folder:FindFirstChild(info.Id)
		if card then
			local attrs = if typeFolder then typeFolder:GetAttributes() else {}
			local color = styleOf(info.Id)
			local placed, opened = 0, 0
			for index, cell in pairs(card.cells) do
				local value = attrs["C" .. tostring(index)]
				local look = "closed"
				local fevered = false
				if type(value) == "number" then
					opened += 1
					if value > 0 then
						placed += 1
						look = if value == mySeat and mySeat > 0 then "mine" else "taken"
						fevered = flying and attrs["F" .. tostring(value)] == true
					else
						look = "open"
					end
				end
				paint(cell, look, color)
				showFever(cell, fevered)
				if fevered then
					feverAll += 1
				end
			end
			card.count.Text = string.format("%d/%d", placed, opened)
			placedAll += placed
			openAll += opened
		end
	end
	if phase == "Build" then
		statusLabel.Text = string.format("조립 중 %s · %d/%d개 장착", Fmt.clock(State.phaseLeft()), placedAll, openAll)
		statusLabel.TextColor3 = C.Yellow
	elseif feverAll > 0 then
		statusLabel.Text = string.format("피버 %d개 · 속도 +%s", feverAll, Fmt.percent(State.number("FeverBonus")))
		statusLabel.TextColor3 = FeverFx.Gold
	else
		statusLabel.Text = string.format("장착 완료 · %d개", placedAll)
		statusLabel.TextColor3 = C.Green
	end
end

local function build(board: BasePart)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local surface = Ui.make("SurfaceGui", {
		Name = "RoflyPartsBoard",
		Adornee = board,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 1.5,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	gui = surface
	local back = Ui.frame(surface, "Back", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 10, 18),
		BackgroundTransparency = 0,
	})
	Ui.label(back, "Title", "부품 장착판", 56, {
		Position = UDim2.fromOffset(PAD + 8, 10),
		Size = UDim2.new(0.5, 0, 0, HEADER - 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Text,
	})
	statusLabel = Ui.label(back, "Status", "", 40, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(PAD + 8), 0, 16),
		Size = UDim2.new(0.5, 0, 0, HEADER - 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Yellow,
	})
	idleLabel = Ui.label(back, "Idle", "다음 판 조립을 기다리는 중", 48, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(1, 0, 0, 64),
		TextColor3 = C.Dim,
	})
	cardsFrame = Ui.frame(back, "Cards", {
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(1, -2 * PAD, 1, -(HEADER + PAD)),
		Visible = false,
	})
	refresh()
end

function PartsBoard.init()
	task.spawn(function()
		local rofly = Workspace:WaitForChild("Rofly")
		local rocket = rofly:WaitForChild("Rocket")
		local board = rocket:WaitForChild("PartsBoard")
		if board:IsA("BasePart") then
			build(board)
		end
	end)
end

function PartsBoard.update(_dt: number)
	if not gui then
		return
	end
	local clock = os.clock()
	if clock - lastRefresh < REFRESH then
		return
	end
	lastRefresh = clock
	refresh()
end

-- 검사용
PartsBoard._internal = {
	size = function(): (number, number)
		return WIDTH, HEIGHT
	end,
}

return PartsBoard
