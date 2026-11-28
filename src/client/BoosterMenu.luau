-- 부스터 메뉴: 비행 중 화면 왼쪽에 떠 있는 부스터 6종 버튼. 누르면 바로 씁니다.
-- 종류마다 한 비행에 로켓 전체에서 1번 (먼저 누른 사람이 씀). 티켓을 1장씩 씁니다.
-- 버튼 칸 아래 줄에 지금 상태를 적습니다: 티켓 1 / 위기 때만 / 티켓 없음 / 사용 중… / 12초(효과 남은 시간) / 적용 중 / 사용됨.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local BoosterMenu = {}

local C = Ui.Colors

-- 부스터마다 버튼 색
local COLORS: { [string]: Color3 } = {
	RescueFuel = C.Orange,
	Turbo = C.Red,
	Slingshot = C.Cyan,
	Wormhole = C.Purple,
	Golden = C.Yellow,
	Resonance = C.Green,
}

-- 칸 배치 (기준 화면 1280x720 단위). 한 줄에 2칸씩 3줄, 왼쪽 끝에 붙임.
-- 세로로는 예전 비행 정보 판과 같은 높이(화면 높이의 40% 를 가운데로)라서
-- 위쪽의 Roblox 메뉴 아이콘(휴대폰에서 기준 단위로 약 115 까지)과 아래쪽 터치 방향 버튼(432 부터)에 닿지 않습니다.
-- 누르면 확인 없이 바로 쓰므로, 손가락으로 누르는 기기(키보드 없음)는 칸을 키워 잘못 누르기 어렵게 합니다.
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local TILE = if TOUCH_ONLY then 80 else 66
local NAME_SIZE = if TOUCH_ONLY then 19 else 17
local STATUS_SIZE = if TOUCH_ONLY then 14 else 13
local GAP = 6
local COLS = 2
local HEADER = 26
BoosterMenu.Left = 16
BoosterMenu.Width = COLS * TILE + (COLS - 1) * GAP

type Tile = {
	info: any, -- Config.Boosters.List 의 한 줄
	button: TextButton,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	stroke: UIStroke,
	color: Color3,
}

local root: Frame
local menu: Frame
local header: TextLabel
local tooltip: TextLabel
local tooltipUntil = 0
local tiles: { Tile } = {}
local pendingUntil: { [string]: number } = {} -- 누른 뒤 서버 답을 기다리는 동안 (os.clock 기준)

-- 부스터의 색 (사용 알림의 화면 번쩍임도 같은 색)
function BoosterMenu.colorOf(id: string): Color3
	return COLORS[id] or C.Cyan
end

local function toast(text: string)
	State.emit("Toast", text)
end

-- 지금 이 부스터를 쓸 수 있는지와, 버튼 아래 줄에 적을 글
local function status(tile: Tile): (boolean, string, string)
	local id = tile.info.Id
	local t = State.flight.t
	if State.flag(Boosters.usedAttribute(id)) then
		local untilT = State.number(Boosters.untilAttribute(id))
		if untilT > t then
			return false, string.format("%d초", math.ceil(untilT - t)), "active"
		elseif id == "Golden" then
			return false, "적용 중", "active"
		end
		return false, "사용됨", "used"
	end
	if (pendingUntil[id] or 0) > os.clock() then
		return false, "사용 중…", "pending"
	end
	if id == "RescueFuel" and not State.flag("Crisis") then
		return false, "위기 때만", "locked"
	end
	if State.myNumber("Tickets") < tile.info.Cost then
		return false, "티켓 없음", "locked"
	end
	return true, string.format("티켓 %d", tile.info.Cost), "ready"
end

local function press(tile: Tile)
	if State.phase() ~= "Flight" or State.role() ~= "Crew" then
		return
	end
	local info = tile.info
	local id = info.Id
	if State.flag(Boosters.usedAttribute(id)) then
		local by = State.text(Boosters.byAttribute(id))
		toast(if by ~= "" then string.format("%s: %s 님이 이미 썼습니다", info.Name, by) else info.Name .. ": 이번 비행에 이미 썼습니다")
		State.emit("Sound", "Wrong")
		return
	end
	if (pendingUntil[id] or 0) > os.clock() then
		return
	end
	if id == "RescueFuel" and not State.flag("Crisis") then
		toast("구원 연료는 위기 때만 쓸 수 있습니다")
		State.emit("Sound", "Wrong")
		return
	end
	if State.myNumber("Tickets") < info.Cost then
		toast("티켓이 없습니다. 티켓은 시상으로 받습니다")
		State.emit("Sound", "Wrong")
		return
	end
	pendingUntil[id] = os.clock() + Config.Boosters.PendingSeconds
	State.emit("Sound", "Press")
	Net.event("UseItem"):FireServer(id)
end

-- 마우스를 올리면 버튼 오른쪽에 설명 (터치 기기는 쓰고 나면 위쪽 알림으로 알 수 있음)
local TIP_SIZE = 17
local function showTooltip(tile: Tile, index: number)
	local row = math.floor((index - 1) / COLS)
	local text = string.format("%s · %s · 티켓 %d", tile.info.Name, tile.info.Desc, tile.info.Cost)
	local width = 360
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, TIP_SIZE, Ui.Font, Vector2.new(100000, 1000))
	end)
	if ok then
		width = bounds.X + 24
	end
	tooltip.Text = text
	tooltip.Size = UDim2.fromOffset(width, 34)
	tooltip.Position = UDim2.new(0, BoosterMenu.Width + 10, 0, HEADER + row * (TILE + GAP) + TILE / 2)
	tooltip.Visible = true
	tooltipUntil = os.clock() + 4
