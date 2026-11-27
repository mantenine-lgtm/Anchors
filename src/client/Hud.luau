-- 비행 화면(HUD): 위쪽 안내, 탑승 버튼, 거리·속도·연료·충격파, 위기 경고, 부스터 사용 알림, 감사 버튼,
-- 선장 발사 버튼, 정산 화면, 한 줄 안내. 부스터 버튼(왼쪽 메뉴)은 BoosterMenu 가 그립니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local FlightSim = require(Shared:WaitForChild("FlightSim"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Net = require(Shared:WaitForChild("Net"))
local Route = require(Shared:WaitForChild("Route"))

local BoosterMenu = require(script.Parent:WaitForChild("BoosterMenu"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local Hud = {}

local C = Ui.Colors
local player = Players.LocalPlayer

local root: Frame
local flashRoot: Frame

-- 위쪽 안내
local bannerTitle: TextLabel
local bannerSub: TextLabel
local toastLabel: TextLabel
local toastUntil = 0

-- 지갑
local walletLabel: TextLabel

-- 탑승
local joinButton: TextButton

-- 비행
local leftPanel: Frame
local speedLabel: TextLabel
local fuelName: TextLabel
local fuelFill: Frame
local comboLabel: TextLabel
local rateLabel: TextLabel
local rightPanel: Frame
local waveGapLabel: TextLabel
local waveEtaLabel: TextLabel
local recordLabel: TextLabel
local recordSub: TextLabel
local ghostNote: TextLabel

-- 위기
local crisisBorder: Frame
local crisisEdges: { Frame } = {}
local crisisLabel: TextLabel

-- 아이템 알림과 감사
local itemBanner: TextLabel
local itemBannerUntil = 0
local thanksButton: TextButton
local thanksUntil = 0
local thanksCount: TextLabel
local heartLayer: Frame

-- 선장 발사
local countdownLabel: TextLabel
local launchPanel: Frame
local launchMarker: Frame
local launchButton: TextButton
local launchHint: TextLabel
local launchSent = false

-- 정산
local resultsPanel: Frame
local resultsShowAt = 0
local resultsData: any = nil
local resultsBuilt = false
local endLabel: TextLabel
local endUntil = 0

-- 화면 번쩍임
local flashFrame: Frame

-- 한 줄 안내·위기 경고·아이템 알림을 두는 높이 (화면 높이에 대한 비율). State.boardBottom(예전 고정 선실 카메라에서
-- 전광판 아래 끝이 오던 자리) 바로 아래, 틈은 화면 높이의 2%.
local UNDER_BOARD_GAP = 0.02
-- 승무원이 많아 전광판이 화면 아래쪽까지 보이면, 아이템 알림(안내에서 +72, 높이 42)이 그 아래 '감사 N'
-- (아래 끝이 화면 아래에서 270, 높이 30)에 닿기 직전에서 멈춤. 한도는 화면 높이(기준 단위)로 계산합니다.
local BANNER_BOTTOM = 72 + 42
local THANKS_TOP = 270 + 30
local underBoard = State.BoardBottomDefault + UNDER_BOARD_GAP

-- 바탕(root)의 높이를 기준 단위로 (화면 전체를 줄이는 UIScale 을 되돌림)
local function rootHeight(): number
	local height = root.AbsoluteSize.Y
	local scale = root:FindFirstChildOfClass("UIScale")
	if scale and scale.Scale > 0 then
		height /= scale.Scale
	end
	return if height > 0 then height else Ui.RefHeight
end

-- 전광판 아래 끝(3D 화면 전체에 대한 비율)을 이 화면 글자 판(ScreenGui)에 대한 비율로 바꿈.
-- 휴대폰은 3D 화면이 전체 화면에 그려지고 화면 글자는 안전 영역(노치·홈 막대를 뺀 곳) 안에만 그려져서
-- 두 비율이 조금 다릅니다.
local function boardBottomOnGui(): number
	local camera = Workspace.CurrentCamera
	local gui = root.Parent
	if camera and gui and gui:IsA("ScreenGui") then
		local full = camera.ViewportSize.Y
		local top = gui.AbsolutePosition.Y
		local height = gui.AbsoluteSize.Y
		if full > 0 and height > 0 then
			return (State.boardBottom * full - top) / height
		end
	end
	return State.boardBottom
end

-- 기준 높이(State.boardBottom)가 바뀌면 그 아래 글자도 따라 옮김 (화면 크기·휴대폰 안전 영역이 바뀔 때도)
local function placeUnderBoard()
	local height = rootHeight()
	local lowest = (height - THANKS_TOP - BANNER_BOTTOM) / height
	local top = math.min(boardBottomOnGui() + UNDER_BOARD_GAP, lowest)
	if math.abs(top - underBoard) < 0.0005 then
		return
	end
	underBoard = top
	toastLabel.Position = UDim2.new(0.5, 0, top, 0)
	crisisLabel.Position = UDim2.new(0.5, 0, top, 34)
	itemBanner.Position = UDim2.new(0.5, 0, top, 72)
end

local function toast(text: string, seconds: number?)
	toastLabel.Text = text
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	toastUntil = os.clock() + (seconds or 3)
end

local function flash(color: Color3, strength: number, seconds: number)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - strength
	Ui.tween(flashFrame, seconds, { BackgroundTransparency = 1 })
end

-- ------------------------------------------------------------ 만들기
local function buildBanner()
	-- 위쪽 가운데는 위에서부터: 안내 두 줄(0~76) → 빈 자리(화면 높이의 약 14~31%, 선실이 보임) → 한 줄 안내 → 위기 경고 → 아이템 알림
	-- 그 아래 글자는 높이 비율로 자리를 잡습니다. 비율은 매 프레임 placeUnderBoard 가 State.boardBottom 에 맞춥니다.
	local banner = Ui.frame(root, "Banner", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(760, 74),
	})
	bannerTitle = Ui.label(banner, "Title", "", 38, {
		Size = UDim2.new(1, 0, 0, 48),
		TextStrokeTransparency = 0.3,
	})
	bannerSub = Ui.label(banner, "Sub", "", 19, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = C.Dim,
		TextStrokeTransparency = 0.4,
	})
	toastLabel = Ui.label(root, "Toast", "", 23, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, underBoard, 0),
		Size = UDim2.fromOffset(760, 32),
		TextColor3 = C.Yellow,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
		Visible = false,
	})
	crisisLabel = Ui.label(root, "CrisisLabel", "", 30, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, underBoard, 34),
		Size = UDim2.fromOffset(640, 36),
		TextColor3 = C.Red,
		TextStrokeTransparency = 0.2,
		Visible = false,
	})
