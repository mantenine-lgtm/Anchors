-- 방향 미션: 화면에 뜬 순서대로 방향 버튼(+점프)을 누릅니다.
-- 입력: 화면 버튼(터치·마우스), 키보드(방향키·WASD·스페이스), 게임패드(십자키·A).
-- 결과는 팀 전체 성공률만 보여 주고, 내 결과는 나에게만 보입니다.
-- 승무원은 선실을 걸어다니다가, 미션이 뜨면 입력을 끝낼 때까지(또는 시간이 끝날 때까지) 그 자리에 멈춥니다
-- (State.missionInput → CameraRig 가 걷기·점프를 잠금). 터치 기기는 그동안만 이동 스틱 대신 미션 버튼이 뜹니다.
--
-- 연타 미션(Config.Tap, Nick 11-28): 화면 양옆에 ← · → 화살표가 그려진 큰 '연타!' 버튼 두 개가 뜨고(양손 엄지용), 정해진
-- 시간 동안 그 버튼이나 키보드 ← → 키(A·D, 게임패드 십자키 좌우도 됨. 스페이스는 안 셈)를 빠르게 누릅니다. ← 는 왼쪽 버튼,
-- → 는 오른쪽 버튼을 누른 것과 같습니다. 내가 누르면 그 버튼이 눌려 들어가며 금빛 고리가 퍼지고, 다른 사람이 누른 만큼
-- (서버가 알리는 합계가 오른 만큼)은 두 버튼 위에 하늘색 작은 고리가 톡톡 터지며 버튼이 들썩입니다.
-- 미션 입력 중에는 ← → 키가 기본 카메라를 돌리지 않게 막습니다(연타로 마구 누르면 화면이 흔들리므로).
-- 누른 횟수는 바로 화면에 올리고, 서버에는 모아서 SendInterval 초마다 누적 횟수만 보냅니다(원격 호출이 몰리지 않게).
-- 아래 미션 판의 게이지는 로켓 전체 연타 합계의 단계(합계가 두 배가 될 때마다 1단계)이고, 단계가 높을수록 그 미션의 가속이 커집니다.
-- 이펙트는 고리 Frame 몇 개를 돌려 쓰고 트윈 없이 매 프레임 크기만 바꿔서 폰에서도 가볍습니다.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Net = require(Shared:WaitForChild("Net"))
local TapMission = require(Shared:WaitForChild("TapMission"))

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

-- 연타 미션 (내 화면)
type Tap = {
	id: number,
	limit: number,
	closeAt: number,
	minTaps: number,
	count: number, -- 내가 누른 횟수 (누르면 바로 늘어남)
	sent: number, -- 서버에 마지막으로 보낸 누적 횟수
	sentAt: number, -- 마지막으로 보낸 때 (os.clock)
	finished: boolean, -- 시간이 끝남
	shown: number, -- 화면에 보이는 로켓 전체 합계 (줄어들지 않음)
	level: number, -- 화면에 보이는 단계 (정수)
	others: number, -- 지금까지 본 다른 사람들의 횟수 (서버 합계 − 내가 보낸 횟수, 줄어들지 않음)
}

