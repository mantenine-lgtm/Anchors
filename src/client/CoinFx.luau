-- 비행 중 코인 연출: 화면 위쪽 거리 오른쪽에 '이번 비행 코인' 칸을 두고, 코인이 날아 들어올 때마다 숫자를 올립니다.
-- - 거리 코인: 거리만큼 쌓이는 코인은 거리 숫자에서 작게 튀어나와 칸으로 폴짝 들어갑니다 (짧게 모아 0.3초마다).
-- - 부스터 코인: 부스터로 더 번 코인(서버가 알려 주는 '그 부스터 하나만 안 쓴 비행'과의 거리 차이, 황금 항로는 늘어난 코인)은
--   부스터 색으로 잠깐 모았다가 화면 가운데에서 한꺼번에 터져 나와 칸으로 빨려 들어가고, 칸 아래에 '+N 터보 엔진'처럼 뜹니다.
-- - 한 번에 들어오는 코인이 많을수록 코인 수·크기·퍼지는 폭·글자·고리·반짝임·소리가 커지고, 적으면 작게 들어옵니다.
--   크기는 이번 판 예상 코인(조립 때 예상 거리 × CoinsPerKm)에 대한 비율이라 장비가 좋아져도 같은 비율이면 같은 느낌입니다.
-- - 숫자는 정산과 같은 계산(Scoring.liveCoins, 자리 비움이면 절반)이라 비행이 끝나면 정산 화면의 '코인 +N'과 같아집니다.
-- 수치는 Config.CoinFx. 승무원에게만 보입니다 (관전자는 코인을 받지 않음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Scoring = require(Shared:WaitForChild("Scoring"))

local BoosterMenu = require(script.Parent:WaitForChild("BoosterMenu"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local CoinFx = {}

local C = Ui.Colors
local FX = Config.CoinFx
local player = Players.LocalPlayer
local rng = Random.new()

-- 칸 배치 (기준 화면 1280x720 단위). 위쪽 가운데 거리 글자(가운데에서 좌우 100 안쪽) 오른쪽, 오른쪽 위 지갑(오른쪽 끝에서 266) 왼쪽.
-- 거리 글자와 같은 줄이고, 아래 끝(48)이 그 밑의 스테이지 안내 글자(54쯤부터)에 닿지 않습니다.
CoinFx.Left = 132 -- 화면 가운데에서 칸 왼쪽 끝까지
CoinFx.Top = 8
CoinFx.Width = 220
CoinFx.Height = 40
local ICON = 30
local ICON_X = 8 -- 칸 왼쪽 끝에서 코인 그림 왼쪽 끝까지
local TEXT_X = ICON_X + ICON + 8
local TEXT_WIDTH = CoinFx.Width - TEXT_X - 8
local NUMBER_SIZE = 24
local NUMBER_MIN = 14
local CAPTION_SIZE = 11
local MAX_PULSE = 0.18 -- 코인이 들어올 때 칸이 커지는 최대 비율 (커져도 지갑에 닿지 않게)
local POPUP_SECONDS = 1.4

local GOLD = Color3.fromRGB(255, 196, 46)
local GOLD_DARK = Color3.fromRGB(184, 116, 12)
local GOLD_LIGHT = Color3.fromRGB(255, 238, 150)

type Burst = {
	serial: number,
	id: string?, -- 부스터 Id (거리 코인이면 nil)
	amount: number, -- 이 무더기의 코인 (자리 비움 반영 전)
	power: number, -- 0(가장 작음) ~ 1(가장 화려함)
	count: number, -- 날린 코인 그림 수
	left: number, -- 아직 칸에 닿지 않은 그림 수
	landed: boolean, -- 첫 그림이 칸에 닿았는지
	color: Color3,
}

type Sprite = {
	holder: Frame,
	coin: Frame,
	burst: Burst,
	value: number, -- 칸에 닿을 때 더할 코인
	index: number, -- 무더기 안에서 몇 번째로 닿는지
	age: number,
	scatter: number, -- 퍼지는 시간
	flyAt: number, -- 칸으로 날아가기 시작하는 때 (age 기준)
	fly: number, -- 칸까지 날아가는 시간
	fromX: number,
	fromY: number,
	midX: number,
	midY: number,
	bendX: number,
	bendY: number,
	size: number,
	spin: number,
	phase: number,
}

type Effect = {
	frame: GuiObject,
	age: number,
	life: number,
	kind: string, -- "popup" | "ring" | "spark"
	x: number,
	y: number,
	vx: number,
	vy: number,
	size: number,
	grow: number,
	stroke: UIStroke?,
}

local root: Frame -- 칸·글자·고리·반짝이 (다른 화면 요소 위)
local flyRoot: Frame -- 날아가는 코인과 금빛 번쩍임 (비행 화면 글자·판 아래: 코인이 '누가 썼습니다' 같은 글을 가리지 않게)
local counter: Frame
local counterScale: UIScale
local counterStroke: UIStroke
local numberLabel: TextLabel
local layer: Frame -- 칸 위의 효과 (root 안)
local flyLayer: Frame -- 날아가는 코인 (flyRoot 안)
local gleamFrame: Frame
local sounds: { Sound } = {}
local soundIndex = 0
local lastSound = 0

local sprites: { Sprite } = {}
local effects: { Effect } = {}
local pulse = 0
local glow = 0
local burstSerial = 0
local fittedLength = -1

-- 이번 비행의 코인 셈 (모두 자리 비움 반영 전 값)
local counting = false -- 승무원으로 비행 중이라 코인을 세는 중
local shown = false -- 칸을 보여 주는 중 (비행 ~ 정산)
local earned = 0 -- 지금까지 번 코인 (정산과 같은 계산. 화면 거리가 잠깐 뒤로 당겨져도 줄지 않게 가장 큰 값)
local claimed = 0 -- 칸으로 날려 보낸 코인 (날아가는 중 + 닿은 것)
local claimedBy: { [string]: number } = {} -- 그중 부스터마다의 몫
local distanceClaimed = 0 -- 그중 거리 코인
local gatherFrom: { [string]: number } = {} -- 부스터 코인을 모으기 시작한 때 (os.clock)
local landed = 0 -- 칸에 닿은 코인 = 화면 숫자
local lastDistance = 0
local official: number? = nil -- 정산에서 받은 코인 (자리 비움 반영 후)
local lastPhase = ""

-- 부스터 코인을 나눠 줄 순서: 황금 항로가 먼저 (정산의 '황금 항로 +N'과 끝까지 같게. 다른 부스터끼리 거리를
-- 겹쳐 세면 마지막에 모자랄 수 있음)
local ORDER: { string } = { "Golden" }
for _, info in ipairs(Boosters.List) do
	if info.Id ~= "Golden" then
		table.insert(ORDER, info.Id)
	end
end

-- ------------------------------------------------------------ 계산
local function afkFactor(): number
	return if player:GetAttribute("Afk") == true then Config.Rewards.AfkCoinFactor else 1
end

-- 화면에 적는 숫자. 비행이 끝나 정산 값을 받았고 날아가는 코인이 없으면 정산 값 그대로.
local function shownCoins(): number
	if official ~= nil and not counting and #sprites == 0 then
		return official
	end
	return math.floor(landed * afkFactor())
end

-- 이번 판 예상 코인: 효과 크기의 기준
local function expectedCoins(): number
	return math.max(State.number("ExpectedKm") * Config.Rewards.CoinsPerKm, FX.MinExpected)
end

-- 한 번에 들어오는 코인 양 -> 효과 크기 0~1 (예상 코인에 대한 비율의 로그 눈금)
function CoinFx.powerOf(amount: number, expected: number): number
	local ratio = amount / math.max(expected, 1)
	if ratio <= FX.SmallRatio then
		return 0
	end
	return math.clamp(math.log(ratio / FX.SmallRatio) / math.log(FX.HugeRatio / FX.SmallRatio), 0, 1)
end

-- 지금 거리에서의 이번 비행 코인과 부스터마다의 몫 (서버가 알려 준 부스터 거리·황금 항로 시작점으로),
-- 그리고 황금 항로 몫을 뺀 '거리만'의 코인
local function liveCoins(km: number): (number, { [string]: number }, number)
	local extras: { [string]: number } = {}
	local goldenFrom: number? = nil
	for _, info in ipairs(Boosters.List) do
		local id = info.Id
		if State.flag(Boosters.usedAttribute(id)) then
			if id == "Golden" then
				local from = State.number("GoldenFromKm")
				if from >= 0 then
					goldenFrom = from
				end
			else
				extras[id] = State.number(Boosters.extraAttribute(id))
			end
		end
	end
	local golden = Boosters.get("Golden")
	local total, shares = Scoring.liveCoins(km, goldenFrom, if golden then golden.Value else 1, extras)
	return total, shares, Scoring.coins(km, false)
end

-- ------------------------------------------------------------ 그림
local function round(frame: GuiObject)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
end

-- 코인 하나. holder 는 크기를 정하는 바깥 틀(돌지 않음), coin 은 좌우로 줄었다 늘었다 하며 도는 동전.
-- glow 를 주면 뒤에 그 색의 빛무리를 둠 (부스터 코인)
local function makeCoin(parent: Instance, name: string, size: number, glowColor: Color3?, glowAlpha: number?): (Frame, Frame)
	local holder = Ui.frame(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
	})
	if glowColor then
		local halo = Ui.frame(holder, "Glow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.6, 1.6),
			BackgroundColor3 = glowColor,
			BackgroundTransparency = glowAlpha or 0.7,
		})
		round(halo)
	end
	local coin = Ui.frame(holder, "Body", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
	})
	round(coin)
	Ui.stroke(coin, GOLD_DARK, math.max(1, math.floor(size / 12 + 0.5)), 0)
	local inner = Ui.frame(coin, "Inner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
	})
	round(inner)
	Ui.stroke(inner, GOLD_DARK, math.max(1, math.floor(size / 16 + 0.5)), 0.25)
	local shine = Ui.frame(coin, "Shine", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.32, 0.3),
		Size = UDim2.fromScale(0.28, 0.18),
		Rotation = -35,
		BackgroundColor3 = GOLD_LIGHT,
		BackgroundTransparency = 0.1,
	})
	round(shine)
	return holder, coin