end

-- 티켓 (보유 코인은 이 칸 왼쪽의 '보유 코인' 칸, CoinFx.luau)
local function buildWallet()
	local wallet = Ui.panel(root, "Wallet", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(130, 40),
	})
	walletLabel = Ui.label(wallet, "Text", "", 19, {})
end

local function buildJoin()
	joinButton = Ui.button(root, "JoinButton", "탑승", 40, C.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -44),
		Size = UDim2.fromOffset(320, 92),
		Modal = true, -- 이 버튼이 보이는 동안에는 1인칭·시프트 락이어도 마우스가 풀려서 누를 수 있음
		Visible = false,
	})
	Ui.stroke(joinButton, C.White, 3, 0.4)
	joinButton.Activated:Connect(function()
		if State.phase() == "Join" then
			State.emit("Sound", "Press")
			Net.event("Join"):FireServer(not State.joined())
		end
	end)
end

local function statLine(parent: Instance, name: string, y: number, title: string): TextLabel
	Ui.label(parent, name .. "Title", title, 16, {
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, 20),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return Ui.label(parent, name, "", 26, {
		Position = UDim2.fromOffset(14, y + 18),
		Size = UDim2.new(1, -28, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- 비행 정보 판(속도·연료·콤보)은 왼쪽 끝의 부스터 메뉴 바로 오른쪽에
local LEFT_PANEL_X = BoosterMenu.Left + BoosterMenu.Width + 12

local function buildFlightPanels()
	leftPanel = Ui.panel(root, "FlightLeft", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, LEFT_PANEL_X, 0.4, 0),
		Size = UDim2.fromOffset(204, 232),
		Visible = false,
	})
	speedLabel = statLine(leftPanel, "Speed", 8, "속도")
	fuelName = Ui.label(leftPanel, "FuelName", "", 16, {
		Position = UDim2.fromOffset(14, 66),
		Size = UDim2.new(1, -28, 0, 20),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local _, fill = Ui.bar(leftPanel, "FuelBar", C.Cyan, {
		Position = UDim2.fromOffset(14, 90),
		Size = UDim2.new(1, -28, 0, 16),
	})
	fuelFill = fill
	comboLabel = statLine(leftPanel, "Combo", 116, "콤보")
	rateLabel = statLine(leftPanel, "Rate", 170, "지난 미션 팀 성공률")

	rightPanel = Ui.panel(root, "FlightRight", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.4, 0),
		Size = UDim2.fromOffset(236, 178),
		Visible = false,
	})
	waveGapLabel = statLine(rightPanel, "WaveGap", 8, "충격파와의 간격")
	waveEtaLabel = Ui.label(rightPanel, "WaveEta", "", 18, {
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.new(1, -28, 0, 24),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	recordLabel = statLine(rightPanel, "Record", 92, "이 서버 최고 기록")
	recordSub = Ui.label(rightPanel, "RecordSub", "", 18, {
		Position = UDim2.fromOffset(14, 142),
		Size = UDim2.new(1, -28, 0, 24),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- 관전 안내는 방향 버튼이 없는 왼쪽 아래 자리에
	ghostNote = Ui.label(root, "GhostNote", "이번 비행은 관전 중입니다. 다음 판에 탑승하세요.", 22, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		-- 가운데 아래의 미션 판(왼쪽 끝 340)에 가리지 않게 좁게 두 줄로
		Size = UDim2.fromOffset(300, 60),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true,
		TextStrokeTransparency = 0.4,
		Visible = false,
	})
end

local function buildCrisis()
	-- 화면 가장자리의 붉은 테두리. 테두리 효과(UIStroke)는 틀 바깥에 그려져 화면 밖으로 나가므로 막대 4개로 그림.
	crisisBorder = Ui.frame(flashRoot, "CrisisBorder", {
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	})
	local thickness = 22
	local function edge(name: string, anchor: Vector2, position: UDim2, size: UDim2)
		local bar = Ui.frame(crisisBorder, name, {
			AnchorPoint = anchor,
			Position = position,
			Size = size,
			BackgroundColor3 = C.Red,
			BackgroundTransparency = 0.3,
		})
		table.insert(crisisEdges, bar)
	end
	edge("Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, thickness))
	edge("Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, thickness))
	edge("Left", Vector2.new(0, 0), UDim2.fromOffset(0, thickness), UDim2.new(0, thickness, 1, -thickness * 2))
	edge("Right", Vector2.new(1, 0), UDim2.new(1, 0, 0, thickness), UDim2.new(0, thickness, 1, -thickness * 2))
end

local function buildItem()
	itemBanner = Ui.label(root, "ItemBanner", "", 30, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, underBoard, 72),
		Size = UDim2.fromOffset(820, 42),
		TextColor3 = C.Yellow,
		TextStrokeTransparency = 0.2,
		Visible = false,
	})
	-- 감사 버튼은 미션 판 바로 위에 뜸
	thanksButton = Ui.button(root, "ThanksButton", "고마워요!", 30, C.Pink, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -196),
		Size = UDim2.fromOffset(320, 68),
		Visible = false,
	})
	Ui.stroke(thanksButton, C.White, 3, 0.3)
	thanksCount = Ui.label(root, "ThanksCount", "", 24, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -270),
		Size = UDim2.fromOffset(400, 30),
		TextColor3 = C.Pink,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	heartLayer = Ui.frame(root, "Hearts", { Size = UDim2.fromScale(1, 1) })
	thanksButton.Activated:Connect(function()
		if not thanksButton.Visible then
			return
		end
		thanksButton.Visible = false
		thanksUntil = 0
		State.emit("Sound", "Thanks")
		Net.event("Thanks"):FireServer()
	end)
end

local function buildLaunch()
	-- 큰 숫자는 전광판 아래, 선장 머리 위(외창 자리)에
	countdownLabel = Ui.bigLabel(root, "Countdown", "", 130, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(400, 150),
		TextStrokeTransparency = 0.1,
		Visible = false,
	})
	launchPanel = Ui.frame(root, "LaunchPanel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.fromOffset(560, 190),
		Visible = false,
	})
	launchHint = Ui.label(launchPanel, "Hint", "", 22, {
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = C.Yellow,
	})
	-- 게이지: 표시가 왼쪽에서 오른쪽으로 움직이고, 밝은 칸에 왔을 때 누르면 완벽
	local total = Config.Captain.GaugeSeconds + Config.Captain.AutoDelay
	local target = Config.Captain.GaugeSeconds / total
	local gauge = Ui.frame(launchPanel, "Gauge", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.4,
	})
	Ui.corner(gauge, 8)
	local goodHalf = Config.Captain.GoodWindow / total
	Ui.frame(gauge, "Good", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(target, 0),
		Size = UDim2.fromScale(goodHalf * 2, 1),
		BackgroundColor3 = C.Green,
		BackgroundTransparency = 0.55,
	})
	local perfectHalf = Config.Captain.PerfectWindow / total
	Ui.frame(gauge, "Perfect", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(target, 0),
		Size = UDim2.fromScale(perfectHalf * 2, 1),
		BackgroundColor3 = C.Yellow,
		BackgroundTransparency = 0,
	})
	launchMarker = Ui.frame(gauge, "Marker", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 8, 1, 14),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0,
	})
	Ui.corner(launchMarker, 4)
	launchButton = Ui.button(launchPanel, "LaunchButton", "발사!", 44, C.Red, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(320, 104),
	})
	Ui.stroke(launchButton, C.White, 3, 0.3)