-- 연타 버튼 위에 퍼지는 고리 하나 (돌려 씀)
type Ring = {
	frame: Frame,
	stroke: UIStroke,
	born: number, -- 생긴 때 (os.clock)
	life: number, -- 사라지기까지 초
	from: number, -- 처음 지름 (버튼 지름에 대한 비율)
	to: number, -- 마지막 지름
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
local tapBox: Frame
local tapFill: Frame
local tapGaugeStroke: UIStroke
local tapTotalLabel: TextLabel
local tapMineLabel: TextLabel
local tapBoostLabel: TextLabel
-- 연타 버튼 하나 (양옆에 두 개)
type TapPad = {
	button: TextButton,
	scale: UIScale,
	stroke: UIStroke,
	word: TextLabel,
	count: TextLabel,
	hint: TextLabel,
	rings: { Ring },
	ringNext: number,
	myDepth: number, -- 내가 누르면 1, 곧 0 으로 (버튼이 눌려 들어가고 금빛으로 번쩍)
	otherDepth: number, -- 다른 사람이 누르면 OTHER_DEPTH, 곧 0 으로 (버튼이 살짝 들썩)
	lastMyRing: number,
}
local tapPads: { TapPad } = {} -- 1 = 왼쪽(TapLeft), 2 = 오른쪽(TapRight)
local TAP_KEY_SIDE: { [string]: number } = { Left = 1, Right = 2 } -- 연타 미션에서 세는 키(KEY_MAP 의 이름) -> 누른 버튼
local TAP_KEY_HINT = { "또는 ← 키", "또는 → 키" }
local SINK_ACTION = "RoflyMissionArrowKeys"
local sinkingKeys = false

local mission: Mission? = nil
local tap: Tap? = nil
local hideAt = 0 -- 이 시각(os.clock)이 지나면 판을 숨김
local lastCombo = 0
local usedTouch = false -- 화면을 한 번이라도 터치했는지
local appear = 1 -- 버튼이 뜰 때 0 에서 1 로 (작게 시작해 커지며 나타남)
local otherQueue = 0 -- 다른 사람이 누른 횟수 중 아직 이펙트로 안 보여 준 것
local otherFrac = 0
local tapFlash = 0 -- 단계가 오를 때 1, 곧 0 으로 (게이지 테두리가 번쩍)
local lastTapSound = 0
local lastLevelSound = 0
local lastOtherRing = 0
local TAP_SOUND_GAP = 0.08 -- 누르는 소리는 이 간격보다 자주 내지 않음
local LEVEL_SOUND_GAP = 0.5
local RING_COUNT = 7 -- 버튼마다 돌려 쓰는 고리 수
local MY_RING_GAP = 0.03 -- 내 고리는 이 간격보다 자주 만들지 않음
local OTHER_RING_GAP = 0.05 -- 다른 사람 고리는 1초에 20개까지 (나머지는 버튼 들썩임으로만)
local OTHER_DEPTH = 0.55

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
local TAP_BUTTON = 200 -- 양옆 연타 버튼 지름 (기준 화면 픽셀)
local TAP_BASE = Color3.fromRGB(44, 36, 16) -- 연타 버튼 바탕 (어두운 금색)

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

-- ------------------------------------------------------------ 연타 미션
local function tapPrompt(): string
	if wantsPad() then
		return "연타! 양옆 버튼을 다 같이 빠르게!"
	end
	return "연타! ← → 키나 양옆 버튼을 빠르게!"
end

-- 고리 하나를 띄움. mine 이면 버튼 둘레에서 크게 퍼지는 금빛 고리, 아니면 버튼 위 아무 데서나 톡 터지는 하늘색 작은 고리
local function ring(pad: TapPad, mine: boolean)
	local r = pad.rings[pad.ringNext]
	if r == nil then
		return
	end
	pad.ringNext = pad.ringNext % #pad.rings + 1
	r.born = os.clock()
	if mine then
		r.frame.Position = UDim2.fromScale(0.5, 0.5)
		r.life, r.from, r.to = 0.35, 1.0, 1.5
		r.stroke.Color = C.Yellow
		r.stroke.Thickness = 5
	else
		local angle = math.random() * math.pi * 2
		local distance = math.random() * 0.32
		r.frame.Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance)
		r.life, r.from, r.to = 0.4, 0.16, 0.42
		r.stroke.Color = C.Cyan
		r.stroke.Thickness = 3
	end
	r.frame.Size = UDim2.fromScale(r.from, r.from)
	r.stroke.Transparency = 0
	r.frame.Visible = true
end

local function updateRings()
	local clock = os.clock()
	for _, pad in ipairs(tapPads) do
		for _, r in ipairs(pad.rings) do
			if r.frame.Visible then
				local k = (clock - r.born) / r.life
				if k >= 1 then
					r.frame.Visible = false
				else
					local eased = 1 - (1 - k) * (1 - k)
					local d = r.from + (r.to - r.from) * eased
					r.frame.Size = UDim2.fromScale(d, d)
					r.stroke.Transparency = k
				end
			end
		end
	end