end

local function buildTile(info: any, index: number): Tile
	local col = (index - 1) % COLS
	local row = math.floor((index - 1) / COLS)
	local color = BoosterMenu.colorOf(info.Id)
	local button = Ui.button(menu, "Booster_" .. info.Id, "", NAME_SIZE, C.PanelLight, {
		Position = UDim2.fromOffset(col * (TILE + GAP), HEADER + row * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = true,
	})
	local stroke = Ui.stroke(button, color, 2, 0)
	-- 이름은 두 줄로 ("터보 엔진" -> "터보" / "엔진")
	local nameLabel = Ui.label(button, "Name", (string.gsub(info.Name, " ", "\n")), NAME_SIZE, {
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 1, -(STATUS_SIZE + 12)),
		TextStrokeTransparency = 0.3,
	})
	local statusLabel = Ui.label(button, "Status", "", STATUS_SIZE, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, STATUS_SIZE + 3),
		Font = Ui.FontLight,
		TextStrokeTransparency = 0.4,
	})
	local tile: Tile = {
		info = info,
		button = button,
		nameLabel = nameLabel,
		statusLabel = statusLabel,
		stroke = stroke,
		color = color,
	}
	button.Activated:Connect(function()
		press(tile)
	end)
	button.MouseEnter:Connect(function()
		showTooltip(tile, index)
	end)
	button.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)
	return tile
end

function BoosterMenu.init()
	local _, base = Ui.screen("RoflyBoosters", 11)
	root = base
	local rows = math.ceil(#Boosters.List / COLS)
	menu = Ui.frame(root, "BoosterMenu", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, BoosterMenu.Left, 0.4, 0),
		Size = UDim2.fromOffset(BoosterMenu.Width, HEADER + rows * TILE + (rows - 1) * GAP),
		Visible = false,
	})
	header = Ui.label(menu, "Header", "부스터", 16, {
		Size = UDim2.new(1, 0, 0, HEADER - 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Dim,
		TextStrokeTransparency = 0.3,
	})
	tooltip = Ui.label(menu, "BoosterTip", "", TIP_SIZE, {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(360, 34),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		TextStrokeTransparency = 1,
		ZIndex = 3,
		Visible = false,
	})
	Ui.corner(tooltip, 8)
	for index, info in ipairs(Boosters.List) do
		table.insert(tiles, buildTile(info, index))
	end
	State.on("Phase", function(phase: string)
		if phase == "Flight" then
			table.clear(pendingUntil)
		end
	end)
end

function BoosterMenu.update(_dt: number)
	local show = State.flying() and State.role() == "Crew" -- 충격파에 잡히면(엔딩) 바로 숨김
	menu.Visible = show
	if not show then
		tooltip.Visible = false
		return
	end
	local clock = os.clock()
	if tooltip.Visible and clock > tooltipUntil then
		tooltip.Visible = false
	end
	header.Text = string.format("부스터 · 티켓 %d", State.myNumber("Tickets"))
	local crisis = State.flag("Crisis")
	local pulse = 0.5 + 0.5 * math.sin(clock * 9)
	for _, tile in ipairs(tiles) do
		local id = tile.info.Id
		if pendingUntil[id] and State.flag(Boosters.usedAttribute(id)) then
			pendingUntil[id] = nil -- 서버가 받아 줌
		end
		local ready, text, kind = status(tile)
		tile.statusLabel.Text = text
		tile.button:SetAttribute("Ready", ready) -- 검사 도구가 읽음
		local button = tile.button
		if kind == "ready" then
			-- 쓸 수 있음: 부스터 색
			button.BackgroundColor3 = tile.color:Lerp(C.Panel, 0.35)
			button.BackgroundTransparency = 0.05
			tile.nameLabel.TextColor3 = C.Text
			tile.statusLabel.TextColor3 = C.Text
			tile.stroke.Color = tile.color
			tile.stroke.Thickness = 2
			if id == "RescueFuel" and crisis then
				-- 위기 때 구원 연료는 깜박여서 눈에 띄게
				tile.stroke.Color = C.White
				tile.stroke.Thickness = 2 + 2 * pulse
				button.BackgroundColor3 = tile.color:Lerp(C.Panel, 0.15 * pulse)
			end
		elseif kind == "active" then
			-- 효과가 도는 중: 밝게
			button.BackgroundColor3 = tile.color:Lerp(C.Panel, 0.1)
			button.BackgroundTransparency = 0
			tile.nameLabel.TextColor3 = C.Text
			tile.statusLabel.TextColor3 = C.Text
			tile.stroke.Color = C.White
			tile.stroke.Thickness = 2
		else
			-- 못 씀 (위기 때만·티켓 없음·사용 중·사용됨): 어둡게
			button.BackgroundColor3 = if kind == "used" then C.Panel else C.PanelLight
			button.BackgroundTransparency = 0.15
			tile.nameLabel.TextColor3 = if kind == "used" then C.Dim else C.Text
			tile.statusLabel.TextColor3 = C.Dim
			tile.stroke.Color = if kind == "used" then C.Line else tile.color
			tile.stroke.Thickness = 1
		end
	end
end

return BoosterMenu