end

local function pressLaunch()
	if launchSent or State.phase() ~= "Countdown" or not State.isCaptain() then
		return
	end
	local now = State.now()
	if now < State.number("LaunchAt") - Config.Captain.EarlyLimit then
		return -- 아직 누를 수 없음
	end
	launchSent = true
	State.emit("Sound", "Press")
	Net.event("Launch"):FireServer(now)
end

local RESULTS_WIDTH = 700 -- 정산 판의 너비 (기준 단위)
local ROW_TEXT_LEFT = 160 -- 정산 줄 글자의 왼쪽 끝
local ROW_TEXT_WIDTH = RESULTS_WIDTH - ROW_TEXT_LEFT - 34 -- 정산 줄 글자가 들어갈 너비
local ROW_MIN_SIZE = 14 -- 이름이 길어 글자를 줄일 때 가장 작은 크기

local function buildResults()
	endLabel = Ui.label(root, "EndLabel", "", 58, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(1000, 80),
		TextStrokeTransparency = 0.1,
		Visible = false,
	})
	resultsPanel = Ui.panel(root, "Results", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(RESULTS_WIDTH, 496),
		BackgroundTransparency = 0.03,
		Visible = false,
	})
	Ui.stroke(resultsPanel, C.Line, 2, 0)
end

