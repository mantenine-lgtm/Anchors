-- 방향 미션: 화면에 뜬 순서대로 방향 버튼(+점프)을 누릅니다.
-- 입력: 화면 버튼(터치·마우스), 키보드(방향키·WASD·스페이스), 게임패드(십자키·A).
-- 결과는 팀 전체 성공률만 보여 주고, 내 결과는 나에게만 보입니다.
-- 승무원은 선실을 걸어다니다가, 미션이 뜨면 입력을 끝낼 때까지(또는 시간이 끝날 때까지) 그 자리에 멈춥니다
-- (State.missionInput → CameraRig 가 걷기·점프를 잠금). 터치 기기는 그동안만 이동 스틱 대신 미션 버튼이 뜹니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Net = require(Shared:WaitForChild("Net"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local MissionUi = {}

local C = Ui.Colors

local KEY_MAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.W] = "Up",
	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.Right] = "Right",
	[Enum.KeyCode.D] = "Right",
	[Enum.KeyCode.DPadRight] = "Right",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.S] = "Down",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.Space] = "Jump",
	[Enum.KeyCode.ButtonA] = "Jump",
}

type Mission = {
	id: number,
	sequence: { string },
	limit: number,
	closeAt: number,
	index: number, -- 다음에 눌러야 할 칸
	touched: boolean,
	finished: boolean, -- 입력이 끝났거나 시간이 지남
	success: boolean,
	slots: { Frame },
}

local root: Frame
local panel: Frame
local titleLabel: TextLabel
local slotRow: Frame
local timerBack: Frame
local timerFill: Frame
local resultLabel: TextLabel
local ownLabel: TextLabel
local padFrame: Frame
local jumpButton: TextButton

local mission: Mission? = nil
local hideAt = 0 -- 이 시각(os.clock)이 지나면 판을 숨김
local lastCombo = 0
local usedTouch = false -- 화면을 한 번이라도 터치했는지

-- 화면 버튼(방향·점프)은 터치 기기에서만 보여 줌. 키보드가 있으면 화면을 가리지 않게 숨김.
local function wantsPad(): boolean
	return usedTouch or UserInputService.TouchEnabled or not UserInputService.KeyboardEnabled
end

local function promptText(): string
	if wantsPad() then
		return "순서대로 누르세요!"
	end
	return "순서대로 누르세요! (방향키 · 점프는 스페이스)"
end

local SLOT = 80
local GAP = 12

local function slotColor(slot: Frame, color: Color3, mark: Color3)
	slot.BackgroundColor3 = color
	local arrow = slot:FindFirstChild("Arrow")
	if arrow then
		Ui.tint(arrow, mark)
	end
	local text = slot:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.TextColor3 = mark
	end
end

local function resetSlots(m: Mission)
	for _, slot in ipairs(m.slots) do
		slotColor(slot, C.PanelLight, C.Text)
	end
end

local function buildSlots(sequence: { string }): { Frame }
	slotRow:ClearAllChildren()
	local count = #sequence
	local width = count * SLOT + (count - 1) * GAP
	slotRow.Size = UDim2.fromOffset(width, SLOT)
	local slots: { Frame } = {}
	for i, key in ipairs(sequence) do
		local slot = Ui.frame(slotRow, "Slot" .. i, {
			Position = UDim2.fromOffset((i - 1) * (SLOT + GAP), 0),
			Size = UDim2.fromOffset(SLOT, SLOT),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0,
		})
		Ui.corner(slot, 12)
		if key == "Jump" then
			Ui.label(slot, "Text", "점프", 26, {})
		else
			Ui.arrow(slot, key, C.Text)
		end
		slots[i] = slot
	end
	return slots
end

local function showPanel(seconds: number)
	panel.Visible = true
	hideAt = os.clock() + seconds
end

local function press(key: string)
	local m = mission
	if not m or m.finished or State.role() ~= "Crew" then
		return
	end
	if State.now() > m.closeAt then
		return
	end
	if not m.touched then
		m.touched = true
		Net.event("MissionInput"):FireServer(m.id, "touch")
	end
	if m.sequence[m.index] == key then
		slotColor(m.slots[m.index], C.Green, C.Black)
		m.index += 1
		State.emit("Sound", "Press")
		if m.index > #m.sequence then
			m.finished = true
			m.success = true
			State.missionInput = false -- 다 눌렀으면 바로 다시 걸을 수 있게
			Net.event("MissionInput"):FireServer(m.id, "done", m.sequence)
			titleLabel.Text = "입력 완료! 판정을 기다립니다"
			titleLabel.TextColor3 = C.Green
		end
	else
		State.emit("Sound", "Wrong")
		if Config.Mission.WrongInputResets then
			m.index = 1
			resetSlots(m)
			titleLabel.Text = "틀렸습니다! 처음부터 다시"
			titleLabel.TextColor3 = C.Orange
		end
	end
end

local function onMissionStart(info: any)
	if type(info) ~= "table" or type(info.sequence) ~= "table" then
		return
	end
	lastCombo = State.number("Combo")
	if State.role() ~= "Crew" then
		mission = nil
		return
	end
	local sequence: { string } = {}
	for i, key in ipairs(info.sequence) do
		sequence[i] = tostring(key)
	end
	mission = {
		id = info.id,
		sequence = sequence,
		limit = info.limit,
		closeAt = info.closeAt,
		index = 1,
		touched = false,
		finished = false,
		success = false,
		slots = buildSlots(sequence),
	}
	State.missionInput = true
	titleLabel.Text = promptText()
	titleLabel.TextColor3 = C.Yellow
	slotRow.Visible = true
	resultLabel.Visible = false
	ownLabel.Visible = false
	timerBack.Visible = true
	showPanel(info.limit + 3)
	State.emit("Sound", "Countdown")
