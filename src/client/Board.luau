-- 선실 전광판(진행도): 로켓 안에서 보는 큰 화면.
-- 위쪽 글자: 스테이지·거리·속도 (조립 때는 부품 종류별 파워, 카운트다운 때는 남은 초).
-- 아래쪽 추격 화면(ChaseView): 로켓이 왼쪽에서 오른쪽으로 가고 충격파 면이 뒤따라오며, 면이 꼬리에 닿으면 로켓이 터짐.
-- 화면은 클라이언트가 만들어 서버의 Board 파트 앞면에 붙입니다. 배치는 Config.World 의 전광판 크기를 따라갑니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Route = require(Shared:WaitForChild("Route"))

local ChaseView = require(script.Parent:WaitForChild("ChaseView"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local Board = {}

local C = Ui.Colors
local PIXELS_PER_STUD = 30
local WIDTH = Config.World.BoardWidth * PIXELS_PER_STUD
local HEIGHT = Config.World.BoardHeight * PIXELS_PER_STUD
-- 글자 배율: 높이 11 스터드(330 px)일 때 1. 전광판이 커지면 글자도 조금 키움 (멀리서도 보이게, 최대 1.25배)
local S = math.clamp(HEIGHT / 330, 1, 1.25)
local TEXT_HEIGHT = math.floor(200 * S) -- 위쪽 글자 묶음 높이. 그 아래는 추격 화면
local CHASE_SIDE = 14 -- 추격 화면 좌우 여백(px)
local CHASE_BOTTOM = 8 -- 추격 화면 아래 여백(px)

local function px(n: number): number
	return math.floor(n * S + 0.5)
end

local gui: SurfaceGui? = nil
local headLabel: TextLabel
local mainLabel: TextLabel
local subLabel: TextLabel
local leftLabel: TextLabel
local rightLabel: TextLabel
local buildFrame: Frame
local buildBars: { [string]: { fill: Frame, value: TextLabel } } = {}

local function build(board: BasePart)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local surface = Ui.make("SurfaceGui", {
		Name = "RoflyBoard",
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
	-- 선실에서는 이 그림이 작게 보이므로 글자를 크게 씀
	headLabel = Ui.label(back, "Head", "", px(40), {
		Position = UDim2.fromOffset(0, px(4)),
		Size = UDim2.new(1, 0, 0, px(48)),
		TextColor3 = C.Dim,
	})
	mainLabel = Ui.bigLabel(back, "Main", "", px(104), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, px(46) / HEIGHT),
		Size = UDim2.new(1, 0, 0, px(112)),
		TextColor3 = C.Cyan,
	})
	subLabel = Ui.label(back, "Sub", "", px(34), {
		Position = UDim2.fromOffset(0, px(154)),
		Size = UDim2.new(1, 0, 0, px(40)),
	})
	leftLabel = Ui.label(back, "Left", "", px(36), {
		Position = UDim2.fromOffset(px(24), px(6)),
		Size = UDim2.fromOffset(px(280), px(44)),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Green,
	})
	rightLabel = Ui.label(back, "Right", "", px(36), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -px(24), 0, px(6)),
		Size = UDim2.fromOffset(px(320), px(44)),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Orange,
	})

	-- 추격 화면: 글자 아래 남은 자리 전부
	local chaseWidth = WIDTH - CHASE_SIDE * 2
	local chaseHeight = HEIGHT - TEXT_HEIGHT - CHASE_BOTTOM
	local chaseHolder = Ui.frame(back, "ChaseHolder", {
		Position = UDim2.fromOffset(CHASE_SIDE, TEXT_HEIGHT),
		Size = UDim2.fromOffset(chaseWidth, chaseHeight),
	})
	ChaseView.build(chaseHolder, chaseWidth, chaseHeight)

	-- 빌드: 부품 종류별 파워 막대 (거리 글자 자리)
	buildFrame = Ui.frame(back, "Build", {
		Position = UDim2.fromOffset(px(40), px(48)),
		Size = UDim2.new(1, -px(80), 0, px(104)),
		Visible = false,
	})
	local types = Config.Parts.Types
	local column = (WIDTH - px(80)) / #types
	for i, info in ipairs(types) do
		local cell = Ui.frame(buildFrame, info.Id, {
			Position = UDim2.fromOffset((i - 1) * column, 0),
			Size = UDim2.fromOffset(column - 12, px(104)),
		})
		Ui.label(cell, "Name", info.Name, px(28), {
			Size = UDim2.new(1, 0, 0, px(32)),
			TextColor3 = C.Dim,
		})
		local _, fill = Ui.bar(cell, "Bar", C.Cyan, {
			Position = UDim2.fromOffset(0, px(36)),
			Size = UDim2.new(1, 0, 0, px(24)),
		})
		local value = Ui.label(cell, "Value", "", px(32), {
			Position = UDim2.fromOffset(0, px(62)),
			Size = UDim2.new(1, 0, 0, px(40)),
		})
		buildBars[info.Id] = { fill = fill, value = value }
	end
