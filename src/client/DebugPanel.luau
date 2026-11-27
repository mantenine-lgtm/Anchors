-- 디버그 패널 (데모 전용). Studio 에서 실행 중이거나 게임 주인에게만 보입니다.
-- 버튼을 누르면 서버에 명령을 보내고, 서버가 권한을 다시 확인합니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fever = require(Shared:WaitForChild("Fever"))
local Net = require(Shared:WaitForChild("Net"))
local Planets = require(Shared:WaitForChild("Planets"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local DebugPanel = {}

local C = Ui.Colors
local CREW_SIZES = { 1, 4, 10, 20, 50 }

local toggleButton: TextButton
local panel: Frame
local skillButton: TextButton
local crewButton: TextButton
local gearButton: TextButton
local feverButton: TextButton
local planetButton: TextButton
local open = false

local function send(command: string, value: any?)
	State.emit("Sound", "Press")
	Net.event("Debug"):FireServer(command, value)
end

local function skillName(id: string): string
	for _, skill in ipairs(Config.Bots.Skills) do
		if skill.Id == id then
			return skill.Name
		end
	end
	return id
end

local function gearName(id: string): string
	for _, preset in ipairs(Config.Gear.Presets) do
		if preset.Id == id then
			return preset.Name
		end
	end
	return id
end

-- 목록에서 지금 값 다음 것을 고름 (끝이면 처음으로)
local function nextIn(list: { any }, current: any, key: string?): any
	for i, item in ipairs(list) do
		local value = if key then item[key] else item
		if value == current then
			return list[i % #list + 1]
		end
	end
	return list[1]
end

function DebugPanel.init()
	local _, root = Ui.screen("RoflyDebug", 20)
	toggleButton = Ui.button(root, "DebugToggle", "디버그", 17, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 108),
		Size = UDim2.fromOffset(150, 36),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	Ui.stroke(toggleButton, C.Purple, 2, 0)

	local rows = 12
	-- 줄 간격 28, 버튼 높이 25: 판의 아래 끝이 499 라서 비행 중 미션 점프 버튼(Key_Jump, 위 끝 510)을 덮지 않음
	-- (부품 피버 줄을 더하며 30·27 에서 줄임). 발사장에서 보이는 엔진 기본 터치 점프 버튼은 화면 높이 500~720 픽셀인
	-- 태블릿에서 위쪽이 조금 가려질 수 있음 (디버그 패널은 개발용이고 닫을 수 있어 그대로 둠)
	local rowPitch = 28
	local rowHeight = 25
	panel = Ui.panel(root, "DebugPanel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 150),
		Size = UDim2.fromOffset(300, 8 + (rows - 1) * rowPitch + rowHeight + 8),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Ui.stroke(panel, C.Purple, 2, 0)

	local row = 0
	local function add(name: string, text: string, action: () -> ()): TextButton
		local button = Ui.button(panel, name, text, 17, C.PanelLight, {
			Position = UDim2.fromOffset(8, 8 + row * rowPitch),
			Size = UDim2.new(1, -16, 0, rowHeight),
		})
		row += 1
		button.Activated:Connect(action)
		return button
	end

	add("DebugSkip", "다음 단계로 넘기기", function()
		send("Skip")
	end)
	add("DebugTicket", "티켓 +1", function()
		send("Ticket")
	end)
	add("DebugCoins", string.format("코인 +%d", Config.Debug.CoinGrant), function()
		send("Coins")
	end)
	add("DebugPartLevels", string.format("내 부품 레벨 +%d", Config.Progress.DebugLevels), function()
		send("PartLevels")
	end)
	add("DebugCrisis", "위기 구간으로 건너뛰기", function()
		send("Crisis")
	end)
	add("DebugBotRescue", "봇이 구원 연료 사용", function()
		send("BotRescue")
	end)
	skillButton = add("DebugBotSkill", "", function()
		local nextSkill = nextIn(Config.Bots.Skills, State.text("OptBotSkill"), "Id")
		send("BotSkill", nextSkill.Id)
	end)
	crewButton = add("DebugBotFill", "", function()
		send("BotFill", nextIn(CREW_SIZES, State.number("OptBotFill")))
	end)
	gearButton = add("DebugGear", "", function()
		local nextGear = nextIn(Config.Gear.Presets, State.text("OptGear"), "Id")
		send("Gear", nextGear.Id)
	end)
	feverButton = add("DebugFever", "", function()
		local nextMode = nextIn(Config.Fever.Modes, Fever.mode(State.text("OptFever")), "Id")
		send("Fever", nextMode.Id)
	end)
	planetButton = add("DebugPlanet", "", function()
		send("Planet")
	end)
	add("DebugMetrics", "지표 출력 (Output 창)", function()
		send("Metrics")
	end)

	toggleButton.Activated:Connect(function()
		open = not open
		State.emit("Sound", "Press")
	end)
end

function DebugPanel.update(_dt: number)
	local allowed = State.canDebug()
	toggleButton.Visible = allowed
	panel.Visible = allowed and open
	if panel.Visible then
		skillButton.Text = "봇 실력: " .. skillName(State.text("OptBotSkill"))
		crewButton.Text = string.format("승무원 수: %d명 (다음 판부터)", State.number("OptBotFill"))
		gearButton.Text = "장비: " .. gearName(State.text("OptGear")) .. " (다음 판부터)"
		feverButton.Text = "부품 피버: " .. Fever.modeName(State.text("OptFever"))
		planetButton.Text = "행성 바꾸기 (지금: " .. Planets.get(State.text("Planet")).Name .. ")"
	end
end

return DebugPanel