end

-- 바탕(root)의 크기를 기준 단위로 (화면 전체를 줄이는 UIScale 을 되돌림)
local function refSize(): (number, number)
	local size = root.AbsoluteSize
	local scale = root:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local w, h = size.X / s, size.Y / s
	if w <= 0 or h <= 0 then
		return Ui.RefWidth, Ui.RefHeight
	end
	return w, h
end

-- 칸의 코인 그림 가운데 (코인이 날아가는 곳)
local function target(refW: number): (number, number)
	return refW * 0.5 + CoinFx.Left + ICON_X + ICON / 2, CoinFx.Top + CoinFx.Height / 2
end

-- ------------------------------------------------------------ 소리
local function playSound(speed: number, volume: number, force: boolean?)
	if #sounds == 0 then
		return
	end
	local clock = os.clock()
	if not force and clock - lastSound < FX.SoundGap then
		return
	end
	lastSound = clock
	soundIndex = soundIndex % #sounds + 1
	local sound = sounds[soundIndex]
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.TimePosition = 0
	sound:Play()
end

-- ------------------------------------------------------------ 효과
local function addEffect(effect: Effect)
	table.insert(effects, effect)
end

-- 칸 아래에 뜨는 '+N' (부스터면 '+N 부스터 이름'). 거리 코인은 아주 많이 들어올 때만 (평소에는 숫자만 오름)
local function popup(burst: Burst)
	local amount = math.floor(burst.amount * afkFactor())
	local text = "+" .. Fmt.comma(amount)
	if burst.id ~= nil then
		local info = Boosters.get(burst.id)
		text ..= " " .. (if info then info.Name else "부스터")
	end
	if burst.power >= 0.7 then
		text ..= "!"
	end
	local size = math.floor(16 + 16 * burst.power + 0.5)
	-- 겹치지 않게: 막 뜬 글자가 있으면 그 아래에
	local below = 0
	for _, effect in ipairs(effects) do
		if effect.kind == "popup" and effect.age < 0.6 then
			below += effect.size + 4
		end
	end
	local refW = refSize()
	local x = refW * 0.5 + CoinFx.Left + CoinFx.Width
	local y = CoinFx.Top + CoinFx.Height + 4 + below
	local label = Ui.label(layer, "CoinPopup", text, size, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(360, size + 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = burst.color,
		TextStrokeTransparency = 0.15,
		ZIndex = 4,
	})
	label:SetAttribute("Amount", burst.amount)
	label:SetAttribute("Power", burst.power)
	label:SetAttribute("Burst", burst.serial)
	addEffect({ frame = label, age = 0, life = POPUP_SECONDS, kind = "popup", x = x, y = y, vx = 0, vy = 10, size = size, grow = 0, stroke = nil })