end

function Board.init()
	task.spawn(function()
		local rofly = Workspace:WaitForChild("Rofly")
		local rocket = rofly:WaitForChild("Rocket")
		local board = rocket:WaitForChild("Board")
		if board:IsA("BasePart") then
			build(board)
		end
	end)
end

function Board.update(dt: number)
	if not gui then
		return
	end
	local phase = State.phase()
	buildFrame.Visible = phase == "Build"
	mainLabel.Visible = phase ~= "Build"
	subLabel.Visible = true
	local leftText = ""
	local rightText = ""

	if phase == "Join" then
		headLabel.Text = "ROFLY · 행성 붕괴까지"
		mainLabel.Text = Fmt.clock(State.phaseLeft())
		mainLabel.TextColor3 = C.Orange
		subLabel.Text = string.format("탑승 %d/%d명", State.number("JoinedCount"), State.number("PlayerCount"))
		subLabel.TextColor3 = C.Text
	elseif phase == "Build" then
		headLabel.Text = string.format("로켓 조립 · 승무원 %d명 · %s", State.number("CrewCount"), Fmt.clock(State.phaseLeft()))
		for id, bar in pairs(buildBars) do
			local total = State.buildTotal(id)
			-- 막대 길이는 자릿수 기준 (파워가 10배가 될 때마다 한 칸). 가장 센 구성(전설 Lv10 50명)이 약 5.8 자리(데모 1은 시너지 없음)라 6 칸으로 나눔
			local digits = math.log10(1 + total / Config.Flight.RefPower)
			bar.fill.Size = UDim2.fromScale(math.clamp(digits / 6, 0.02, 1), 1)
			bar.value.Text = Fmt.comma(total)
		end
		subLabel.Text = "예상 거리 " .. Fmt.km(State.number("ExpectedKm"))
		subLabel.TextColor3 = C.Yellow
	elseif phase == "Countdown" then
		local left = State.number("LaunchAt") - State.now()
		headLabel.Text = "발사 카운트다운"
		mainLabel.Text = if left > 0 then tostring(math.ceil(left)) else "발사!"
		mainLabel.TextColor3 = if left <= 3 then C.Yellow else C.Text
		local captain = State.text("CaptainName")
		subLabel.Text = if captain ~= "" then "선장 " .. captain else "자동 발사"
		subLabel.TextColor3 = C.Text
	elseif phase == "Flight" then
		local f = State.flight
		local index = Route.stageIndex(f.km)
		headLabel.Text = Route.stage(index).Name
		mainLabel.Text = Fmt.km(f.km)
		mainLabel.TextColor3 = if State.flag("Crisis") then C.Red else C.Cyan
		subLabel.Text = "속도 " .. Fmt.speed(f.speed)
		subLabel.TextColor3 = C.Text
		local combo = State.number("Combo")
		leftText = if combo > 0 then string.format("콤보 x%d", combo) else ""
		local eta = State.number("Eta")
		rightText = if eta < Config.Crisis.EtaLimit then string.format("충격파 %d초", math.ceil(eta)) else ""
	else
		local km = State.number("Km")
		headLabel.Text = if State.flag("Escaped") then "탈출 성공" else "비행 종료"
		mainLabel.Text = Fmt.km(km)
		mainLabel.TextColor3 = C.Yellow
		subLabel.Text = Route.arrivalName(km, State.flag("Escaped"))
		subLabel.TextColor3 = C.Text
	end
	leftLabel.Text = leftText
	rightLabel.Text = rightText
	ChaseView.update(dt)
end

return Board