-- 글자가 정산 줄 한 줄에 들어가는 가장 큰 크기: size 에서 2씩 줄여 ROW_MIN_SIZE 까지.
-- TextScaled 와 UITextSizeConstraint 는 화면 전체를 줄이는 UIScale 아래에서 어떻게 되는지 문서로 확인되지
-- 않아 쓰지 않고, 글자 너비를 직접 잽니다 (너비는 글자 크기에 비례하므로 기준 단위 그대로 견줌).
local function rowTextSize(text: string, size: number): number
	local fit = size
	while fit > ROW_MIN_SIZE do
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(text, fit, Ui.Font, Vector2.new(100000, 1000))
		end)
		if not ok or bounds.X <= ROW_TEXT_WIDTH then
			break
		end
		fit = math.max(fit - 2, ROW_MIN_SIZE)
	end
	return fit
end

local function resultRow(parent: Instance, y: number, title: string, text: string, color: Color3, size: number)
	Ui.label(parent, "RowTitle", title, 18, {
		Position = UDim2.fromOffset(34, y),
		Size = UDim2.fromOffset(120, size + 8),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- 이름이 길면 판 밖으로 나가는 대신 글자를 줄여 한 줄에 맞춤 (가장 클 때가 size, 뒤쪽 숫자가 잘리지 않음)
	Ui.label(parent, "RowText", text, rowTextSize(text, size), {
		Position = UDim2.fromOffset(ROW_TEXT_LEFT, y),
		Size = UDim2.new(1, -(ROW_TEXT_LEFT + 34), 0, size + 8),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, -- 가장 작게 해도 넘치면 끝을 줄임
	})
end

local LAUNCH_TEXT = {
	perfect = "완벽한 발사",
	good = "좋은 발사",
	early = "이른 발사",
	late = "늦은 발사",
	auto = "자동 발사",
}

local function fillResults(data: any)
	resultsPanel:ClearAllChildren()
	Ui.corner(resultsPanel, 12)
	Ui.stroke(resultsPanel, C.Line, 2, 0)
	local common = data.common
	local me = data.me
	Ui.label(resultsPanel, "Head", string.format("%d판 결과", common.round), 22, {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = C.Dim,
	})
	local title = Fmt.km(common.km)
	if common.escaped then
		title = "탈출 성공! " .. title
	end
	Ui.label(resultsPanel, "Distance", title, 56, {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 66),
		TextColor3 = if common.newServerBest then C.Yellow else C.Text,
	})
	local line = string.format("%s · 비행 %d초 · 팀 성공률 %s · %s", common.stageName, math.floor(common.seconds + 0.5), Fmt.percent(common.teamRate), LAUNCH_TEXT[common.launch] or "")
	if common.newServerBest then
		line = "서버 신기록! · " .. line
	end
	Ui.label(resultsPanel, "Line", line, 19, {
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = C.Dim,
	})

	-- 시상 3종
	local y = 148
	local hero = common.hero
	resultRow(resultsPanel, y, "영웅", if hero then string.format("%s · 기여 %s", hero.name, Fmt.km(hero.value)) else "없음", if hero then C.Yellow else C.Dim, 26)
	y += 40
	local king = common.king
	resultRow(resultsPanel, y, "미션왕", if king then string.format("%s · %d연속 성공", king.name, king.value) else "없음", if king then C.Cyan else C.Dim, 26)
	y += 40
	local savior = common.savior
	local saviorText = "없음"
	local botSave = common.botSave
	if savior then
		local item = if type(common.saviorItem) == "string" and common.saviorItem ~= "" then common.saviorItem else "부스터"
		saviorText = string.format("%s · %s +%s · 감사 %d", savior.name, Fmt.josa(item, "으로", "로"), Fmt.km(savior.extra), savior.value)
	elseif type(botSave) == "table" and botSave.km > 0 then
		saviorText = string.format("봇의 %s +%s", Fmt.josa(botSave.item, "으로", "로"), Fmt.km(botSave.km))
	end
	resultRow(resultsPanel, y, "구원자", saviorText, if savior then C.Pink else C.Dim, 26)
	y += 52

	local divider = Ui.frame(resultsPanel, "Divider", {
		Position = UDim2.fromOffset(34, y),
		Size = UDim2.new(1, -68, 0, 2),
		BackgroundColor3 = C.Line,
		BackgroundTransparency = 0,
	})
	divider.ZIndex = 2
	y += 14

	if me then
		local badges = {}
		if me.isHero then
			table.insert(badges, "이번 비행의 영웅")
		end
		if me.isKing then
			table.insert(badges, "미션왕")
		end
		if me.isSavior then
			table.insert(badges, "구원자")
		end
		if #badges > 0 then
			Ui.label(resultsPanel, "Badges", table.concat(badges, " · ") .. "!", 30, {
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, 40),
				TextColor3 = C.Yellow,
			})
			y += 44
		end
		local reward = string.format("코인 +%s", Fmt.comma(me.coins))
		if type(me.goldenCoins) == "number" and me.goldenCoins > 0 then
			reward ..= string.format(" (황금 항로 +%s)", Fmt.comma(me.goldenCoins))
		end
		if me.tickets > 0 then
			reward ..= string.format(" · 티켓 +%d", me.tickets)
		end
		if me.afk then
			reward ..= " (자리 비움: 코인 절반)"
		end
		resultRow(resultsPanel, y, "보상", reward, C.Green, 24)
		y += 36
		-- 순위는 사람끼리만 견줌 (봇은 시상에서 빠지므로). 혼자면 순위를 적지 않음
		local mine = Fmt.km(me.contributionKm)
		if me.crew >= 2 then
			mine ..= string.format(" · 사람 %d명 중 %d위", me.crew, me.rank)
		end
		mine ..= string.format(" · 미션 %d/%d", me.successes, me.attempts)
		resultRow(resultsPanel, y, "내 기여", mine, C.Text, 22)
		y += 34
		if me.newBest then
			resultRow(resultsPanel, y, "내 기록", "개인 최고 기록 갱신!", C.Yellow, 22)
		end
	else
		Ui.label(resultsPanel, "Spectator", "관전했습니다. 다음 판에 탑승하면 보상을 받습니다.", 22, {
			Position = UDim2.fromOffset(0, y + 10),
			Size = UDim2.new(1, 0, 0, 30),
			TextColor3 = C.Dim,
		})
	end
	Ui.label(resultsPanel, "Next", "", 18, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = C.Dim,
	})