end

-- 칸에서 퍼지는 고리 (조금 큰 무더기부터)
local function ring(burst: Burst)
	local refW = refSize()
	local x, y = target(refW)
	local frame = Ui.frame(layer, "CoinRing", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(ICON, ICON),
		ZIndex = 3,
	})
	round(frame)
	local stroke = Ui.stroke(frame, burst.color, 3 + 4 * burst.power, 0.1)
	addEffect({ frame = frame, age = 0, life = 0.35 + 0.3 * burst.power, kind = "ring", x = x, y = y, vx = 0, vy = 0, size = ICON, grow = 50 + 170 * burst.power, stroke = stroke })
end

-- 칸에서 튀어 나가는 반짝이 (큰 무더기)
local function sparks(burst: Burst)
	local refW = refSize()
	local x, y = target(refW)
	local count = math.floor(4 + 10 * burst.power)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber() * 0.5
		local speed = 90 + 160 * burst.power * (0.6 + 0.4 * rng:NextNumber())
		local size = 6 + 6 * burst.power
		local spark = Ui.frame(layer, "CoinSpark", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			Rotation = 45,
			BackgroundColor3 = if i % 2 == 0 then GOLD_LIGHT else burst.color,
			BackgroundTransparency = 0,
			ZIndex = 4,
		})
		addEffect({ frame = spark, age = 0, life = 0.45 + 0.2 * burst.power, kind = "spark", x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, size = size, grow = 0, stroke = nil })
	end
