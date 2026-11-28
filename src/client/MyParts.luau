-- '내 부품' 패널 (Nick 11-27): 선실 -X 벽 장착판(PartsBoard) 바로 아래 'MyPartsBoard' 에 내 부품 6개만 모아 보여 줍니다.
-- 종류마다 이름·돌파(★)·레어도와 부품 이름(레어도 색)·레벨·경험치 막대. 돌파 한도에 닿으면 '돌파 필요' (뽑기, Config.Gacha). 비행 중에는 서버가 Config.Progress.SendInterval(0.25초)마다 보내는 값으로
-- 막대가 쭉쭉 차고, 레벨이 오를 때마다 그 부품 자리에서 폭죽이 터지며 '+N Lv' 가 뜹니다 (그사이 여러 레벨이 오르면 한 번으로 묶음).
-- 값은 서버 PartProgress 가 이 사람에게만 'PartProgress' 신호로 보냅니다. 시작할 때 한 번 달라고 요청합니다.
-- 패널과 폭죽은 내 화면에만 있어서, 같은 벽을 봐도 사람마다 자기 부품이 보입니다.
-- 부품 피버 (Nick 11-28): 비행 중 내 부품이 피버에 들어가면 그 칸에 금빛 테두리·별빛(FeverFx)과 '피버!' 딱지가 뜨고,
-- 패널 앞에서 금빛 반짝이가 피어남 (다음 미션 판정까지).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Leveling = require(Shared:WaitForChild("Leveling"))
local Net = require(Shared:WaitForChild("Net"))