end

-- ------------------------------------------------------------ 하트
-- 승무원 번호 seat 인 사람(봇) 머리 위가 화면의 어디인지 (화면 글자 판에 대한 비율). 화면 밖이면 nil
local function memberScreenPoint(seat: number): Vector2?
	local camera = workspace.CurrentCamera
	local head = State.memberPart(seat)
	if camera and head then
		local point, onScreen = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.5, 0))
		if onScreen then
			local gui = root.Parent :: ScreenGui
			local size = gui.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				return Vector2.new(point.X / size.X, point.Y / size.Y)
			end
		end
	end
	return nil
end

local function flyHeart(fromSeat: number, toSeat: number)
	local from = memberScreenPoint(fromSeat) or Vector2.new(0.5 + (math.random() - 0.5) * 0.5, 0.8)
	local to = memberScreenPoint(toSeat) or Vector2.new(0.5, 0.42)
	local heart = Ui.heart(heartLayer, 34, C.Pink)
	heart.Position = UDim2.fromScale(from.X, from.Y)
	local tween = Ui.tween(heart, 0.9, { Position = UDim2.fromScale(to.X, to.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	tween.Completed:Connect(function()
		heart:Destroy()
	end)
	task.delay(2, function()
		if heart.Parent then
			heart:Destroy()
		end
	end)
end

-- ------------------------------------------------------------ 신호 처리
local function onLaunched(info: any)
	local quality = info.quality
	if quality == "perfect" then
		toast(string.format("완벽한 발사! 초반 속도 +%d%%", math.floor(info.bonus * 100 + 0.5)), 4)
	elseif quality == "good" then
		toast(string.format("좋은 발사! 초반 속도 +%d%%", math.floor(info.bonus * 100 + 0.5)), 4)
	elseif quality == "early" then
		toast("발사! 조금 빨랐습니다", 3)
	elseif quality == "late" then
		toast("발사! 조금 늦었습니다", 3)
	else
		toast("자동 발사!", 3)
	end
	flash(C.White, 0.7, 0.8)
end

local function onItemUsed(info: any)
	if type(info) ~= "table" then
		return
	end
	local booster = Boosters.get(info.item)
	local itemName = if booster then booster.Name else "부스터"
	itemBanner.Text = string.format("%s 님이 %s 썼습니다!", tostring(info.name), Fmt.josa(itemName, "을", "를"))
	itemBanner.Visible = true
	itemBannerUntil = os.clock() + info.thanksSeconds + 1
	thanksCount.Text = ""
	thanksCount.Visible = true
	if booster then
		toast(string.format("%s: %s", booster.Name, booster.Desc), 4)
	end
	if info.item == "Wormhole" then
		-- 웜홀만의 워프 연출: 길고 밝게
		flash(C.Purple, 0.85, 1.6)
	else
		flash(if booster then BoosterMenu.colorOf(booster.Id) else C.Orange, 0.5, 0.8)
	end
	if info.userId ~= player.UserId or info.isBot then
		thanksButton.Visible = true
		thanksUntil = os.clock() + info.thanksSeconds
	end
end

local function onThanksFx(info: any)
	thanksCount.Text = string.format("감사 %d", info.count)
	flyHeart(info.fromSeat, info.toSeat)
end

local function onFlightEnd(info: any)
	if info.escaped then
		endLabel.Text = "폭발권 밖으로 탈출했습니다!"
		endLabel.TextColor3 = C.Yellow
		flash(C.White, 0.8, 1.2)
	else
		endLabel.Text = "충격파에 따라잡혔습니다"
		endLabel.TextColor3 = C.Red
		flash(C.Orange, 0.9, 1.4)
	end
	endLabel.Visible = true
	endUntil = os.clock() + 2.2
end

local function onResults(data: any)
	if type(data) ~= "table" or type(data.common) ~= "table" then
		return
	end
	resultsData = data
	resultsBuilt = false
	resultsShowAt = os.clock() + 2.2
end

-- ------------------------------------------------------------ 매 프레임
local FUEL_TEXT = {
	rescue = "구원 연료 분사 중",
	hot = "최대 출력",
	cruise = "순항 (연료)",
	sail = "솔라 세일",
	coast = "관성 비행 (감속)",
}
local FUEL_COLOR = {
	rescue = C.Orange,
	hot = C.Yellow,
	cruise = C.Cyan,
	sail = C.Purple,
	coast = C.Red,
}

local function updateBanner(phase: string)
	if phase == "Join" then
		local left = State.phaseLeft()
		bannerTitle.Text = "행성 붕괴까지 " .. Fmt.clock(left)
		bannerTitle.TextColor3 = if left <= 10 then C.Orange else C.Text
		local joined = State.number("JoinedCount")
		local total = State.number("PlayerCount")
		if State.joined() then
			bannerSub.Text = string.format("탑승 완료 · %d/%d명 탑승 · 곧 로켓을 조립합니다", joined, total)
		else
			bannerSub.Text = string.format("탑승 버튼을 눌러 로켓에 타세요 · %d/%d명 탑승", joined, total)
		end
	elseif phase == "Build" then
		bannerTitle.Text = "로켓 조립 중 " .. Fmt.clock(State.phaseLeft())
		bannerTitle.TextColor3 = C.Text
		local gear = State.gearName()
		local captain = State.text("CaptainName")
		if State.isCaptain() then
			bannerSub.Text = "당신이 선장입니다! 카운트다운이 0이 될 때 발사 버튼을 누르세요"
			bannerSub.TextColor3 = C.Yellow
		else
			bannerSub.Text = string.format("승무원 %d명 · 장비 %s · 예상 거리 %s · 선장 %s", State.number("CrewCount"), gear, Fmt.km(State.number("ExpectedKm")), if captain ~= "" then captain else "없음")
			bannerSub.TextColor3 = C.Dim
		end
	elseif phase == "Countdown" then
		bannerTitle.Text = "발사 카운트다운"
		bannerTitle.TextColor3 = C.Text
		local captain = State.text("CaptainName")
		if State.isCaptain() then
			bannerSub.Text = "0이 되는 순간에 발사 버튼!"
			bannerSub.TextColor3 = C.Yellow
		else
			bannerSub.Text = if captain ~= "" then string.format("선장 %s 님이 발사 버튼을 누릅니다", captain) else "자동으로 발사됩니다"
			bannerSub.TextColor3 = C.Dim
		end
	elseif phase == "Flight" then
		local km = State.flight.km
		bannerTitle.Text = Fmt.km(km)
		bannerTitle.TextColor3 = C.Text
		local index, _, toNext = Route.progress(km)
		bannerSub.Text = string.format("%s · 다음 스테이지까지 %s", Route.stage(index).Name, Fmt.km(toNext))
		bannerSub.TextColor3 = C.Dim
	else
		bannerTitle.Text = "정산"
		bannerTitle.TextColor3 = C.Text
		bannerSub.Text = string.format("다음 판까지 %s", Fmt.clock(State.phaseLeft()))
		bannerSub.TextColor3 = C.Dim
	end
end

local function updateFlight()
	local f = State.flight
	speedLabel.Text = Fmt.speed(f.speed)

	local t = f.t
	local hot, fuel, sail = State.number("HotTime"), State.number("FuelTime"), State.number("SailTime")
	local rescueUntil = State.number("RescueUntil")
	local phaseName = FlightSim.phaseAt(t, hot, fuel, sail, rescueUntil)
	local fraction = 0
	if phaseName == "rescue" then
		fraction = (rescueUntil - t) / Config.Rescue.Hold
	elseif phaseName == "hot" then
		fraction = (hot - t) / math.max(hot, 0.01)
	elseif phaseName == "cruise" then
		fraction = (fuel - t) / math.max(fuel - hot, 0.01)
	elseif phaseName == "sail" then
		fraction = (fuel + sail - t) / math.max(sail, 0.01)
	end
	fuelName.Text = FUEL_TEXT[phaseName] or ""
	fuelFill.BackgroundColor3 = FUEL_COLOR[phaseName] or C.Cyan
	fuelFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)

	local combo = State.number("Combo")
	comboLabel.Text = if combo > 0 then string.format("x%d", combo) else "-"
	comboLabel.TextColor3 = if combo >= Config.Flight.ComboMax then C.Yellow elseif combo > 0 then C.Green else C.Dim
	local rate = State.number("LastRate")
	rateLabel.Text = if rate >= 0 then Fmt.percent(rate) else "-"
	rateLabel.TextColor3 = if rate >= Config.Mission.ComboRule then C.Green elseif rate >= 0 then C.Orange else C.Dim

	local gap = math.max(f.km - f.waveKm, 0)
	waveGapLabel.Text = Fmt.km(gap)
	local eta = State.number("Eta")
	local crisis = State.flag("Crisis")
	if eta >= Config.Crisis.EtaLimit then
		waveEtaLabel.Text = "아직 멀리 있습니다"
		waveEtaLabel.TextColor3 = C.Dim
	else
		waveEtaLabel.Text = string.format("약 %d초 뒤 도달", math.ceil(eta))
		waveEtaLabel.TextColor3 = if crisis then C.Red else C.Orange
	end
	waveGapLabel.TextColor3 = if crisis then C.Red else C.Text

	local best = State.number("BestKm")
	if best <= 0 then
		recordLabel.Text = "첫 비행"
		recordSub.Text = "이번 거리가 첫 기록"
		recordSub.TextColor3 = C.Dim
	else
		recordLabel.Text = Fmt.km(best)
		if f.km >= best then
			recordSub.Text = "신기록 갱신 중!"
			recordSub.TextColor3 = C.Yellow
		else
			recordSub.Text = string.format("기록까지 %s", Fmt.km(best - f.km))
			recordSub.TextColor3 = C.Dim
		end
	end

	-- 위기
	crisisBorder.Visible = crisis
	crisisLabel.Visible = crisis
	if crisis then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
		for _, bar in ipairs(crisisEdges) do
			bar.BackgroundTransparency = 0.15 + 0.5 * pulse
		end
		crisisLabel.Text = string.format("충격파 접근! 약 %d초 뒤 도달", math.ceil(eta))
	end
end

local function updateLaunch()
	local launchAt = State.number("LaunchAt")
	local left = launchAt - State.now()
	countdownLabel.Visible = true
	if left > 0 then
		countdownLabel.Text = tostring(math.ceil(left))
		countdownLabel.TextColor3 = if left <= 3 then C.Yellow else C.Text
	else
		countdownLabel.Text = "발사!"
		countdownLabel.TextColor3 = C.Orange
	end
	local captain = State.isCaptain()
	launchPanel.Visible = captain
	if captain then
		local total = Config.Captain.GaugeSeconds + Config.Captain.AutoDelay
		local x = math.clamp((Config.Captain.GaugeSeconds - left) / total, 0, 1)
		launchMarker.Position = UDim2.fromScale(x, 0.5)
		if launchSent then
			launchHint.Text = "발사 신호를 보냈습니다"
			launchButton.BackgroundColor3 = C.PanelLight
		elseif left > Config.Captain.EarlyLimit then
			launchHint.Text = "표시가 밝은 칸에 올 때 누르세요"
			launchButton.BackgroundColor3 = C.PanelLight
		else
			launchHint.Text = "지금!"
			launchButton.BackgroundColor3 = C.Red
		end
	end
end

function Hud.update(_dt: number)
	local phase = State.phase()
	local clock = os.clock()
	updateBanner(phase)

	walletLabel.Text = string.format("티켓 %d", State.myNumber("Tickets"))

	placeUnderBoard()

	-- 탑승 버튼
	local showJoin = phase == "Join"
	joinButton.Visible = showJoin
	if showJoin then
		if State.joined() then
			joinButton.Text = "탑승 취소"
			joinButton.BackgroundColor3 = C.PanelLight
		else
			joinButton.Text = "탑승"
			joinButton.BackgroundColor3 = C.Green
		end
	end

	-- 비행
	local flying = phase == "Flight"
	leftPanel.Visible = flying
	rightPanel.Visible = flying
	if flying then
		updateFlight()
	else
		crisisBorder.Visible = false
		crisisLabel.Visible = false
	end
	ghostNote.Visible = State.role() == "Ghost" and (phase == "Build" or phase == "Countdown" or phase == "Flight")

	-- 카운트다운과 선장 발사
	if phase == "Countdown" then
		updateLaunch()
	else
		countdownLabel.Visible = false
		launchPanel.Visible = false
	end

	-- 아이템 알림, 감사 버튼
	if itemBanner.Visible and (clock > itemBannerUntil or not flying) then
		itemBanner.Visible = false
		thanksCount.Visible = false
	end
	if thanksButton.Visible then
		if clock > thanksUntil or not flying then
			thanksButton.Visible = false
		else
			thanksButton.Text = string.format("고마워요! (%d)", math.ceil(thanksUntil - clock))
		end
	end

	-- 한 줄 안내
	if toastLabel.Visible and clock > toastUntil then
		toastLabel.Visible = false
	end

	-- 비행 끝 문구와 정산
	if endLabel.Visible and clock > endUntil then
		endLabel.Visible = false
	end
	if phase == "Results" and resultsData ~= nil and clock >= resultsShowAt then
		if not resultsBuilt then
			resultsBuilt = true
			fillResults(resultsData)
			State.emit("Sound", "MissionSuccess")
		end
		resultsPanel.Visible = true
		local nextLabel = resultsPanel:FindFirstChild("Next")
		if nextLabel and nextLabel:IsA("TextLabel") then
			nextLabel.Text = string.format("다음 판까지 %s", Fmt.clock(State.phaseLeft()))
		end
	else
		resultsPanel.Visible = false
	end
end

function Hud.init()
	local _, flashBase = Ui.screen("RoflyFlash", 5)
	flashRoot = flashBase
	flashFrame = Ui.frame(flashRoot, "Flash", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 1,
	})
	local _, base = Ui.screen("RoflyHud", 10)
	root = base

	buildBanner()
	buildWallet()
	buildJoin()
	buildFlightPanels()
	buildCrisis()
	buildItem()
	buildLaunch()
	buildResults()

	launchButton.MouseButton1Down:Connect(pressLaunch)
	-- 스페이스는 기본 조작(점프)에 묶여 있으면 "이미 처리된 입력"으로 오기도 해서, 그 표시는 보지 않고
	-- 채팅 등 글자를 치는 중인지만 확인합니다. (엔터는 채팅을 보내는 키라서 발사 키로 쓰지 않음)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if State.typing() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
			pressLaunch()
		end
	end)

	State.on("Launched", onLaunched)
	State.on("ItemUsed", onItemUsed)
	State.on("ThanksFx", onThanksFx)
	State.on("FlightEnd", onFlightEnd)
	State.on("Results", onResults)
	State.on("Announce", function(text: any)
		if type(text) == "string" then
			toast(text, 4)
		end
	end)
	State.on("Toast", function(text: any)
		if type(text) == "string" then
			toast(text, 3)
		end
	end)
	State.on("Phase", function(phase: string)
		if phase == "Countdown" then
			launchSent = false
		elseif phase == "Join" then
			resultsData = nil
			resultsBuilt = false
			itemBanner.Visible = false
			thanksButton.Visible = false
			thanksCount.Visible = false
			heartLayer:ClearAllChildren()
		end
	end)
end

return Hud
