-- 선실 전광판: 외창 위의 큰 화면. 로켓 안에서 속도·거리·궤적을 보여 줍니다.
-- 화면은 클라이언트가 만들어 서버의 Board 파트 앞면에 붙입니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Route = require(Shared:WaitForChild("Route"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local Board = {}

local C = Ui.Colors
local PIXELS_PER_STUD = 30
local WIDTH = Config.World.BoardWidth * PIXELS_PER_STUD
local HEIGHT = Config.World.BoardHeight * PIXELS_PER_STUD

local gui: SurfaceGui? = nil
local headLabel: TextLabel
local mainLabel: TextLabel
local subLabel: TextLabel
local leftLabel: TextLabel
local rightLabel: TextLabel
local routeFrame: Frame
local rocketMark: Frame
local waveMark: Frame
local recordMark: Frame
local buildFrame: Frame
local buildBars: { [string]: { fill: Frame, value: TextLabel } } = {}

local ROUTE_WIDTH = WIDTH - 80

local function mark(name: string, color: Color3, width: number, height: number): Frame
	return Ui.frame(routeFrame, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
	})
end

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
	-- 화면에서는 이 그림이 1/3 쯤으로 줄어 보이므로 글자를 크게 씀
	headLabel = Ui.label(back, "Head", "", 44, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 52),
		TextColor3 = C.Dim,
	})
	mainLabel = Ui.bigLabel(back, "Main", "", 128, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 58 / HEIGHT),
		Size = UDim2.new(1, 0, 0, 136),
		TextColor3 = C.Cyan,
	})
	subLabel = Ui.label(back, "Sub", "", 40, {
		Position = UDim2.fromOffset(0, 196),
		Size = UDim2.new(1, 0, 0, 48),
	})
	leftLabel = Ui.label(back, "Left", "", 40, {
		Position = UDim2.fromOffset(28, 10),
		Size = UDim2.fromOffset(280, 48),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Green,
	})
	rightLabel = Ui.label(back, "Right", "", 40, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 10),
		Size = UDim2.fromOffset(320, 48),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Orange,
	})

	-- 궤적: 루트 전체를 로그 눈금으로 그린 선. 스테이지 경계마다 눈금.
	-- 파랑 = 로켓, 빨강 = 충격파, 노랑 = 이 서버 최고 기록
	routeFrame = Ui.frame(back, "Route", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(ROUTE_WIDTH, 60),
	})
	Ui.frame(routeFrame, "Line", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = C.Line,
		BackgroundTransparency = 0,
	})
	for i = 1, Route.stageCount() do
		local x = Route.logPosition(Route.stage(i).EndKm)
		Ui.frame(routeFrame, "Tick" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromOffset(4, 28),
			BackgroundColor3 = C.Line,
			BackgroundTransparency = 0,
		})
	end
	recordMark = mark("Record", C.Yellow, 6, 56)
	waveMark = mark("Wave", C.Red, 14, 44)
	rocketMark = mark("Rocket", C.Cyan, 20, 50)

	-- 빌드: 부품 종류별 파워 막대
	buildFrame = Ui.frame(back, "Build", {
		Position = UDim2.fromOffset(40, 66),
		Size = UDim2.new(1, -80, 0, 126),
		Visible = false,
	})
	local types = Config.Parts.Types
	local column = (WIDTH - 80) / #types
	for i, info in ipairs(types) do
		local cell = Ui.frame(buildFrame, info.Id, {
			Position = UDim2.fromOffset((i - 1) * column, 0),
			Size = UDim2.fromOffset(column - 12, 126),
		})
		Ui.label(cell, "Name", info.Name, 30, {
			Size = UDim2.new(1, 0, 0, 38),
			TextColor3 = C.Dim,
		})
		local _, fill = Ui.bar(cell, "Bar", C.Cyan, {
			Position = UDim2.fromOffset(0, 44),
			Size = UDim2.new(1, 0, 0, 30),
		})
		local value = Ui.label(cell, "Value", "", 38, {
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 0, 44),
		})
		buildBars[info.Id] = { fill = fill, value = value }
	end
end

local function setRoute(visible: boolean)
	routeFrame.Visible = visible
end

local function placeMark(markFrame: Frame, km: number, visible: boolean)
	markFrame.Visible = visible
	if visible then
		markFrame.Position = UDim2.fromScale(Route.logPosition(km), 0.5)
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

function Board.update(_dt: number)
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
		setRoute(false)
		headLabel.Text = "ROFLY · 행성 붕괴까지"
		mainLabel.Text = Fmt.clock(State.phaseLeft())
		mainLabel.TextColor3 = C.Orange
		subLabel.Text = string.format("탑승 %d/%d명", State.number("JoinedCount"), State.number("PlayerCount"))
		subLabel.TextColor3 = C.Text
	elseif phase == "Build" then
		setRoute(false)
		headLabel.Text = string.format("로켓 조립 · 승무원 %d명 · %s", State.number("CrewCount"), Fmt.clock(State.phaseLeft()))
		local info = State.build()
		if info then
			for id, bar in pairs(buildBars) do
				local total = info.totals[id]
				if type(total) ~= "number" then
					total = 0
				end
				-- 막대 길이는 자릿수 기준 (파워가 10배가 될 때마다 한 칸)
				local digits = math.log10(1 + total / Config.Flight.RefPower)
				bar.fill.Size = UDim2.fromScale(math.clamp(digits / 5, 0.02, 1), 1)
				bar.value.Text = Fmt.comma(total)
			end
		end
		subLabel.Text = "예상 거리 " .. Fmt.km(State.number("ExpectedKm"))
		subLabel.TextColor3 = C.Yellow
	elseif phase == "Countdown" then
		setRoute(false)
		local left = State.number("LaunchAt") - State.now()
		headLabel.Text = "발사 카운트다운"
		mainLabel.Text = if left > 0 then tostring(math.ceil(left)) else "발사!"
		mainLabel.TextColor3 = if left <= 3 then C.Yellow else C.Text
		local captain = State.text("CaptainName")
		subLabel.Text = if captain ~= "" then "선장 " .. captain else "자동 발사"
		subLabel.TextColor3 = C.Text
	elseif phase == "Flight" then
		setRoute(true)
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
		placeMark(rocketMark, f.km, true)
		placeMark(waveMark, f.waveKm, true)
		placeMark(recordMark, State.number("BestKm"), State.number("BestKm") > 0)
	else
		setRoute(true)
		local km = State.number("Km")
		headLabel.Text = if State.flag("Escaped") then "탈출 성공" else "비행 종료"
		mainLabel.Text = Fmt.km(km)
		mainLabel.TextColor3 = C.Yellow
		subLabel.Text = Route.stage(Route.stageIndex(km)).Name
		subLabel.TextColor3 = C.Text
		placeMark(rocketMark, km, true)
		placeMark(waveMark, State.number("WaveKm"), true)
		placeMark(recordMark, State.number("BestKm"), State.number("BestKm") > 0)
	end
	leftLabel.Text = leftText
	rightLabel.Text = rightText
end

return Board