local BuildUi = require(script.Parent:WaitForChild("BuildUi"))
local FeverFx = require(script.Parent:WaitForChild("FeverFx"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local MyParts = {}

local C = Ui.Colors
local PIXELS_PER_STUD = 30
local BOARD_NAME = "MyPartsBoard"
local BOARD_WAIT = 30 -- 패널 파트를 기다리는 시간(초). 없는 맵이면 패널 없이 지나감
local MINE = BuildUi.MineColor
local PAD = 14 -- 패널 안쪽 여백(픽셀)
local BAR_SPEED = 5 -- 경험치 막대가 1초에 움직이는 길이 (막대 전체 = 1)
local FX_MARGIN = 0.8 -- 폭죽이 터지는 자리: 패널 앞면에서 이만큼(스터드) 앞
local FX_HEIGHT = 0.4 -- 폭죽이 터지는 높이: 패널 위에서 이 비율 (레벨 글자 자리)
local POP_SOUND = "rbxasset://sounds/impact_explosion_03.mp3" -- 설치본에 있는 파일. 높은 음으로 작게 틀면 폭죽 소리
local POP_VOLUME = 0.15
local POP_GAP = 0.45 -- 폭죽 소리 사이 최소 간격(초). 초반엔 비행 내내 레벨이 오르므로 시끄럽지 않게
local BIG_QUIET = 1.5 -- 이만큼(초) 안 오르다 오르면 크게 터뜨림 (갈수록 레벨업이 드물어져 한 번 한 번이 큼)
local RETRY = 5 -- 값을 못 받으면 이 간격(초)으로 다시 요청
local FEVER_CHECK = 0.1 -- 내 부품 피버를 다시 읽는 간격(초)
local FEVER_RATE = 8 -- 피버 중인 내 부품 하나에서 피어나는 반짝이 수(초당). 6개 모두여도 한꺼번에 60개쯤 (휴대폰 사양)
local FEVER_POP = 14 -- 피버에 들어가는 순간 한 번에 터지는 반짝이 수

type Column = {
	typeId: string,
	frame: Frame,
	title: TextLabel,
	variant: TextLabel,
	level: TextLabel,
	pulse: UIScale,
	fill: Frame,
	exp: TextLabel,
	up: TextLabel,
	sparks: ParticleEmitter?,
	glow: ParticleEmitter?,
	fever: FeverFx.Glints,
	feverBadge: TextLabel,
	feverSparkles: ParticleEmitter?,
	feverOn: boolean,
	lv: number,
	rarity: number,
	star: number,
	cap: number,
	look: string,
	expValue: number,
	lastBurst: number, -- 마지막으로 폭죽이 터진 시각 (os.clock)
	shown: number, -- 지금 보이는 막대 길이 (0~1)
	target: number, -- 서버 값의 막대 길이
	wraps: number, -- 막대가 끝까지 찼다가 처음부터 다시 찰 횟수 (레벨이 오름)
}

local gui: SurfaceGui? = nil
local columns: { Column } = {}
local byType: { [string]: Column } = {}
local latest: any = nil -- 화면이 생기기 전에 받은 값
local received = false -- 서버 값을 한 번이라도 받음 (첫 값은 폭죽 없이)
local nextRequest = 0
local pops: { Sound } = {}
local popIndex = 0
local lastPop = -math.huge
local lastFeverCheck = 0

-- ------------------------------------------------------------ 폭죽
local function makeFx(board: BasePart, column: Column, index: number, count: number)
	local width = board.Size.X * PIXELS_PER_STUD
	local x = PAD + (index - 0.5) * (width - 2 * PAD) / count -- 패널 왼쪽에서 칸 가운데까지(픽셀)
	local u = x / width
	-- 앞면(Front, -Z)을 바라볼 때 화면 오른쪽이 파트의 -X
	local attachment = Instance.new("Attachment")
	attachment.Name = "MyPartFx_" .. column.typeId
	attachment.Position = Vector3.new((0.5 - u) * board.Size.X, (0.5 - FX_HEIGHT) * board.Size.Y, -(board.Size.Z / 2 + FX_MARGIN))
	local color = column.frame:FindFirstChildOfClass("UIStroke") and (column.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Color or C.White
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Enabled = true
	sparks.Rate = 0 -- 레벨이 오를 때만 Emit 으로 터뜨림
	sparks.EmissionDirection = Enum.NormalId.Front -- 패널 밖(선실 쪽)으로
	sparks.SpreadAngle = Vector2.new(75, 75)
	sparks.Speed = NumberRange.new(10, 24)
	sparks.Drag = 2.5
	sparks.Acceleration = Vector3.new(0, -14, 0)
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Size = NumberSequence.new(0.9, 0)
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.White),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, MINE),
	})
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Brightness = 2
	sparks.ZOffset = 1
	sparks.Parent = attachment
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "Glow"
	glow.Enabled = true
	glow.Rate = 0
	glow.Speed = NumberRange.new(0, 0)
	glow.Lifetime = NumberRange.new(0.3, 0.3)
	glow.Size = NumberSequence.new(2.5, 6)
	glow.Transparency = NumberSequence.new(0.2, 1)
	glow.Color = ColorSequence.new(color)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.ZOffset = 0.5
	glow.Parent = attachment
	-- 부품 피버 반짝이: 피버 동안 패널 앞으로 천천히 피어남 (기본 그림이 반짝이라 Texture 는 그대로)
	local fever = Instance.new("ParticleEmitter")
	fever.Name = "FeverSparkles"
	fever.Enabled = true
	fever.Rate = 0
	fever.EmissionDirection = Enum.NormalId.Front
	fever.SpreadAngle = Vector2.new(70, 50)
	fever.Speed = NumberRange.new(1.5, 4)
	fever.Drag = 1
	fever.Acceleration = Vector3.new(0, 1.5, 0)
	fever.Lifetime = NumberRange.new(0.7, 1.3)
	fever.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	fever.Color = ColorSequence.new(C.White, FeverFx.Gold)
	fever.LightEmission = 1
	fever.LightInfluence = 0
	fever.Rotation = NumberRange.new(0, 360)
	fever.RotSpeed = NumberRange.new(-90, 90)
	fever.ZOffset = 1
	fever.Parent = attachment
	attachment.Parent = board
	column.sparks = sparks
	column.glow = glow
	column.feverSparkles = fever
end