end

-- 가장 큰 무더기: 화면 전체가 금빛으로 살짝 번쩍
local function gleam(power: number)
	gleamFrame.BackgroundTransparency = 1 - 0.18 * power
	Ui.tween(gleamFrame, 0.6, { BackgroundTransparency = 1 })
end

-- ------------------------------------------------------------ 날리기
-- 코인 amount 개를 한 무더기로 날림. id 가 있으면 부스터 코인 (화면 가운데에서 터져 나옴), 없으면 거리 코인 (거리 글자에서 폴짝)
local function launch(id: string?, amount: number)
	if amount < 1 then
		return
	end
	local power = CoinFx.powerOf(amount, expectedCoins())
	local maxCount = if id ~= nil then FX.MaxPerBurst else FX.DistanceMaxSprites
	local count = math.clamp(math.floor(1 + (maxCount - 1) * power ^ 1.2 + 0.5), 1, maxCount)
	count = math.min(count, FX.MaxSprites - #sprites)
	burstSerial += 1
	local color = if id ~= nil then BoosterMenu.colorOf(id) else GOLD_LIGHT
	local burst: Burst = {
		serial = burstSerial,
		id = id,
		amount = amount,
		power = power,
		count = math.max(count, 0),
		left = math.max(count, 0),
		landed = false,
		color = color,
	}
	-- 검사 도구와 디버그용: 마지막 무더기
	counter:SetAttribute("Bursts", burstSerial)
	counter:SetAttribute("LastBooster", id or "")
	counter:SetAttribute("LastAmount", amount)
	counter:SetAttribute("LastPower", power)
	counter:SetAttribute("LastSprites", burst.count)
	if count <= 0 then
		-- 이미 너무 많이 날아다니면 바로 칸에 넣음
		landed += amount
		pulse = math.max(pulse, 0.05)
		return
	end
	local refW, refH = refSize()
	local tx, ty = target(refW)
	local size = if id ~= nil then 16 + 22 * power else 15 + 10 * power
	local scatter = if id ~= nil then 0.22 + 0.25 * power else 0.16
	local gap = if id ~= nil then math.clamp(0.9 / count, 0.025, 0.07) else 0.07
	for i = 1, count do
		-- 코인을 그림마다 고르게 나눔 (그림이 코인보다 많으면 일부는 0)
		local value = math.floor(amount * i / count) - math.floor(amount * (i - 1) / count)
		local fromX, fromY, midX, midY
		if id ~= nil then
			-- 화면 가운데(외창)에서 위쪽 반원으로 터져 나옴 (아래쪽 미션 판은 가리지 않게)
			local cx, cy = refW * 0.5, refH * 0.5
			local angle = math.rad(-172 + 164 * rng:NextNumber())
			local reach = (50 + 250 * power) * (0.35 + 0.65 * rng:NextNumber())
			fromX = cx + (rng:NextNumber() - 0.5) * 30
			fromY = cy + (rng:NextNumber() - 0.5) * 20
			midX = cx + math.cos(angle) * reach
			midY = cy + math.sin(angle) * reach * 0.75
		else
			-- 거리 글자에서 튀어나와 살짝 뜸
			fromX = refW * 0.5 + (rng:NextNumber() - 0.5) * 90
			fromY = 34
			midX = fromX + (rng:NextNumber() - 0.3) * 30
			midY = 14 + rng:NextNumber() * 8
		end
		-- 칸으로 갈 때 옆으로 휘는 정도
		local dx, dy = tx - midX, ty - midY
		local length = math.max(math.sqrt(dx * dx + dy * dy), 1)
		local bend = (rng:NextNumber() - 0.5) * 0.5 * length
		local glowColor: Color3? = if id ~= nil then color else nil
		local holder, coin = makeCoin(flyLayer, "Coin", size, glowColor, 0.75 - 0.2 * power)
		holder.Position = UDim2.fromOffset(fromX, fromY)
		holder.ZIndex = 2
		holder:SetAttribute("Booster", id or "")
		holder:SetAttribute("Burst", burst.serial)
		holder:SetAttribute("Value", value)
		holder:SetAttribute("Size", size)
		holder:SetAttribute("Amount", amount)
		holder:SetAttribute("Power", power)
		table.insert(sprites, {
			holder = holder,
			coin = coin,
			burst = burst,
			value = value,
			index = i,
			age = -rng:NextNumber() * 0.05,
			scatter = scatter,
			flyAt = scatter + (i - 1) * gap + rng:NextNumber() * 0.04,
			fly = if id ~= nil then 0.42 + 0.12 * rng:NextNumber() else 0.3 + 0.06 * rng:NextNumber(),
			fromX = fromX,
			fromY = fromY,
			midX = midX,
			midY = midY,
			bendX = -dy / length * bend,
			bendY = dx / length * bend,
			size = size,
			spin = 7 + rng:NextNumber() * 6,
			phase = rng:NextNumber() * math.pi * 2,
		})
	end
end

-- 코인 그림 하나가 칸에 닿음
local function arrive(sprite: Sprite)
	local burst = sprite.burst
	landed += sprite.value
	burst.left -= 1
	pulse = math.max(pulse, 0.04 + (MAX_PULSE - 0.04) * burst.power)
	glow = math.max(glow, burst.power)
	-- 소리: 무더기 안에서 뒤로 갈수록 높아지고, 큰 무더기일수록 크고 높음
	local progress = sprite.index / math.max(burst.count, 1)
	if burst.id == nil and burst.power < 0.6 then
		playSound(2.5 + rng:NextNumber() * 0.25, FX.SoundVolume * 0.5)
	else
		playSound(2.2 + 0.9 * progress * (0.4 + burst.power) + rng:NextNumber() * 0.1, FX.SoundVolume + 0.3 * burst.power)
	end
	if not burst.landed then
		burst.landed = true
		-- 부스터 코인은 글자·고리·반짝이를 더 일찍(작은 양부터) 붙이고, 거리 코인은 평소에는 숫자만 오르게 아주 많을 때만
		local boost = burst.id ~= nil
		if boost or burst.power >= 0.6 then
			popup(burst)
		end
		if burst.power >= (if boost then 0.25 else 0.6) then
			ring(burst)
		end
		if burst.power >= (if boost then 0.55 else 0.8) then
			sparks(burst)
			playSound(1.5, FX.SoundVolume + 0.4 * burst.power, true)
		end
		if boost and burst.power >= 0.8 then
			gleam(burst.power)
		end
	end
end

-- ------------------------------------------------------------ 이번 비행 코인 세기
local function resetCount()
	earned = 0
	claimed = 0
	distanceClaimed = 0
	landed = 0
	table.clear(claimedBy)
	table.clear(gatherFrom)
	lastDistance = 0
	official = nil
	counter:SetAttribute("Official", -1)
	counter:SetAttribute("Mismatch", 0)
	for _, id in ipairs(ORDER) do
		counter:SetAttribute("Boost_" .. id, 0) -- 검사 도구가 봄: 부스터마다 날려 보낸 코인
	end
end

local function clearSprites()
	for _, sprite in ipairs(sprites) do
		sprite.holder:Destroy()
	end
	table.clear(sprites)
	for _, effect in ipairs(effects) do
		effect.frame:Destroy()
	end
	table.clear(effects)
end

-- 번 코인을 거리 코인과 부스터 코인으로 나눠 날림. flush 면 기다리지 않고 남은 것을 모두 날림 (비행이 끝났을 때).
-- 거리는 화면용으로 부드럽게 이은 값이 아니라 서버가 보낸 값(Km)을 씀: 부스터 거리와 같은 순간의 값이고,
-- 앞질러 어림한 거리로 정산보다 많이 세는 일이 없음 (어차피 0.3초마다 모아서 날리므로 0.1초 간격이면 충분)
-- 코인은 두 몫으로 나눠 셈: 황금 항로 몫(전체 - 거리만)과 '거리만' 몫. 거리 코인과 다른 부스터 코인은 '거리만' 몫
-- 안에서만 날려서, 끝에 황금 항로 코인 합이 정산의 '황금 항로 +N'과 꼭 같게 함.
local function collect(flush: boolean)
	local total, shares, plain = liveCoins(State.number("Km"))
	earned = math.max(earned, total)
	if not flush and shares.Golden ~= nil then
		-- 황금 항로 몫은 내림 때문에 잠깐 1개 줄었다가 돌아올 때가 있어, 비행 중에는 1개 덜 날리고 끝에 맞춤
		shares.Golden = math.max(shares.Golden - 1, 0)
	end
	local clock = os.clock()
	local othersClaimed = 0 -- 황금 항로가 아닌 부스터로 날린 코인
	for id, amount in pairs(claimedBy) do
		if id ~= "Golden" then
			othersClaimed += amount
		end
	end
	local othersPending = 0 -- 그 부스터들이 모으는 중인 코인
	for _, id in ipairs(ORDER) do
		local due = (shares[id] or 0) - (claimedBy[id] or 0)
		if due >= 1 then
			local started = gatherFrom[id]
			if started == nil then
				started = clock
				gatherFrom[id] = clock
			end
			if flush or clock - started >= FX.BoostGather then
				local room = earned - claimed
				if id ~= "Golden" then
					room = math.min(room, plain - distanceClaimed - othersClaimed)
				end
				local give = math.min(math.floor(due), room)
				if give >= 1 then
					launch(id, give)
					claimedBy[id] = (claimedBy[id] or 0) + give
					claimed += give
					due -= give
					if id ~= "Golden" then
						othersClaimed += give
					end
					counter:SetAttribute("Boost_" .. id, claimedBy[id])
				end
				gatherFrom[id] = nil
			end
		else
			gatherFrom[id] = nil
		end
		if id ~= "Golden" and due > 0 then
			othersPending += due
		end
	end
	-- 거리 코인: '거리만' 몫에서 다른 부스터 코인(날린 것 + 모으는 중)을 뺀 나머지
	local distanceDue = math.floor(math.min(plain - distanceClaimed - othersClaimed - othersPending, earned - claimed))
	if distanceDue >= 1 and (flush or clock - lastDistance >= FX.DistanceInterval) then
		launch(nil, distanceDue)
		claimed += distanceDue
		distanceClaimed += distanceDue
		lastDistance = clock
	end
	if flush and earned - claimed >= 1 then
		-- 부스터 몫이 다 못 받고 남은 것까지 모두
		local rest = earned - claimed
		launch(nil, rest)
		claimed += rest
		distanceClaimed += rest
	end
	counter:SetAttribute("Earned", earned)
	counter:SetAttribute("Claimed", claimed)
end

-- ------------------------------------------------------------ 매 프레임
local function animateSprites(dt: number)
	local refW = refSize()
	local tx, ty = target(refW)
	for i = #sprites, 1, -1 do
		local s = sprites[i]
		s.age += dt
		local x, y, scale
		if s.age < 0 then
			x, y, scale = s.fromX, s.fromY, 0.01
		elseif s.age < s.scatter then
			-- 터져 나옴
			local u = s.age / s.scatter
			local e = 1 - (1 - u) * (1 - u)
			x = s.fromX + (s.midX - s.fromX) * e
			y = s.fromY + (s.midY - s.fromY) * e
			scale = 0.35 + 0.65 * e
		elseif s.age < s.flyAt then
			-- 잠깐 떠 있음
			x = s.midX
			y = s.midY + math.sin((s.age - s.scatter) * 9 + s.phase) * 2
			scale = 1
		else
			-- 칸으로 빨려 들어감 (가까울수록 빨라짐)
			local u = math.min((s.age - s.flyAt) / s.fly, 1)
			if u >= 1 then
				arrive(s)
				s.holder:Destroy()
				table.remove(sprites, i)
				continue
			end
			local e = u ^ 1.8
			local cx = (s.midX + tx) * 0.5 + s.bendX
			local cy = (s.midY + ty) * 0.5 + s.bendY
			local a = 1 - e
			x = a * a * s.midX + 2 * a * e * cx + e * e * tx
			y = a * a * s.midY + 2 * a * e * cy + e * e * ty
			scale = 1 - 0.35 * e
		end
		local px = s.size * scale
		s.holder.Position = UDim2.fromOffset(x, y)
		s.holder.Size = UDim2.fromOffset(px, px)
		-- 동전이 도는 모습: 좌우 폭만 줄었다 늘었다
		local flip = math.abs(math.cos(math.max(s.age, 0) * s.spin + s.phase))
		s.coin.Size = UDim2.fromScale(math.max(flip, 0.2), 1)
	end
end

local function animateEffects(dt: number)
	for i = #effects, 1, -1 do
		local effect = effects[i]
		effect.age += dt
		local u = effect.age / effect.life
		if u >= 1 then
			effect.frame:Destroy()
			table.remove(effects, i)
			continue
		end
		local frame = effect.frame
		if effect.kind == "popup" then
			-- 처음 0.25초는 커지며 나타나고, 뒤쪽 40% 동안 흐려짐
			local label = frame :: TextLabel
			local fade = math.clamp((u - 0.6) / 0.4, 0, 1)
			label.Position = UDim2.fromOffset(effect.x, effect.y + effect.vy * effect.age)
			label.TextTransparency = fade
			label.TextStrokeTransparency = 0.15 + 0.85 * fade
			local pop = math.clamp(effect.age / 0.25, 0, 1)
			label.TextSize = math.max(1, math.floor(effect.size * (0.6 + 0.4 * pop) + 0.5))
		elseif effect.kind == "ring" then
			local e = 1 - (1 - u) * (1 - u)
			local size = effect.size + effect.grow * e
			frame.Size = UDim2.fromOffset(size, size)
			if effect.stroke then
				effect.stroke.Transparency = 0.1 + 0.9 * u
			end
		else
			effect.x += effect.vx * dt
			effect.y += effect.vy * dt
			effect.vx *= math.exp(-dt * 3)
			effect.vy *= math.exp(-dt * 3)
			frame.Position = UDim2.fromOffset(effect.x, effect.y)
			frame.BackgroundTransparency = u
			local size = effect.size * (1 - 0.6 * u)
			frame.Size = UDim2.fromOffset(size, size)
		end
	end
end

-- 숫자가 칸에 들어가는 가장 큰 글자 크기 (TextScaled 는 화면 전체 UIScale 아래에서 어떻게 되는지 확인되지 않아 직접 잼)
local function fitNumber(text: string)
	if #text == fittedLength then
		return
	end
	fittedLength = #text
	local fit = NUMBER_SIZE
	while fit > NUMBER_MIN do
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(text, fit, Ui.Font, Vector2.new(100000, 1000))
		end)
		if not ok or bounds.X <= TEXT_WIDTH then
			break
		end
		fit -= 1
	end
	numberLabel.TextSize = fit