end

local function onMissionResult(info: any)
	if type(info) ~= "table" then
		return
	end
	local rate: number = info.rate
	local combo: number = info.combo
	mission = nil
	slotRow.Visible = false
	timerBack.Visible = false

	local text = "팀 성공률 " .. Fmt.percent(rate)
	if info.perfect then
		text = "전원 성공! " .. text
	end
	if combo > 0 then
		text ..= string.format(" · 콤보 x%d", combo)
	elseif lastCombo > 0 then
		text ..= " · 콤보 끊김"
	end
	titleLabel.Text = "미션 결과"
	titleLabel.TextColor3 = C.Dim
	resultLabel.Text = text
	resultLabel.TextColor3 = if rate >= Config.Mission.ComboRule then C.Green else C.Orange
	resultLabel.Visible = true

	local own = info.own
	if own == "success" then
		ownLabel.Text = "나: 성공"
		ownLabel.TextColor3 = C.Green
	elseif own == "fail" then
		ownLabel.Text = "나: 실패"
		ownLabel.TextColor3 = C.Red
	elseif own == "excluded" then
		ownLabel.Text = "입력이 없어 판정에서 빠졌습니다 (코인 절반)"
		ownLabel.TextColor3 = C.Orange
	else
		ownLabel.Text = ""
	end
	-- 부품 피버 (Nick 11-28): 이번 판정으로 피버에 들어간 내 부품 수
	local feverMine = if type(info.feverMine) == "number" then info.feverMine else 0
	if feverMine > 0 and (own == "success" or own == "fail") then
		ownLabel.Text ..= string.format(" · 내 부품 %d개 피버!", feverMine)
	end
	ownLabel.Visible = ownLabel.Text ~= ""
	showPanel(Config.Mission.ResultShowSeconds)

	State.emit("MissionFx", rate, combo, info.perfect == true)
	if rate >= Config.Mission.ComboRule then
		State.emit("Sound", if combo >= 2 then "Combo" else "MissionSuccess")
	end
end

local function padButton(name: string, direction: string, position: UDim2)
	local button = Ui.button(padFrame, name, "", 20, C.PanelLight, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(84, 84),
		BackgroundTransparency = 0.15,
	})
	Ui.stroke(button, C.Line, 2, 0)
	Ui.arrow(button, direction, C.Text)
	button.MouseButton1Down:Connect(function()
		press(direction)
	end)
end

function MissionUi.init()
	local _, base = Ui.screen("RoflyMission", 12)
	root = base

	panel = Ui.panel(root, "MissionPanel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(600, 162),
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	Ui.stroke(panel, C.Line, 2, 0)
	titleLabel = Ui.label(panel, "Title", "", 20, {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = C.Yellow,
	})
	slotRow = Ui.frame(panel, "Slots", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(0, SLOT),
	})
	local back, fill = Ui.bar(panel, "Timer", C.Yellow, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 12),
	})
	back.Visible = false
	timerBack = back
	timerFill = fill
	resultLabel = Ui.label(panel, "Result", "", 34, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 44),
		Visible = false,
	})
	ownLabel = Ui.label(panel, "Own", "", 24, {
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 32),
		Visible = false,
	})

	-- 방향 버튼 (왼쪽 아래)과 점프 버튼 (오른쪽 아래)
	padFrame = Ui.frame(root, "Pad", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -24),
		Size = UDim2.fromOffset(264, 264),
		Visible = false,
	})
	padButton("Key_Up", "Up", UDim2.fromScale(0.5, 0.17))
	padButton("Key_Left", "Left", UDim2.fromScale(0.17, 0.5))
	padButton("Key_Right", "Right", UDim2.fromScale(0.83, 0.5))
	padButton("Key_Down", "Down", UDim2.fromScale(0.5, 0.83))

	jumpButton = Ui.button(root, "Key_Jump", "점프", 30, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -60),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = jumpButton })
	Ui.stroke(jumpButton, C.Line, 2, 0)
	jumpButton.MouseButton1Down:Connect(function()
		press("Jump")
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			usedTouch = true
		end
		local key = KEY_MAP[input.KeyCode]
		if key and not State.typing() then
			press(key)
		end
	end)

	State.on("MissionStart", onMissionStart)
	State.on("MissionResult", onMissionResult)
	State.on("Phase", function(phase: string)
		if phase ~= "Flight" then
			mission = nil
			panel.Visible = false
		end
	end)
end

function MissionUi.update(_dt: number)
	local flying = State.phase() == "Flight"
	local crew = State.role() == "Crew"

	local m = mission
	if m then
		local left = m.closeAt - State.now()
		timerFill.Size = UDim2.fromScale(math.clamp(left / m.limit, 0, 1), 1)
		timerFill.BackgroundColor3 = if left < m.limit * 0.3 then C.Red else C.Yellow
		if left <= 0 and not m.finished then
			m.finished = true
			titleLabel.Text = "시간 초과"
			titleLabel.TextColor3 = C.Red
		end
	end
	if panel.Visible and (os.clock() > hideAt or not flying) then
		panel.Visible = false
		mission = nil
	end

	-- 내 입력을 받는 동안만 걷기를 잠그고(CameraRig) 화면 버튼을 보여 줌
	local active = mission ~= nil and not (mission :: Mission).finished and flying and crew
	State.missionInput = active
	local showPad = active and wantsPad()
	padFrame.Visible = showPad
	jumpButton.Visible = showPad
end

return MissionUi