local function popSound(big: boolean)
	local now = os.clock()
	if #pops == 0 or now - lastPop < POP_GAP then
		return
	end
	lastPop = now
	popIndex = popIndex % #pops + 1 -- 두 개를 번갈아 써서 앞 소리가 끊기지 않게
	local sound = pops[popIndex]
	sound.Volume = if big then POP_VOLUME * 2 else POP_VOLUME
	sound.PlaybackSpeed = (if big then 1.3 else 1.6) + math.random() * 0.5
	sound:Play()
end

-- 레벨이 ups 만큼 오름: 폭죽, '+N Lv', 레벨 글자 튀기. 한동안 안 오르다 오르면 크게. 크게 터졌는지 돌려줌
local function burst(column: Column, ups: number): boolean
	local now = os.clock()
	local big = now - column.lastBurst >= BIG_QUIET
	column.lastBurst = now
	local sparks, glow = column.sparks, column.glow
	if sparks then
		sparks:Emit(if big then 45 else math.clamp(10 + 3 * ups, 12, 40))
	end
	if glow then
		glow:Emit(if big then 2 else 1)
	end
	local up = column.up
	up.Text = "+" .. Fmt.comma(ups) .. " Lv"
	up.Position = UDim2.fromScale(0, 0.2)
	up.TextTransparency = 0
	up.TextStrokeTransparency = 0.2
	Ui.tween(up, 0.8, { Position = UDim2.fromScale(0, 0.02), TextTransparency = 1, TextStrokeTransparency = 1 })
	column.pulse.Scale = if big then 1.5 else 1.25
	Ui.tween(column.pulse, if big then 0.4 else 0.25, { Scale = 1 })
	return big
end

-- ------------------------------------------------------------ 값
local function number(map: any, key: string, default: number): number
	local value = if type(map) == "table" then map[key] else nil
	return if type(value) == "number" and value == value then value else default
end