end

local function updateCounter(dt: number)
	pulse *= math.exp(-dt * 9)
	glow *= math.exp(-dt * 4)
	counterScale.Scale = 1 + math.min(pulse, MAX_PULSE)
	counterStroke.Thickness = 2 + 3 * glow
	counterStroke.Transparency = 0.35 * (1 - glow)
	local value = shownCoins()
	local text = "+" .. Fmt.comma(value)
	numberLabel.Text = text
	fitNumber(text)
	counter:SetAttribute("Shown", value)
	counter:SetAttribute("Landed", landed)
end

function CoinFx.update(dt: number)
	local phase = State.phase()
	local crew = State.role() == "Crew"
	if phase ~= lastPhase then
		local previous = lastPhase
		lastPhase = phase
		if phase == "Flight" then
			clearSprites()
			resetCount()
			counting = crew
			shown = crew
		elseif previous == "Flight" and counting then
			-- 비행이 끝남: 남은 코인을 모두 날려 보냄 (정산 값과 같아짐)
			collect(true)
			counting = false
		end
		if phase == "Join" then
			counting = false
			shown = false
			clearSprites()
			resetCount()
		end
	end
	if counting and phase == "Flight" then
		collect(false)
	end
	counter.Visible = shown
	if not shown then
		return
	end
	animateSprites(dt)
	animateEffects(dt)
	if official ~= nil and not counting and #sprites == 0 then
		-- 날아가는 코인이 다 닿은 뒤에도 정산 값과 다르면 알림용으로 기록 (검사 도구가 봄)
		counter:SetAttribute("Mismatch", official - math.floor(landed * afkFactor()))
	end
	updateCounter(dt)