end

-- 서버에 누적 횟수를 보냄 (바뀐 것이 있을 때만)
local function sendTaps(t: Tap)
	if t.count == t.sent then
		return
	end
	t.sent = t.count
	t.sentAt = os.clock()
	Net.event("MissionInput"):FireServer(t.id, "tap", t.count)
end

-- 로켓 전체 합계: 서버가 알린 합계(내가 보낸 횟수까지 들어 있음) + 아직 안 보낸 내 횟수. 화면에서는 줄어들지 않게.
-- 다른 사람들의 횟수(서버 합계 − 내가 보낸 횟수)가 오르면 그만큼을 '다른 사람 누름' 이펙트로 보여 줄 몫에 더함
local function tapTotal(t: Tap): number
	local server = if State.number("TapId") == t.id then State.number("TapTotal") else 0
	local others = server - t.sent
	if others > t.others then
		otherQueue += others - t.others
		t.others = others
	end
	t.shown = math.max(t.shown, server + (t.count - t.sent))
	return t.shown
end

local function refreshTap(t: Tap)
	local total = tapTotal(t)
	local level = TapMission.level(total)
	tapFill.Size = UDim2.fromScale(math.clamp(level / Config.Tap.MaxLevel, 0, 1), 1)
	tapTotalLabel.Text = "합계 " .. Fmt.comma(total) .. "회"
	tapBoostLabel.Text = string.format("%d단계 · 가속 ×%.2f", math.floor(level), TapMission.factor(total))
	local mine = tostring(t.count)
	for _, pad in ipairs(tapPads) do
		pad.count.Text = mine
	end
	if t.count >= t.minTaps then
		tapMineLabel.Text = string.format("나 %d회 ✓", t.count)
		tapMineLabel.TextColor3 = C.Green
	else
		tapMineLabel.Text = string.format("나 %d/%d", t.count, t.minTaps)
		tapMineLabel.TextColor3 = C.Text
	end
	local whole = math.floor(level)
	if whole > t.level then
		t.level = whole
		tapFlash = 1
		if os.clock() - lastLevelSound >= LEVEL_SOUND_GAP then
			lastLevelSound = os.clock()
			State.emit("Sound", "Combo")
		end
	end
end

-- side = 누른 버튼 (1 왼쪽, 2 오른쪽. 키보드 ← 는 왼쪽, → 는 오른쪽)
local function pressTap(side: number)
	local t = tap
	if not t or t.finished or State.role() ~= "Crew" then
		return
	end
	if State.now() > t.closeAt then
		return
	end
	t.count += 1
	local pad = tapPads[side]
	local clock = os.clock()
	if pad then
		pad.myDepth = 1
		if clock - pad.lastMyRing >= MY_RING_GAP then
			pad.lastMyRing = clock
			ring(pad, true)
		end
	end
	if clock - lastTapSound >= TAP_SOUND_GAP then
		lastTapSound = clock
		State.emit("Sound", "Press")
	end
	refreshTap(t)
end

local function press(key: string)
	if tap then
		-- 연타 미션: 키보드·게임패드는 왼쪽·오른쪽 키만 셈 (누른 쪽 버튼이 눌림). 스페이스·위·아래는 안 셈
		local side = TAP_KEY_SIDE[key]
		if side then
			pressTap(side)
		end
		return
	end
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