local function showText(column: Column)
	local max = column.lv >= Leveling.MaxLevel
	local capped = not max and column.lv >= column.cap -- 돌파 한도: 경험치는 쌓아 두고 레벨은 멈춤
	column.level.Text = if max then "MAX" else "Lv " .. Fmt.comma(column.lv)
	column.level.TextColor3 = if max or capped then C.Yellow else C.Text
	local need = Leveling.need(column.lv, column.rarity)
	column.exp.Text = if max
		then "만렙"
		elseif capped then "한도! 돌파하면 더 올라감"
		else Fmt.comma(math.floor(column.expValue)) .. " / " .. Fmt.comma(need)
	column.exp.TextColor3 = if capped then C.Yellow else C.Dim
	local info = nil
	for _, partType in ipairs(Config.Parts.Types) do
		if partType.Id == column.typeId then
			info = partType
		end
	end
	column.title.Text = (if info then info.Name else column.typeId) .. " ★" .. tostring(column.star)
	local rarity = math.clamp(math.floor(column.rarity), 1, #Config.Parts.RarityNames)
	local variant = Catalog.get(column.look)
	if variant == nil or variant.Rarity ~= rarity then
		variant = Catalog.ofRarity(column.typeId, rarity)[1]
	end
	-- 부품 이름만 (레어도는 글자 색으로): 칸이 좁아서 레어도 글자까지 넣으면 잘림
	column.variant.Text = if variant then variant.Name else Config.Parts.RarityNames[rarity]
	column.variant.TextColor3 = Catalog.rarityText(rarity)
end

-- 서버 값 반영. 첫 값은 바로 맞추고, 그 뒤로는 레벨이 오른 부품마다 폭죽
local function apply(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local first = not received
	received = true
	local burstCount = 0
	local big = false
	for _, column in ipairs(columns) do
		local id = column.typeId
		column.lv = number(payload.lv, id, column.lv)
		column.expValue = number(payload.exp, id, column.expValue)
		column.rarity = number(payload.rarity, id, column.rarity)
		column.star = number(payload.star, id, column.star)
		column.cap = number(payload.cap, id, Leveling.cap(column.star))
		local look = if type(payload.look) == "table" then payload.look[id] else nil
		if type(look) == "string" then
			column.look = look
		end
		column.target = Leveling.fraction(column.lv, column.expValue, column.rarity)
		local ups = number(payload.ups, id, 0)
		if first then
			column.shown = column.target
			column.wraps = 0
		elseif ups > 0 then
			column.wraps = math.min(column.wraps + 1, 2)
			big = burst(column, ups) or big
			burstCount += 1
		end
		showText(column)
	end
	if burstCount > 0 then
		popSound(big)
	end
end

local function onProgress(payload: any)
	if #columns == 0 then
		latest = payload -- 화면이 아직 없음: 생기면 반영
		return
	end
	apply(payload)
end

-- ------------------------------------------------------------ 화면
local function build(board: BasePart)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local surface = Ui.make("SurfaceGui", {
		Name = "RoflyMyParts",
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
	local back = Ui.frame(surface, "Back", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 8, 22),
		BackgroundTransparency = 0,
	})
	Ui.stroke(back, MINE, 6, 0)
	Ui.label(back, "Head", "내 부품 · " .. player.DisplayName, 36, {
		Position = UDim2.new(0, PAD + 6, 0, 6),
		Size = UDim2.new(0.6, 0, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MINE,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(back, "Hint", string.format("비행 1초마다 경험치 +%s", Fmt.comma(Config.Progress.ExpPerSecond)), 26, {
		Position = UDim2.new(0.4, 0, 0, 6),
		Size = UDim2.new(0.6, -(PAD + 6), 0, 46),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Dim,
	})
	local list = Ui.frame(back, "Parts", {
		Position = UDim2.new(0, PAD, 0, 58),
		Size = UDim2.new(1, -2 * PAD, 1, -58 - PAD),
	})
	local count = #Config.Parts.Types
	for index, info in ipairs(Config.Parts.Types) do
		local style = BuildUi.TypeStyle[info.Id] or { Color = C.Cyan }
		local frame = Ui.frame(list, "MyPart_" .. info.Id, {
			Position = UDim2.new((index - 1) / count, 6, 0, 0),
			Size = UDim2.new(1 / count, -12, 1, 0),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.3,
		})
		Ui.corner(frame, 12)
		Ui.stroke(frame, style.Color, 2, 0.3)
		local title = Ui.label(frame, "PartName", info.Name, 26, {
			Position = UDim2.fromScale(0, 0.02),
			Size = UDim2.fromScale(1, 0.16),
			TextColor3 = style.Color,
		})
		local variant = Ui.label(frame, "Variant", "", 20, {
			Position = UDim2.new(0, 6, 0.18, 0),
			Size = UDim2.new(1, -12, 0.13, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local level = Ui.label(frame, "Level", "Lv 1", 46, {
			Position = UDim2.fromScale(0, 0.31),
			Size = UDim2.fromScale(1, 0.24),
		})
		local pulse = Ui.make("UIScale", { Name = "Pulse", Scale = 1, Parent = level })
		local bar = Ui.frame(frame, "ExpBar", {
			Position = UDim2.new(0, 12, 0.57, 0),
			Size = UDim2.new(1, -24, 0.13, 0),
			BackgroundColor3 = C.Black,
			BackgroundTransparency = 0.45,
			ClipsDescendants = true,
		})
		Ui.corner(bar, 8)
		local fill = Ui.frame(bar, "ExpFill", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = style.Color,
			BackgroundTransparency = 0,
		})
		Ui.corner(fill, 8)
		local exp = Ui.label(frame, "Exp", "", 22, {
			Position = UDim2.fromScale(0, 0.72),
			Size = UDim2.fromScale(1, 0.15),
			TextColor3 = C.Dim,
		})
		local up = Ui.label(frame, "LevelUp", "", 34, {
			Position = UDim2.fromScale(0, 0.2),
			Size = UDim2.fromScale(1, 0.2),
			TextColor3 = MINE,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			ZIndex = 3,
		})
		-- 피버 딱지: 칸 위 테두리에 걸친 금빛 띠
		local badge = Ui.label(frame, "FeverBadge", "피버!", 26, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(96, 32),
			BackgroundColor3 = FeverFx.Gold,
			BackgroundTransparency = 0,
			TextColor3 = Color3.fromRGB(40, 26, 0),
			TextStrokeTransparency = 1,
			Visible = false,
			ZIndex = 4,
		})
		Ui.corner(badge, 10)
		local column: Column = {
			typeId = info.Id,
			frame = frame,
			title = title,
			variant = variant,
			level = level,
			pulse = pulse,
			fill = fill,
			exp = exp,
			up = up,
			sparks = nil,
			glow = nil,
			fever = FeverFx.glints(frame, 4, 0.26, 6, 4, true), -- 6칸뿐이라 한도 없이 늘 반짝임
			feverBadge = badge,
			feverSparkles = nil,
			feverOn = false,
			lv = 1,
			rarity = 1,
			star = 1,
			cap = Leveling.cap(1),
			look = Catalog.starter(info.Id).Id,
			expValue = 0,
			lastBurst = -math.huge,
			shown = 0,
			target = 0,
			wraps = 0,
		}
		showText(column)
		makeFx(board, column, index, count)
		table.insert(columns, column)
		byType[info.Id] = column
	end
	for i = 1, 2 do
		local sound = Instance.new("Sound")
		sound.Name = "RoflyPartPop" .. i
		sound.SoundId = POP_SOUND
		sound.Volume = POP_VOLUME
		sound.Parent = SoundService
		pops[i] = sound
	end
	gui = surface
	if latest ~= nil then
		local payload = latest
		latest = nil
		apply(payload)
	end
end

function MyParts.init()
	Net.event("PartProgress").OnClientEvent:Connect(onProgress)
	Net.event("PartProgress"):FireServer()
	nextRequest = os.clock() + RETRY
	task.spawn(function()
		local rofly = Workspace:WaitForChild("Rofly", BOARD_WAIT)
		local rocket = rofly and rofly:WaitForChild("Rocket", BOARD_WAIT)
		local board = rocket and rocket:WaitForChild(BOARD_NAME, BOARD_WAIT)
		if board and board:IsA("BasePart") then
			build(board)
		end
	end)
end

-- 내 부품 피버를 서버 값(Grid/<종류>의 F<좌석>)에 맞춤. 비행 중 승무원일 때만
local function updateFever()
	local seat = if State.role() == "Crew" and State.phase() == "Flight" then State.myNumber("Seat") else 0
	for _, column in ipairs(columns) do
		local on = seat > 0 and FeverFx.isOn(column.typeId, seat)
		if on ~= column.feverOn then
			column.feverOn = on
			FeverFx.show(column.fever, on)
			column.feverBadge.Visible = on
			local emitter = column.feverSparkles
			if emitter then
				emitter.Rate = if on then FEVER_RATE else 0
				if on then
					emitter:Emit(FEVER_POP)
				end
			end
		end
	end
end

function MyParts.update(dt: number)
	if not received and os.clock() >= nextRequest then
		nextRequest = os.clock() + RETRY
		Net.event("PartProgress"):FireServer()
	end
	if not gui then
		return
	end
	if os.clock() - lastFeverCheck >= FEVER_CHECK then
		lastFeverCheck = os.clock()
		updateFever()
	end
	local step = BAR_SPEED * dt
	for _, column in ipairs(columns) do
		if column.wraps > 0 then
			-- 레벨이 오름: 끝까지 채운 뒤 처음부터
			column.shown += step
			if column.shown >= 1 then
				column.shown = 0
				column.wraps -= 1
			end
		elseif column.shown < column.target then
			column.shown = math.min(column.target, column.shown + step)
		else
			column.shown = column.target
		end
		column.fill.Size = UDim2.fromScale(math.clamp(column.shown, 0, 1), 1)
	end
end

return MyParts