end

function CoinFx.init()
	-- 날아가는 코인은 비행 화면(Hud 10)·부스터 메뉴(11)·미션 판(12) 아래, 화면 번쩍임(5) 위
	local _, flyBase = Ui.screen("RoflyCoinFly", 9)
	flyRoot = flyBase
	gleamFrame = Ui.frame(flyRoot, "CoinGleam", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 1,
	})
	flyLayer = Ui.frame(flyRoot, "CoinFlyLayer", { Size = UDim2.fromScale(1, 1) })
	-- 칸과 그 위의 글자·고리는 맨 위 (코인이 칸 안으로 들어가 사라지는 것처럼 보임)
	local _, base = Ui.screen("RoflyCoins", 13)
	root = base
	-- 칸: 가운데를 기준으로 두어야 들어올 때 커지는 효과(UIScale)가 제자리에서 커짐
	counter = Ui.panel(root, "CoinCounter", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, CoinFx.Left + CoinFx.Width / 2, 0, CoinFx.Top + CoinFx.Height / 2),
		Size = UDim2.fromOffset(CoinFx.Width, CoinFx.Height),
		BackgroundTransparency = 0.3,
		Visible = false,
	})
	counterStroke = Ui.stroke(counter, GOLD, 2, 0.35)
	counterScale = Ui.make("UIScale", { Parent = counter })
	local icon = makeCoin(counter, "CoinIcon", ICON, nil, nil)
	icon.Position = UDim2.fromOffset(ICON_X + ICON / 2, CoinFx.Height / 2)
	Ui.label(counter, "CoinCaption", "이번 비행 코인", CAPTION_SIZE, {
		Position = UDim2.fromOffset(TEXT_X, 3),
		Size = UDim2.fromOffset(TEXT_WIDTH, 13),
		Font = Ui.FontLight,
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
	})
	numberLabel = Ui.label(counter, "CoinCount", "+0", NUMBER_SIZE, {
		Position = UDim2.fromOffset(TEXT_X, 14),
		Size = UDim2.fromOffset(TEXT_WIDTH, 24),
		TextColor3 = C.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.3,
	})
	layer = Ui.frame(root, "CoinLayer", { Size = UDim2.fromScale(1, 1) })
	resetCount()

	-- 코인 소리: 여러 개를 돌려 써서 빨리 이어져도 앞 소리가 끊기지 않게
	local folder = Instance.new("Folder")
	folder.Name = "RoflyCoinSounds"
	for i = 1, 6 do
		local sound = Instance.new("Sound")
		sound.Name = "Coin" .. tostring(i)
		sound.SoundId = FX.SoundId
		sound.Volume = FX.SoundVolume
		sound.Parent = folder
		table.insert(sounds, sound)
	end
	folder.Parent = SoundService

	State.on("Results", function(data: any)
		if type(data) == "table" and type(data.me) == "table" and type(data.me.coins) == "number" then
			official = data.me.coins
			counter:SetAttribute("Official", data.me.coins)
		end
	end)
end

return CoinFx