local function startTap(info: any)
	if type(info.id) ~= "number" or type(info.limit) ~= "number" or type(info.closeAt) ~= "number" then
		return
	end
	local t: Tap = {
		id = info.id,
		limit = info.limit,
		closeAt = info.closeAt,
		minTaps = if type(info.minTaps) == "number" then info.minTaps else Config.Tap.MinTaps,
		count = 0,
		sent = 0,
		sentAt = os.clock(),
		finished = false,
		shown = 0,
		level = 0,
		others = 0,
	}
	tap = t
	otherQueue = 0
	otherFrac = 0
	appear = 0
	for side, pad in ipairs(tapPads) do
		pad.myDepth = 0
		pad.otherDepth = 0
		pad.hint.Text = if wantsPad() then "" else TAP_KEY_HINT[side]
	end
	State.missionInput = true
	titleLabel.Text = tapPrompt()
	titleLabel.TextColor3 = C.Yellow
	slotRow.Visible = false
	tapBox.Visible = true
	resultLabel.Visible = false
	ownLabel.Visible = false
	timerBack.Visible = true
	tapFlash = 0
	refreshTap(t)
	showPanel(info.limit + 3)
	State.emit("Sound", "Countdown")
end

local function onMissionStart(info: any)
	if type(info) ~= "table" then
		return
	end
	if info.kind ~= "tap" and type(info.sequence) ~= "table" then
		return
	end
	lastCombo = State.number("Combo")
	tap = nil
	if State.role() ~= "Crew" then
		mission = nil
		return
	end
	if info.kind == "tap" then
		mission = nil
		startTap(info)
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
	tapBox.Visible = false
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
	local isTap = info.kind == "tap"
	mission = nil
	tap = nil
	slotRow.Visible = false
	tapBox.Visible = false
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
	if isTap then
		-- 연타 미션: 큰 줄은 로켓 전체 연타 합계와 가속 배율, 제목 줄에 팀 성공률·콤보
		local total = if type(info.tapTotal) == "number" then info.tapTotal else 0
		local factor = if type(info.tapFactor) == "number" then info.tapFactor else 1
		local level = if type(info.tapLevel) == "number" then info.tapLevel else 0
		titleLabel.Text = string.format("연타 %d단계 · %s", math.floor(level), text)
		titleLabel.TextColor3 = C.Dim
		resultLabel.Text = string.format("연타 %s회 · 가속 ×%.2f", Fmt.comma(total), factor)
	else
		titleLabel.Text = "미션 결과"
		titleLabel.TextColor3 = C.Dim
		resultLabel.Text = text
	end
	resultLabel.TextColor3 = if rate >= Config.Mission.ComboRule then C.Green else C.Orange
	resultLabel.Visible = true

	local own = info.own
	local taps = if isTap and type(info.tapMine) == "number" then info.tapMine else nil
	if own == "success" then
		ownLabel.Text = "나: 성공" .. (if taps then string.format(" · %d회", taps) else "")
		ownLabel.TextColor3 = C.Green
	elseif own == "fail" then
		-- 연타 미션은 몇 번 모자랐는지 (성공 기준 MinTaps)
		ownLabel.Text = "나: 실패" .. (if taps then string.format(" · %d/%d회", taps, Config.Tap.MinTaps) else "")
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

-- 연타 버튼 하나: 둥글고 큼. 여러 손가락이 따로 눌러도 하나하나 세도록 버튼의 InputBegan(누를 때마다 따로 옴)을 씀.
-- 글자·숫자·고리는 모두 버튼의 자식이라 누르는 것을 막지 않음
local function buildTapPad(name: string, side: number, direction: string, position: UDim2): TapPad
	local button = Ui.button(root, name, "", 20, TAP_BASE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(TAP_BUTTON, TAP_BUTTON),
		BackgroundTransparency = 0.08,
		AutoButtonColor = false,
		Visible = false,
	})
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = button })
	local stroke = Ui.stroke(button, C.Yellow, 4, 0)
	local scale = Ui.make("UIScale", { Parent = button })
	-- 위쪽에 큰 화살표(왼쪽 버튼 ←, 오른쪽 버튼 →: 키보드 ← → 키와 같은 쪽), 그 아래 '연타!'·내 횟수·키 안내
	local arrow = Ui.arrow(button, direction, C.Yellow)
	arrow.Position = UDim2.fromScale(0.5, 0.25)
	arrow.Size = UDim2.fromScale(0.34, 0.34)
	local word = Ui.label(button, "Word", "연타!", 32, {
		Position = UDim2.fromScale(0, 0.43),
		Size = UDim2.fromScale(1, 0.18),
		TextColor3 = C.Yellow,
		TextStrokeTransparency = 0.3,
	})
	local count = Ui.label(button, "Count", "0", 28, {
		Position = UDim2.fromScale(0, 0.61),
		Size = UDim2.fromScale(1, 0.15),
	})
	local hint = Ui.label(button, "Hint", "", 15, {
		Position = UDim2.fromScale(0, 0.77),
		Size = UDim2.fromScale(1, 0.09),
		TextColor3 = C.Dim,
	})
	local pad: TapPad = {
		button = button,
		scale = scale,
		stroke = stroke,
		word = word,
		count = count,
		hint = hint,
		rings = {},
		ringNext = 1,
		myDepth = 0,
		otherDepth = 0,
		lastMyRing = 0,
	}
	for i = 1, RING_COUNT do
		local frame = Ui.frame(button, "Ring" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Visible = false,
		})
		Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
		local ringStroke = Ui.stroke(frame, C.Yellow, 4, 0)
		table.insert(pad.rings, { frame = frame, stroke = ringStroke, born = 0, life = 1, from = 1, to = 1 })
	end
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			if kind == Enum.UserInputType.Touch then
				usedTouch = true
			end
			pressTap(side)
		end
	end)
	return pad
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

	-- 연타 미션: 로켓 전체 합계의 단계 게이지(눈금 = 단계) + 합계·내 횟수·가속 배율
	tapBox = Ui.frame(panel, "TapBox", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 38),
		Size = UDim2.new(1, -40, 0, 84),
		Visible = false,
	})
	local gauge, gaugeFill = Ui.bar(tapBox, "TapGauge", C.Yellow, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 26),
	})
	tapFill = gaugeFill
	tapGaugeStroke = Ui.stroke(gauge, C.Yellow, 2, 0.4)
	for level = 1, Config.Tap.MaxLevel - 1 do
		Ui.frame(gauge, "Tick" .. level, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(level / Config.Tap.MaxLevel, 0.5),
			Size = UDim2.new(0, 2, 1, -6),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.55,
			ZIndex = 2,
		})
	end
	tapTotalLabel = Ui.label(tapBox, "TapTotal", "", 30, {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(0.42, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	tapMineLabel = Ui.label(tapBox, "TapMine", "", 22, {
		Position = UDim2.new(0.42, 0, 0, 34),
		Size = UDim2.new(0.22, 0, 0, 44),
	})
	tapBoostLabel = Ui.label(tapBox, "TapBoost", "", 22, {
		Position = UDim2.new(0.64, 0, 0, 34),
		Size = UDim2.new(0.36, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Cyan,
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

	-- 연타 버튼 두 개: 양손 엄지 자리(이동 스틱 자리와 점프 버튼 자리). 위 끝이 502 라서 디버그 패널(아래 끝 501)·
	-- 부스터 메뉴(왼쪽 가운데)와 겹치지 않고, 가운데 미션 판(340~940)과도 떨어져 있음
	tapPads[1] = buildTapPad("TapLeft", 1, "Left", UDim2.new(0, 160, 1, -118))
	tapPads[2] = buildTapPad("TapRight", 2, "Right", UDim2.new(1, -150, 1, -118))

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
			tap = nil
			panel.Visible = false
		end
	end)
end

-- 미션 입력 중에는 ← → 키를 기본 카메라(키보드로 화면 돌리기)에 넘기지 않음: 미션 키로만 쓰고, 연타로 마구 눌러도
-- 화면이 흔들리지 않게. 키 자체는 위의 UserInputService.InputBegan 으로 그대로 받음 (ContextActionService 가 가로챈 키도 옴)
local function setArrowSink(on: boolean)
	if sinkingKeys == on then
		return
	end
	sinkingKeys = on
	if on then
		ContextActionService:BindActionAtPriority(SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Left, Enum.KeyCode.Right)
	else
		ContextActionService:UnbindAction(SINK_ACTION)
	end
end

-- 다른 사람 누름: 서버 합계가 오른 만큼을 다음 ShowInterval 동안 고르게 나눠, 버튼을 들썩이고 작은 고리를 띄움
local function updateOthers(dt: number)
	if otherQueue <= 0 then
		return
	end
	otherFrac += otherQueue * math.min(1, dt / Config.Tap.ShowInterval)
	local n = math.min(math.floor(otherFrac), otherQueue)
	if n <= 0 then
		return
	end
	otherFrac -= n
	otherQueue -= n
	local pad = tapPads[math.random(1, #tapPads)]
	if pad == nil then
		return
	end
	pad.otherDepth = math.max(pad.otherDepth, OTHER_DEPTH)
	local clock = os.clock()
	if clock - lastOtherRing >= OTHER_RING_GAP then
		lastOtherRing = clock
		ring(pad, false)
	end
end

-- 연타 미션 진행: 버튼 이펙트, 모아 둔 횟수를 SendInterval 초마다 보내고, 시간이 끝나면 남은 것을 마지막으로 보냄
local function updateTap(dt: number)
	local fade = math.exp(-dt * 16)
	tapFlash = math.max(0, tapFlash - dt * 3)
	appear = math.min(1, appear + dt / 0.2)
	updateRings()
	local t = tap
	for _, pad in ipairs(tapPads) do
		pad.myDepth *= fade
		pad.otherDepth *= fade
	end
	if not t then
		return
	end
	updateOthers(dt)
	local pop = 1 - (1 - appear) ^ 3
	for _, pad in ipairs(tapPads) do
		local depth = math.max(pad.myDepth, pad.otherDepth)
		pad.scale.Scale = (0.6 + 0.4 * pop) * (1 - 0.08 * depth)
		local glow = TAP_BASE:Lerp(C.Cyan, 0.3 * pad.otherDepth)
		pad.button.BackgroundColor3 = glow:Lerp(C.Yellow, 0.55 * pad.myDepth)
		pad.word.TextColor3 = C.Yellow:Lerp(C.White, pad.myDepth)
		pad.stroke.Thickness = 4 + 4 * math.max(pad.myDepth, pad.otherDepth * 0.6)
	end
	if not t.finished and State.now() > t.closeAt then
		t.finished = true
		sendTaps(t)
		titleLabel.Text = "연타 끝! 판정을 기다립니다"
		titleLabel.TextColor3 = C.Green
	elseif not t.finished and os.clock() - t.sentAt >= Config.Tap.SendInterval then
		sendTaps(t)
	end
	refreshTap(t)
	tapGaugeStroke.Color = if tapFlash > 0 then C.White else C.Yellow
	tapGaugeStroke.Thickness = 2 + 3 * tapFlash
	tapGaugeStroke.Transparency = 0.4 * (1 - tapFlash)
	tapFill.BackgroundColor3 = if t.level >= Config.Tap.MaxLevel then C.Green else C.Yellow
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
	local t = tap
	if t then
		local left = t.closeAt - State.now()
		timerFill.Size = UDim2.fromScale(math.clamp(left / t.limit, 0, 1), 1)
		timerFill.BackgroundColor3 = if left < t.limit * 0.3 then C.Red else C.Yellow
	end
	updateTap(_dt)
	if panel.Visible and (os.clock() > hideAt or not flying) then
		panel.Visible = false
		mission = nil
		tap = nil
	end

	-- 내 입력을 받는 동안만 걷기를 잠그고(CameraRig) 화면 버튼을 보여 줌
	local directionActive = mission ~= nil and not (mission :: Mission).finished and flying and crew
	local tapActive = tap ~= nil and not (tap :: Tap).finished and flying and crew
	State.missionInput = directionActive or tapActive
	setArrowSink(directionActive or tapActive)
	local showPad = directionActive and wantsPad()
	padFrame.Visible = showPad
	jumpButton.Visible = showPad
	-- 양옆 연타 버튼 (모든 기기. PC 는 마우스로도, ← → 키로도)
	for _, pad in ipairs(tapPads) do
		pad.button.Visible = tapActive
	end
end

return MissionUi
