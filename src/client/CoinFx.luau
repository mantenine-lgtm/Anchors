-- 보유 코인 칸과 비행 중 코인 연출: 화면 오른쪽 위 티켓 칸 옆에 '보유 코인' 칸을 늘 두고, 비행 중에는 번 코인이
-- 내 캐릭터로 모였다가 칸으로 날아 들어갈 때마다 보유 코인 숫자를 올립니다. 칸 위쪽 작은 글자는 이번 비행으로 번 코인 ('이번 비행 +N').
-- - 거리 코인: 거리만큼 쌓이는 코인은 선실 진행도 전광판의 거리 숫자에서 작게 튀어나와 내 캐릭터로 날아옵니다 (0.3초마다 모아서).
-- - 부스터 코인: 부스터로 더 번 코인(서버가 알려 주는 '그 부스터 하나만 안 쓴 비행'과의 거리 차이, 황금 항로는 늘어난 코인)은
--   부스터 색으로 잠깐 모았다가 그 부스터를 쓴 사람 캐릭터에서 한꺼번에 터져 나와 내 캐릭터로 날아옵니다
--   (쓴 사람을 비추는 클로즈업이 끝나 카메라가 내 캐릭터로 돌아온 뒤에).
-- - 내 캐릭터에 닿은 코인은 머리 둘레를 잠깐 돌고 (무더기가 다 모일 때까지, 길어도 0.8초), 머리 위에 '+N'(부스터면 '+N 터보 엔진')을 띄운 뒤
--   칸으로 날아갑니다. 전광판·쓴 사람이 화면 밖이면 그쪽 화면 가장자리에서 날아옵니다. 칸 숫자는 코인이 칸에 닿을 때 오름.
-- - 내 캐릭터가 화면에 없으면(바깥 시점·클로즈업) 거리 코인은 위쪽 거리 글자에서, 부스터 코인은 화면 가운데에서 바로 칸으로 날아가고
--   '+N'은 칸 아래에 뜹니다.
-- - 한 번에 들어오는 코인이 많을수록 코인 수·크기·퍼지는 폭·글자·고리·반짝임·소리가 커지고, 적으면 작게 들어옵니다.
--   크기는 이번 판 예상 코인(조립 때 예상 거리 × CoinsPerKm)에 대한 비율이라 장비가 좋아져도 같은 비율이면 같은 느낌입니다.
-- - 숫자는 정산과 같은 계산(Scoring.liveCoins, 자리 비움이면 절반)이라 비행이 끝나면 '이번 비행 +N'은 정산 화면의
--   '코인 +N'과, 보유 코인은 서버의 보유 코인과 같아집니다 (정산 코인을 두 번 세지 않음).
-- 수치는 Config.CoinFx. 칸은 모두에게 보이고, 날아오는 코인은 탄 사람에게만 (관전자는 코인을 받지 않음).
-- 코인 그림은 3D 화면 위의 평면 그림이라 가볍고(폰), 월드의 자리(전광판·사람 머리)는 매 프레임 카메라로 화면 자리로 바꿔 씀.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Scoring = require(Shared:WaitForChild("Scoring"))

local Board = require(script.Parent:WaitForChild("Board"))
local BoosterMenu = require(script.Parent:WaitForChild("BoosterMenu"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local CoinFx = {}

local C = Ui.Colors
local FX = Config.CoinFx
local player = Players.LocalPlayer
local rng = Random.new()

-- 칸 배치 (기준 화면 1280x720 단위, 화면 폭은 1280 이상). 오른쪽 위 티켓 칸(오른쪽 끝에서 146) 왼쪽에 붙여 두어
-- 위쪽 가운데 제목(거리·'행성 붕괴까지 0:30'·'로켓 조립 중' 등, 가운데에서 좌우 170 안쪽)과 떨어지고,
-- 아래 끝(48)이 그 밑의 안내 글자(52쯤부터)에 닿지 않습니다.
CoinFx.Right = 176 -- 화면 오른쪽 끝에서 칸 오른쪽 끝까지 (커져도 티켓 칸과 10 띄움)
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
local MAX_PULSE = 0.18 -- 코인이 들어올 때 칸이 커지는 최대 비율 (커져도 티켓 칸에 닿지 않게)
local POPUP_SECONDS = 1.4

-- 내 캐릭터로 모으기 (기준 단위)
local EDGE = 28 -- 화면 밖(전광판·쓴 사람)에서 오는 코인이 나타나는 좌우 가장자리 여백
local EDGE_TOP = 64 -- 위쪽 가장자리 (위쪽 제목·칸 줄 아래)
local BOTTOM_KEEP = 200 -- 아래쪽 미션 판(아래 끝에서 184까지) 자리: 코인이 그 위로 지나가지 않게 비워 둠
local HEAD_MAX_DEPTH = 45 -- 내 머리가 카메라에서 이보다 멀면 (바깥 시점처럼) 머리로 모으지 않음
local ORBIT_RADIUS = 16 -- 머리 둘레를 도는 코인의 가로 반지름 (세로는 절반)
local ORBIT_SPEED = 7 -- 머리 둘레를 도는 빠르기 (라디안/초)
local HOLD_MAX = 0.8 -- 머리 둘레에서 기다리는 가장 긴 시간 (무더기가 다 모이기 전이라도 칸으로)
local HEAD_LABEL_GAP = 6 -- 머리 꼭대기와 '+N' 글자 사이
local HEAD_LABEL_FADE = 0.7 -- '+N' 글자가 떠오르며 사라지는 시간
local HEAD_LABEL_CUT = 0.15 -- 카메라가 내 캐릭터를 떠나면(클로즈업·바깥 시점) '+N' 글자를 이 시간 안에 지움 (안내 글자와 안 겹치게)
local BOOST_WAIT_MAX = 3 -- 클로즈업이 끝나기를 기다려 부스터 코인을 날리는 가장 긴 시간 (모으는 시간 뒤로)
local CAMERA_SETTLE = 0.15 -- 클로즈업이 끝난 뒤 카메라가 내 캐릭터로 돌아와 자리 잡기를 기다리는 시간
-- 화면 가운데의 안내 글자 (Hud: 한 줄 안내·위기 경고·부스터 알림). 내 머리 바로 위가 이 글자들 자리라,
-- 머리 위 '+N'이 이 글자들과 겹치면 그 위로 올림
local HUD_TEXTS = { "Toast", "CrisisLabel", "ItemBanner" }
local HEAD_LABEL_WIDTH = 360

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
	headLeft: number, -- 아직 내 캐릭터에 닿지 않은(바로 칸으로 가기로 정하지도 않은) 그림 수
	headHit: boolean, -- 첫 그림이 내 캐릭터에 닿았는지
	viaHead: boolean, -- 내 캐릭터를 거쳐 감 ('+N'은 머리 위에: 칸 아래에는 안 띄움)
	release: number?, -- 무더기가 다 모여 칸으로 떠나기 시작하는 때 (os.clock)
	gap: number, -- 머리에서 칸으로 떠나는 코인 사이 간격(초)
}

type Sprite = {
	holder: Frame,
	coin: Frame,
	burst: Burst,
	value: number, -- 칸에 닿을 때 더할 코인
	index: number, -- 무더기 안에서 몇 번째인지
	age: number,
	stage: string, -- "out" 터져 나와 떠 있음 | "head" 내 캐릭터로 | "hold" 머리 둘레를 돎 | "pill" 칸으로
	stageAt: number, -- 지금 단계를 시작한 때 (age 기준)
	scatter: number, -- 퍼지는 시간
	flyAt: number, -- 떠 있다가 날아가기 시작하는 때 (age 기준)
	toHead: number, -- 내 캐릭터까지 날아가는 시간
	fly: number, -- 칸까지 날아가는 시간
	fromX: number,
	fromY: number,
	midX: number,
	midY: number,
	legX: number, -- 지금 날아가는 길(내 캐릭터로·칸으로)의 시작점
	legY: number,
	bendX: number,
	bendY: number,
	x: number, -- 지난 프레임 자리
	y: number,
	size: number,
	startScale: number, -- 나올 때 크기 배율 (멀리 있는 전광판에서 나오면 작게 시작해 다가오며 커짐)
	spin: number,
	phase: number,
	orbit: number, -- 머리 둘레를 도는 각도 (시작)
	collected: boolean, -- 내 캐릭터에 닿았는지 (소리는 그때 냄)
}

type HeadLabel = {
	label: TextLabel,
	id: string?, -- 부스터 Id (거리 코인이면 nil)
	serial: number, -- 이 글자를 만든 무더기
	burst: Burst,
	amount: number, -- 지금까지 머리에 닿은 코인 (자리 비움 반영 전)
	power: number,
	born: number, -- os.clock
	last: number, -- 마지막으로 코인이 닿은 때
	released: number?, -- 떠오르며 사라지기 시작한 때
	fadeTime: number, -- 사라지는 데 걸리는 시간 (카메라가 바뀌면 짧게)
	size: number,
	lift: number, -- 머리 위로 쌓인 높이 (먼저 뜬 글자 위로)
	pop: number,
	x: number, -- 머리 꼭대기 자리 (내 캐릭터가 안 보이면 마지막 자리)
	y: number,
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
local flightLabel: TextLabel -- '이번 비행 +N'
local layer: Frame -- 칸 위의 효과 (root 안)
local flyLayer: Frame -- 날아가는 코인 (flyRoot 안)
local gleamFrame: Frame
local sounds: { Sound } = {}
local soundIndex = 0
local lastSound = 0

local sprites: { Sprite } = {}
local effects: { Effect } = {}
local headLabels: { HeadLabel } = {}
local pulse = 0
local glow = 0
local burstSerial = 0
local fittedLength = -1

-- 이번 비행의 코인 셈 (모두 자리 비움 반영 전 값)
local counting = false -- 승무원으로 비행 중이라 코인을 세는 중
local earned = 0 -- 지금까지 번 코인 (정산과 같은 계산. 화면 거리가 잠깐 뒤로 당겨져도 줄지 않게 가장 큰 값)
local claimed = 0 -- 칸으로 날려 보낸 코인 (날아가는 중 + 닿은 것)
local claimedBy: { [string]: number } = {} -- 그중 부스터마다의 몫
local distanceClaimed = 0 -- 그중 거리 코인
local gatherFrom: { [string]: number } = {} -- 부스터 코인을 모으기 시작한 때 (os.clock)
local landed = 0 -- 칸에 닿은 코인 = 화면 숫자
local lastDistance = 0
local official: number? = nil -- 정산에서 받은 코인 (자리 비움 반영 후)
local lastPhase = ""
local userSeat: { [string]: number } = {} -- 부스터마다 쓴 사람의 승무원 번호 (그 사람 캐릭터에서 코인이 나옴)

-- 이번 프레임의 내 머리 (기준 단위). 기본 카메라가 내 캐릭터를 따라가고 머리가 화면 안에 보일 때만 headOn
local headOn = false
local headX, headY = 0, 0
local headTopY = 0 -- 머리 꼭대기 ('+N' 글자 자리)
local headDepth = 1 -- 카메라에서 머리까지 거리 (스터드)
local headFresh = false -- 이번 프레임에 머리가 다시 보이기 시작함 (카메라가 바뀜)
local labelBase = 0 -- 머리 위 '+N' 글자 묶음의 아래 끝 (안내 글자와 겹치면 그 위로)
local labelDodge = 0 -- 안내 글자를 피해 글자 묶음을 머리 위에서 더 올린 만큼
local closeupSeen = -math.huge -- 클로즈업을 마지막으로 본 때 (os.clock)
local hudTexts: { GuiObject } = {}

-- 보유 코인 (칸의 큰 숫자). 서버는 정산 때 한꺼번에 보유 코인을 늘리므로, 비행 중에는 화면에서 따로 셈
local inFlight = false -- 탄 사람: 비행 시작 ~ 정산 코인이 다 날아와 닿을 때까지 '비행 전 보유 코인 + 닿은 코인'을 보임
local walletBase = 0 -- 비행을 시작할 때의 보유 코인 + 비행 중에 따로 받은 코인 (감사·디버그)
local flightOver = false -- 비행 끝 신호를 받음: 이 뒤로 늘어나는 보유 코인은 정산 몫이라 더하지 않음 (날아와 닿으며 오름)
local lastWallet = 0
local walletAfter: number? = nil -- 정산 뒤 보유 코인 (서버가 정산 신호에 같이 보냄)
local lastValue = -1 -- 지난 프레임에 칸에 적은 보유 코인
local arrivedNow = false -- 이번 프레임에 코인이 칸에 닿았는지

-- 부스터 코인을 나눠 줄 순서: 황금 항로가 먼저 (정산의 '황금 항로 +N'과 끝까지 같게), 다른 부스터는 나중에 쓴 것부터.
-- 부스터끼리 겹쳐 세는 거리(터보 중에 쓴 웜홀은 터보 덕에 더 멀리 감: 두 부스터 몫에 다 들어감)는 먼저 쓴 부스터가
-- 그 뒤에 받아서, 방금 쓴 부스터의 코인이 한 무더기로 다 나옴
local ORDER: { string } = { "Golden" }
for _, info in ipairs(Boosters.List) do
	if info.Id ~= "Golden" then
		table.insert(ORDER, info.Id)
	end
end
local order: { string } = table.clone(ORDER) -- 이번 비행에서 나눠 줄 차례
local usedAt: { [string]: number } = {} -- 부스터를 쓴 것을 본 차례
local usedCount = 0

local function sortOrder()
	table.sort(order, function(a: string, b: string): boolean
		if a == "Golden" or b == "Golden" then
			return a == "Golden" and b ~= "Golden"
		end
		local x, y = usedAt[a] or 0, usedAt[b] or 0
		if x ~= y then
			return x > y
		end
		return a < b
	end)
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

-- 칸에 적는 보유 코인
local function walletCoins(): number
	if inFlight then
		return walletBase + shownCoins()
	end
	return State.myNumber("Coins")
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
	return refW - CoinFx.Right - CoinFx.Width + ICON_X + ICON / 2, CoinFx.Top + CoinFx.Height / 2
end

-- 코인이 다닐 수 있는 곳 (왼쪽, 오른쪽, 위, 아래): 좌우 가장자리 여백 안, 위쪽 제목·칸 줄 아래, 아래쪽 미션 판 위
local function band(refW: number, refH: number): (number, number, number, number)
	return EDGE, refW - EDGE, EDGE_TOP, math.max(refH - BOTTOM_KEEP, EDGE_TOP + 40)
end

-- 월드 좌표 -> 이 화면의 자리(기준 단위), 카메라에서의 깊이, 화면 안(카메라 앞)인지.
-- WorldToScreenPoint 와 AbsolutePosition 은 같은 화면 글자 좌표(맨 위 막대 아래가 0)라 빼면 이 화면 안의 자리가 됨
local function screenPoint(camera: Camera, world: Vector3): (number, number, number, boolean)
	local point, on = camera:WorldToScreenPoint(world)
	local origin = flyRoot.AbsolutePosition
	local scale = flyRoot:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	return (point.X - origin.X) / s, (point.Y - origin.Y) / s, point.Z, on and point.Z > 0
end

-- 코인이 나오는 화면 자리: 그 점이 화면에 보이면 그 자리(다닐 수 있는 곳 안으로 당김), 안 보이면 카메라에서 본 그쪽
-- 방향의 화면 가장자리. 돌려줌: x, y, 깊이, 화면에 보이는지
local function sourcePoint(camera: Camera, world: Vector3): (number, number, number, boolean)
	local refW, refH = refSize()
	local left, right, top, bottom = band(refW, refH)
	local x, y, depth, on = screenPoint(camera, world)
	if on then
		return math.clamp(x, left, right), math.clamp(y, top, bottom), depth, true
	end
	-- 카메라에서 본 방향 (화면 오른쪽 +x, 아래쪽 +y). 카메라 바로 뒤면 오른쪽에서
	local rel = camera.CFrame:PointToObjectSpace(world)
	local dx, dy = rel.X, -rel.Y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-3 then
		dx, dy, length = 1, 0, 1
	end
	dx, dy = dx / length, dy / length
	local cx, cy = (left + right) * 0.5, (top + bottom) * 0.5
	local t = math.huge
	if dx > 1e-3 then
		t = math.min(t, (right - cx) / dx)
	elseif dx < -1e-3 then
		t = math.min(t, (left - cx) / dx)
	end
	if dy > 1e-3 then
		t = math.min(t, (bottom - cy) / dy)
	elseif dy < -1e-3 then
		t = math.min(t, (top - cy) / dy)
	end
	return cx + dx * t, cy + dy * t, depth, false
end

-- 내 머리가 이번 프레임 화면 어디인지 (기본 카메라가 내 캐릭터를 따라가고 머리가 다닐 수 있는 곳 안에 보일 때만 headOn)
local function updateHead()
	local was = headOn
	headOn = false
	if CameraRig.closeupActive() then
		closeupSeen = os.clock()
	end
	if not CameraRig.followsMe() then
		return
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom or head == nil or not head:IsA("BasePart") then
		return
	end
	local refW, refH = refSize()
	local left, right, top, bottom = band(refW, refH)
	local x, y, depth, on = screenPoint(camera, head.Position)
	if not on or depth > HEAD_MAX_DEPTH or x < left or x > right or y < top + 20 or y > bottom - 20 then
		return
	end
	local _, topY = screenPoint(camera, head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.3, 0))
	headOn = true
	headFresh = not was
	headX, headY = x, y
	headTopY = math.clamp(topY, top, y - 8)
	headDepth = math.max(depth, 1)
end

-- 머리 둘레를 도는 코인의 자리 (t: 돌기 시작한 뒤 초)
local function orbitPoint(s: Sprite, t: number): (number, number)
	local angle = s.orbit + t * ORBIT_SPEED
	return headX + math.cos(angle) * ORBIT_RADIUS, headY - 4 + math.sin(angle) * ORBIT_RADIUS * 0.5
end

-- 화면 가운데의 안내 글자들을 찾아 둠 (Hud 가 만든 것)
local function findHudTexts()
	if #hudTexts > 0 then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("RoflyHud")
	local hudRoot = hud and hud:FindFirstChild("Root")
	if hudRoot == nil then
		return
	end
	for _, name in ipairs(HUD_TEXTS) do
		local item = hudRoot:FindFirstChild(name)
		if item and item:IsA("GuiObject") then
			table.insert(hudTexts, item)
		end
	end
end

-- 머리 위 글자 묶음(아래 끝 bottom, 높이 height)이 보이는 안내 글자와 겹치면 그 글자 위로 올린 아래 끝
local function clearOfHud(x: number, bottom: number, height: number): number
	findHudTexts()
	local origin = flyRoot.AbsolutePosition
	local scale = flyRoot:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	for _ = 1, #HUD_TEXTS do
		local moved = false
		for _, item in ipairs(hudTexts) do
			if item.Visible and item.Parent ~= nil then
				local position, size = item.AbsolutePosition, item.AbsoluteSize
				local top = (position.Y - origin.Y) / s
				local low = (position.Y + size.Y - origin.Y) / s
				local left = (position.X - origin.X) / s
				local right = (position.X + size.X - origin.X) / s
				if bottom > top and bottom - height < low and x + HEAD_LABEL_WIDTH / 2 > left and x - HEAD_LABEL_WIDTH / 2 < right then
					bottom = top - 4
					moved = true
				end
			end
		end
		if not moved then
			break
		end
	end
	return bottom
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
	local x = refW - CoinFx.Right
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

-- 칸(또는 내 캐릭터)에서 퍼지는 고리 (조금 큰 무더기부터). at: "Pill" | "Head"
local function ring(burst: Burst, x: number, y: number, parent: Instance, at: string)
	local frame = Ui.frame(parent, "CoinRing", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(ICON, ICON),
		ZIndex = 3,
	})
	frame:SetAttribute("At", at)
	round(frame)
	local stroke = Ui.stroke(frame, burst.color, 3 + 4 * burst.power, 0.1)
	addEffect({ frame = frame, age = 0, life = 0.35 + 0.3 * burst.power, kind = "ring", x = x, y = y, vx = 0, vy = 0, size = ICON, grow = 50 + 170 * burst.power, stroke = stroke })
end

-- 칸(또는 내 캐릭터)에서 튀어 나가는 반짝이 (큰 무더기)
local function sparks(burst: Burst, x: number, y: number, parent: Instance, at: string)
	local count = math.floor(4 + 10 * burst.power)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber() * 0.5
		local speed = 90 + 160 * burst.power * (0.6 + 0.4 * rng:NextNumber())
		local size = 6 + 6 * burst.power
		local spark = Ui.frame(parent, "CoinSpark", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			Rotation = 45,
			BackgroundColor3 = if i % 2 == 0 then GOLD_LIGHT else burst.color,
			BackgroundTransparency = 0,
			ZIndex = 4,
		})
		spark:SetAttribute("At", at)
		addEffect({ frame = spark, age = 0, life = 0.45 + 0.2 * burst.power, kind = "spark", x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, size = size, grow = 0, stroke = nil })
	end
end

-- 가장 큰 무더기: 화면 전체가 금빛으로 살짝 번쩍
local function gleam(power: number)
	gleamFrame.BackgroundTransparency = 1 - 0.18 * power
	Ui.tween(gleamFrame, 0.6, { BackgroundTransparency = 1 })
end

-- ------------------------------------------------------------ 날리기
-- 코인 amount 개를 한 무더기로 날림. id 가 있으면 부스터 코인, 없으면 거리 코인.
-- 내 캐릭터가 보이면: 거리 코인은 전광판 거리 숫자에서, 부스터 코인은 쓴 사람 캐릭터에서 나옴 (화면 밖이면 그쪽 가장자리에서).
-- 안 보이면: 거리 코인은 위쪽 거리 글자에서, 부스터 코인은 화면 가운데에서 나와 바로 칸으로
local function launch(id: string?, amount: number)
	if amount < 1 then
		return
	end
	local power = CoinFx.powerOf(amount, expectedCoins())
	local maxCount = if id ~= nil then FX.MaxPerBurst else FX.DistanceMaxSprites
	local wanted = math.clamp(math.floor(1 + (maxCount - 1) * power ^ 1.2 + 0.5), 1, maxCount)
	-- 화면에 이미 많이 날아다니면 줄여서 날림. 그래도 하나는 날림 (숫자는 코인 그림이 칸에 닿을 때만 오름)
	local count = math.max(1, math.min(wanted, FX.MaxSprites - #sprites))
	burstSerial += 1
	local color = if id ~= nil then BoosterMenu.colorOf(id) else GOLD_LIGHT
	local burst: Burst = {
		serial = burstSerial,
		id = id,
		amount = amount,
		power = power,
		count = count,
		left = count,
		landed = false,
		color = color,
		headLeft = count,
		headHit = false,
		viaHead = false,
		release = nil,
		gap = if id ~= nil then math.clamp(0.6 / math.max(count, 1), 0.015, 0.05) else 0.05,
	}
	-- 검사 도구와 디버그용: 마지막 무더기
	counter:SetAttribute("Bursts", burstSerial)
	counter:SetAttribute("LastBooster", id or "")
	counter:SetAttribute("LastAmount", amount)
	counter:SetAttribute("LastPower", power)
	counter:SetAttribute("LastSprites", burst.count)
	local refW, refH = refSize()
	local left, right, top, bottom = band(refW, refH)
	-- 코인이 나오는 곳
	local source = if id ~= nil then "Center" else "Title"
	local sx, sy = refW * 0.5, if id ~= nil then refH * 0.5 else 34
	local startScale = 1
	local camera = Workspace.CurrentCamera
	if headOn and camera ~= nil then
		local world: Vector3? = nil
		if id == nil then
			world = Board.coinSource()
		else
			local member = State.memberPart(userSeat[id] or 0)
			world = if member then member.Position else nil
		end
		if world ~= nil then
			local x, y, depth, on = sourcePoint(camera, world)
			sx, sy = x, y
			source = if not on then "Edge" elseif id == nil then "Board" else "Member"
			if on then
				startScale = math.clamp(headDepth / math.max(depth, 1), 0.5, 1)
			end
		end
	end
	-- 화면 가장자리에서 나오면 화면 안쪽으로 퍼짐
	local inward = math.atan2((top + bottom) * 0.5 - sy, (left + right) * 0.5 - sx)
	local size = if id ~= nil then 16 + 22 * power else 15 + 10 * power
	local scatter = if id ~= nil then 0.22 + 0.25 * power elseif source == "Title" then 0.16 else 0.12
	local gap = if id ~= nil then math.clamp(0.9 / count, 0.025, 0.07) elseif source == "Title" then 0.07 else 0.04
	for i = 1, count do
		-- 코인을 그림마다 고르게 나눔 (그림이 코인보다 많으면 일부는 0)
		local value = math.floor(amount * i / count) - math.floor(amount * (i - 1) / count)
		local fromX, fromY, midX, midY
		if source == "Title" then
			-- 거리 글자에서 튀어나와 살짝 뜸
			fromX = refW * 0.5 + (rng:NextNumber() - 0.5) * 90
			fromY = 34
			midX = fromX + (rng:NextNumber() - 0.3) * 30
			midY = 14 + rng:NextNumber() * 8
		elseif id == nil then
			-- 전광판(또는 그쪽 가장자리)에서 톡 튀어나옴
			local angle = if source == "Edge" then inward + (rng:NextNumber() - 0.5) * 1.2 else math.rad(-150 + 120 * rng:NextNumber())
			local reach = 14 + 18 * rng:NextNumber()
			fromX = sx + (rng:NextNumber() - 0.5) * 24
			fromY = sy + (rng:NextNumber() - 0.5) * 12
			midX = fromX + math.cos(angle) * reach
			midY = fromY + math.sin(angle) * reach
		else
			-- 쓴 사람(또는 화면 가운데·그쪽 가장자리)에서 터져 나옴: 가장자리면 화면 안쪽으로, 아니면 위쪽 반원으로 (미션 판은 가리지 않게)
			local angle = if source == "Edge" then inward + (rng:NextNumber() - 0.5) * 2.2 else math.rad(-172 + 164 * rng:NextNumber())
			local reach = (50 + 250 * power) * (0.35 + 0.65 * rng:NextNumber())
			fromX = sx + (rng:NextNumber() - 0.5) * 30
			fromY = sy + (rng:NextNumber() - 0.5) * 20
			midX = sx + math.cos(angle) * reach
			midY = sy + math.sin(angle) * reach * 0.75
		end
		if source ~= "Title" then
			fromX, fromY = math.clamp(fromX, left, right), math.clamp(fromY, top, bottom)
			midX, midY = math.clamp(midX, left, right), math.clamp(midY, top, bottom)
		end
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
		holder:SetAttribute("Wanted", wanted) -- 한도로 줄이기 전 코인 그림 수
		holder:SetAttribute("Source", source) -- 검사 도구가 봄: Board | Member | Edge | Title | Center
		holder:SetAttribute("Stage", "out")
		table.insert(sprites, {
			holder = holder,
			coin = coin,
			burst = burst,
			value = value,
			index = i,
			age = -rng:NextNumber() * 0.05,
			stage = "out",
			stageAt = 0,
			scatter = scatter,
			flyAt = scatter + (i - 1) * gap + rng:NextNumber() * 0.04,
			toHead = 0.5,
			fly = 0.4,
			fromX = fromX,
			fromY = fromY,
			midX = midX,
			midY = midY,
			legX = midX,
			legY = midY,
			bendX = 0,
			bendY = 0,
			x = fromX,
			y = fromY,
			size = size,
			startScale = startScale,
			spin = 7 + rng:NextNumber() * 6,
			phase = rng:NextNumber() * math.pi * 2,
			orbit = rng:NextNumber() * math.pi * 2,
			collected = false,
		})
	end
end

-- 날아가는 길 하나를 시작함: stage "head"(내 캐릭터로) 또는 "pill"(칸으로), (x, y) 에서 (gx, gy) 쪽으로
local function beginLeg(s: Sprite, stage: string, x: number, y: number, gx: number, gy: number)
	s.stage = stage
	s.stageAt = s.age
	s.legX, s.legY = x, y
	local dx, dy = gx - x, gy - y
	local length = math.max(math.sqrt(dx * dx + dy * dy), 1)
	local boost = s.burst.id ~= nil
	-- 옆으로 휘는 정도 (위쪽 거리 글자에서 바로 칸으로 가는 거리 코인은 화면 위쪽 줄을 따라 가므로 조금만: 화면 밖으로 안 나가게)
	local bend = (rng:NextNumber() - 0.5) * (if boost then 0.5 elseif stage == "head" then 0.35 else 0.2) * length
	s.bendX, s.bendY = -dy / length * bend, dx / length * bend
	if stage == "head" then
		-- 멀리서 오면 조금 더 오래 (가까울수록 빨라짐)
		s.toHead = if boost then math.clamp(length / 900, 0.4, 0.75) else math.clamp(length / 1100, 0.3, 0.55)
	elseif s.collected then
		s.fly = 0.36 + 0.08 * rng:NextNumber()
	else
		s.fly = if boost then 0.42 + 0.12 * rng:NextNumber() else 0.3 + 0.06 * rng:NextNumber()
	end
	s.holder:SetAttribute("Stage", stage)
end

-- 이 그림은 내 캐릭터에 들르지 않고 바로 칸으로 감 (내 캐릭터가 안 보임)
local function skipHead(s: Sprite)
	local burst = s.burst
	burst.headLeft -= 1
	if burst.headLeft <= 0 and burst.release == nil then
		burst.release = os.clock()
	end
end

-- 코인 소리: 작은 코인은 원래 높이 가까이(1.0~1.1). 무더기 안에서 뒤로 갈수록, 큰 무더기일수록 크고 조금 높게 (1.3 까지)
local function coinSound(sprite: Sprite)
	local burst = sprite.burst
	local progress = sprite.index / math.max(burst.count, 1)
	if burst.id == nil and burst.power < 0.6 then
		playSound(FX.SoundSpeedMin + rng:NextNumber() * 0.1, FX.SoundVolume * 0.5)
	else
		local rise = math.clamp(progress * (0.4 + 0.6 * burst.power), 0, 1)
		local speed = FX.SoundSpeedMin + (FX.SoundSpeedMax - FX.SoundSpeedMin - 0.05) * rise + rng:NextNumber() * 0.05
		playSound(speed, FX.SoundVolume + 0.3 * burst.power)
	end
end

-- 머리 위 '+N' 글자
local function headLabelText(h: HeadLabel): string
	local text = "+" .. Fmt.comma(math.floor(h.amount * afkFactor()))
	if h.id ~= nil then
		local info = Boosters.get(h.id)
		text ..= " " .. (if info then info.Name else "부스터")
	end
	if h.power >= 0.7 then
		text ..= "!"
	end
	return text
end

-- 내 캐릭터에 닿은 코인을 머리 위 '+N'에 더함. 거리 코인은 한 글자에 잠깐씩 모으고, 부스터 코인은 무더기마다 한 글자
local function addHeadLabel(burst: Burst, value: number)
	local now = os.clock()
	local entry: HeadLabel? = nil
	for _, h in ipairs(headLabels) do
		if h.released == nil and ((burst.id == nil and h.id == nil) or (burst.id ~= nil and h.serial == burst.serial)) then
			entry = h
			break
		end
	end
	if entry == nil then
		if #headLabels == 0 then
			local base = headTopY - HEAD_LABEL_GAP
			labelDodge = base - clearOfHud(headX, base, 24)
			labelBase = base - labelDodge
		end
		local label = Ui.label(flyLayer, "CoinHead", "", 16, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(headX, labelBase),
			Size = UDim2.fromOffset(360, 44),
			TextColor3 = if burst.id ~= nil then burst.color else GOLD_LIGHT,
			TextStrokeTransparency = 0.15,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			ZIndex = 5,
		})
		label:SetAttribute("Burst", burst.serial)
		label:SetAttribute("Booster", burst.id or "")
		entry = {
			label = label,
			id = burst.id,
			serial = burst.serial,
			burst = burst,
			amount = 0,
			power = 0,
			born = now,
			last = now,
			released = nil,
			fadeTime = HEAD_LABEL_FADE,
			size = 16,
			lift = 0,
			pop = 0,
			x = headX,
			y = labelBase,
		}
		table.insert(headLabels, entry :: HeadLabel)
	end
	local h = entry :: HeadLabel
	h.amount += value
	h.last = now
	h.pop = 1
	-- 부스터 글자는 그 무더기 크기, 거리 글자는 모인 양만큼 (작게: 15~22)
	h.power = if burst.id ~= nil then burst.power else CoinFx.powerOf(h.amount, expectedCoins())
	h.size = if burst.id ~= nil then math.floor(18 + 16 * burst.power + 0.5) else math.floor(15 + 7 * h.power + 0.5)
	h.label.Text = headLabelText(h)
	h.label:SetAttribute("Amount", h.amount)
	h.label:SetAttribute("Power", h.power)
	h.label:SetAttribute("Size", h.size) -- 검사 도구가 봄: 커졌다 돌아오기 전 글자 크기
end

-- 코인 그림 하나가 내 캐릭터에 닿음: 소리, 머리 위 '+N', 무더기의 첫 코인이면 고리·반짝이 (숫자는 칸에 닿을 때 오름)
local function headArrive(sprite: Sprite)
	local burst = sprite.burst
	sprite.collected = true
	burst.viaHead = true
	burst.headLeft -= 1
	if burst.headLeft <= 0 and burst.release == nil then
		burst.release = os.clock()
	end
	coinSound(sprite)
	addHeadLabel(burst, sprite.value)
	if not burst.headHit then
		burst.headHit = true
		local boost = burst.id ~= nil
		if burst.power >= (if boost then 0.25 else 0.6) then
			ring(burst, headX, headY, flyLayer, "Head")
		end
		if burst.power >= (if boost then 0.55 else 0.8) then
			sparks(burst, headX, headY, flyLayer, "Head")
			playSound(FX.SoundAccentSpeed, FX.SoundVolume + 0.4 * burst.power, true)
		end
	end
end

-- 코인 그림 하나가 칸에 닿음
local function arrive(sprite: Sprite)
	local burst = sprite.burst
	landed += sprite.value
	arrivedNow = true
	burst.left -= 1
	pulse = math.max(pulse, 0.04 + (MAX_PULSE - 0.04) * burst.power)
	glow = math.max(glow, burst.power)
	if not sprite.collected then
		coinSound(sprite) -- 내 캐릭터를 거친 코인은 그때 소리를 냄
	end
	if not burst.landed then
		burst.landed = true
		-- 부스터 코인은 글자·고리·반짝이를 더 일찍(작은 양부터) 붙이고, 거리 코인은 평소에는 숫자만 오르게 아주 많을 때만.
		-- 내 캐릭터를 거친 무더기는 '+N'·반짝이를 머리 위에서 이미 보였으므로 칸에서는 고리만
		local boost = burst.id ~= nil
		local x, y = target((refSize()))
		if not burst.viaHead and (boost or burst.power >= 0.6) then
			popup(burst)
		end
		if burst.power >= (if boost then 0.25 else 0.6) then
			ring(burst, x, y, layer, "Pill")
		end
		if not burst.viaHead and burst.power >= (if boost then 0.55 else 0.8) then
			sparks(burst, x, y, layer, "Pill")
			playSound(FX.SoundAccentSpeed, FX.SoundVolume + 0.4 * burst.power, true)
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
	table.clear(usedAt)
	table.clear(userSeat)
	usedCount = 0
	sortOrder()
	lastDistance = 0
	official = nil
	walletAfter = nil
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
	for _, h in ipairs(headLabels) do
		h.label:Destroy()
	end
	table.clear(headLabels)
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
	for _, info in ipairs(Boosters.List) do
		if usedAt[info.Id] == nil and State.flag(Boosters.usedAttribute(info.Id)) then
			usedCount += 1
			usedAt[info.Id] = usedCount
			sortOrder()
		end
	end
	local othersClaimed = 0 -- 황금 항로가 아닌 부스터로 날린 코인
	for id, amount in pairs(claimedBy) do
		if id ~= "Golden" then
			othersClaimed += amount
		end
	end
	local othersPending = 0 -- 그 부스터들이 모으는 중인 코인 (이 줄에서는 지금 부스터보다 나중에 쓴 것들의 몫)
	for _, id in ipairs(order) do
		local due = (shares[id] or 0) - (claimedBy[id] or 0)
		if due >= 1 then
			local started = gatherFrom[id]
			if started == nil then
				started = clock
				gatherFrom[id] = clock
			end
			-- 쓴 사람을 비추는 클로즈업이 끝나 카메라가 내 캐릭터로 돌아온 뒤에 날림 (너무 오래 기다리면 그냥)
			local waited = clock - started
			local settling = clock - closeupSeen < CAMERA_SETTLE
			if flush or (waited >= FX.BoostGather and (not settling or waited >= FX.BoostGather + BOOST_WAIT_MAX)) then
				local room = earned - claimed
				if id ~= "Golden" then
					room = math.min(room, plain - distanceClaimed - othersClaimed - othersPending)
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
	local refW, refH = refSize()
	local tx, ty = target(refW)
	local _, _, _, bottom = band(refW, refH)
	local clock = os.clock()
	for i = #sprites, 1, -1 do
		local s = sprites[i]
		local burst = s.burst
		s.age += dt
		-- 단계 넘기기: 떠 있다가 -> 내 캐릭터로 (안 보이면 바로 칸으로) -> 머리 둘레 -> 칸으로
		if s.stage == "out" and s.age >= s.flyAt then
			if headOn then
				local gx, gy = orbitPoint(s, 0)
				beginLeg(s, "head", s.midX, s.midY, gx, gy)
			else
				skipHead(s)
				beginLeg(s, "pill", s.midX, s.midY, tx, ty)
			end
		end
		if s.stage == "head" then
			if not headOn then
				skipHead(s)
				beginLeg(s, "pill", s.x, s.y, tx, ty)
			elseif s.age - s.stageAt >= s.toHead then
				s.stage = "hold"
				s.stageAt = s.age
				s.holder:SetAttribute("Stage", "hold")
				headArrive(s)
			end
		end
		if s.stage == "hold" then
			-- 무더기가 다 모이면 잠깐 더 돌다가 차례로 칸으로
			local release = burst.release
			if
				not headOn
				or s.age - s.stageAt >= HOLD_MAX
				or (release ~= nil and clock >= release + FX.HeadHold + (s.index - 1) * burst.gap)
			then
				beginLeg(s, "pill", s.x, s.y, tx, ty)
			end
		end
		if s.stage == "pill" and s.age - s.stageAt >= s.fly then
			arrive(s)
			s.holder:Destroy()
			table.remove(sprites, i)
			continue
		end
		local x, y, scale
		if s.stage == "out" then
			if s.age < 0 then
				x, y, scale = s.fromX, s.fromY, 0.01
			elseif s.age < s.scatter then
				-- 터져 나옴
				local u = s.age / s.scatter
				local e = 1 - (1 - u) * (1 - u)
				x = s.fromX + (s.midX - s.fromX) * e
				y = s.fromY + (s.midY - s.fromY) * e
				scale = (0.35 + 0.65 * e) * s.startScale
			else
				-- 잠깐 떠 있음
				x = s.midX
				y = s.midY + math.sin((s.age - s.scatter) * 9 + s.phase) * 2
				scale = s.startScale
			end
		elseif s.stage == "head" then
			-- 내 캐릭터로 끌려옴 (머리 자리는 매 프레임 다시 봄: 걸어도 따라감)
			local u = math.clamp((s.age - s.stageAt) / s.toHead, 0, 1)
			local e = u * u * (3 - 2 * u)
			local gx, gy = orbitPoint(s, 0)
			local cx = (s.legX + gx) * 0.5 + s.bendX
			local cy = (s.legY + gy) * 0.5 + s.bendY
			local a = 1 - e
			x = a * a * s.legX + 2 * a * e * cx + e * e * gx
			y = a * a * s.legY + 2 * a * e * cy + e * e * gy
			scale = s.startScale + (1 - s.startScale) * e
		elseif s.stage == "hold" then
			-- 머리 둘레를 돎
			x, y = orbitPoint(s, s.age - s.stageAt)
			scale = 0.8
		else
			-- 칸으로 빨려 들어감 (가까울수록 빨라짐)
			local u = math.clamp((s.age - s.stageAt) / s.fly, 0, 1)
			local e = u ^ 1.8
			local cx = (s.legX + tx) * 0.5 + s.bendX
			local cy = (s.legY + ty) * 0.5 + s.bendY
			local a = 1 - e
			x = a * a * s.legX + 2 * a * e * cx + e * e * tx
			y = a * a * s.legY + 2 * a * e * cy + e * e * ty
			scale = (if s.collected then 0.8 else 1) * (1 - 0.35 * e)
		end
		-- 화면 안, 아래쪽 미션 판 위로만
		x = math.clamp(x, 0, refW)
		y = math.clamp(y, 0, bottom)
		s.x, s.y = x, y
		local px = s.size * scale
		s.holder.Position = UDim2.fromOffset(x, y)
		s.holder.Size = UDim2.fromOffset(px, px)
		-- 동전이 도는 모습: 좌우 폭만 줄었다 늘었다
		local flip = math.abs(math.cos(math.max(s.age, 0) * s.spin + s.phase))
		s.coin.Size = UDim2.fromScale(math.max(flip, 0.2), 1)
	end
end

-- 머리 위 '+N' 글자: 코인이 더 안 오면(부스터는 무더기가 다 모이면) 떠오르며 사라짐. 여러 개면 위로 쌓음
local function updateHeadLabels(dt: number)
	if #headLabels == 0 then
		return
	end
	local now = os.clock()
	for _, h in ipairs(headLabels) do
		local released = h.released
		if released == nil then
			local quiet = now - h.last
			local done
			if h.id == nil then
				done = quiet > 0.45 or now - h.born > FX.HeadLabelSeconds
			else
				done = (h.burst.headLeft <= 0 and quiet > 0.5) or quiet > 1.2
			end
			if not headOn then
				h.released, h.fadeTime = now, HEAD_LABEL_CUT
			elseif done then
				h.released = now
			end
		elseif not headOn and h.fadeTime > HEAD_LABEL_CUT then
			-- 사라지던 글자도 카메라가 바뀌면 빨리 (지금 흐린 정도에서 이어서)
			local u = (now - released) / h.fadeTime
			h.released, h.fadeTime = now - u * HEAD_LABEL_CUT, HEAD_LABEL_CUT
		end
	end
	-- 거리 '+N'이 머리에 가장 가깝게, 그 위로 부스터 '+N'(먼저 생긴 것부터)
	local stack = 0
	for pass = 1, 2 do
		for _, h in ipairs(headLabels) do
			if h.released == nil and ((pass == 1) == (h.id == nil)) then
				h.lift += (stack - h.lift) * math.min(1, dt * 12)
				stack += h.size + 4
			end
		end
	end
	if headOn then
		-- 머리 바로 위 (걸어도 바로 따라감). 안내 글자와 겹치면 그 위로: 떠오르며 사라지는 글자까지 비키게 높이를 잼.
		-- 새 안내 글자가 뜨면 빠르게 올리고, 내려올 때는 천천히. 카메라가 바뀌었거나 많이 옮기면 바로
		local extent = math.max(stack, 24)
		for _, h in ipairs(headLabels) do
			local released = h.released
			if released ~= nil then
				extent = math.max(extent, h.lift + h.size + 30 * math.min((now - released) / h.fadeTime, 1))
			end
		end
		local base = headTopY - HEAD_LABEL_GAP
		local dodge = base - clearOfHud(headX, base, extent)
		local rate = if dodge > labelDodge then 30 else 10
		labelDodge = if headFresh or math.abs(dodge - labelDodge) > 200 then dodge else labelDodge + (dodge - labelDodge) * math.min(1, dt * rate)
		labelBase = base - labelDodge
	end
	for i = #headLabels, 1, -1 do
		local h = headLabels[i]
		local fade, rise = 0, 0
		local released = h.released
		if released ~= nil then
			local u = (now - released) / h.fadeTime
			if u >= 1 then
				h.label:Destroy()
				table.remove(headLabels, i)
				continue
			end
			fade, rise = u, 30 * u
		end
		if headOn then
			h.x, h.y = headX, labelBase
		end
		h.pop *= math.exp(-dt * 10)
		h.label.Position = UDim2.fromOffset(h.x, h.y - h.lift - rise)
		h.label.TextSize = math.max(1, math.floor(h.size * (1 + 0.25 * h.pop) + 0.5))
		h.label.TextTransparency = fade
		h.label.TextStrokeTransparency = 0.15 + 0.85 * fade
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
	local value = walletCoins()
	if lastValue >= 0 and value > lastValue and not arrivedNow then
		-- 날아온 코인이 아닌 것으로 늘어남 (감사 코인·디버그): 살짝 커졌다 돌아옴
		pulse = math.max(pulse, 0.08)
		glow = math.max(glow, 0.4)
	end
	lastValue = value
	arrivedNow = false
	local text = Fmt.comma(value)
	numberLabel.Text = text
	fitNumber(text)
	-- 이번 비행으로 번 코인: 탄 사람에게 비행 ~ 정산 동안
	local flight = shownCoins()
	local showFlight = inFlight or (official ~= nil and State.phase() == "Results")
	flightLabel.Visible = showFlight
	if showFlight then
		flightLabel.Text = "이번 비행 +" .. Fmt.comma(flight)
	end
	counter:SetAttribute("Wallet", value) -- 검사 도구가 봄
	counter:SetAttribute("Shown", flight)
	counter:SetAttribute("Landed", landed)
	counter:SetAttribute("InFlight", inFlight)
end

function CoinFx.update(dt: number)
	local phase = State.phase()
	local crew = State.role() == "Crew"
	local wallet = State.myNumber("Coins")
	if phase ~= lastPhase then
		local previous = lastPhase
		lastPhase = phase
		if phase == "Flight" then
			clearSprites()
			resetCount()
			counting = crew
			inFlight = crew
			flightOver = false
			walletBase = wallet
			lastWallet = wallet
		elseif previous == "Flight" and counting then
			-- 비행이 끝남: 남은 코인을 모두 날려 보냄 (정산 값과 같아짐)
			collect(true)
			counting = false
			flightOver = true
		end
		if phase == "Join" then
			counting = false
			inFlight = false
			clearSprites()
			resetCount()
		end
	end
	updateHead()
	if counting and phase == "Flight" then
		collect(false)
	end
	if inFlight then
		local change = wallet - lastWallet
		if change ~= 0 and (not flightOver or change < 0) then
			-- 비행 중에 따로 받거나 쓴 코인 (감사·디버그). 비행이 끝난 뒤 늘어나는 것은 정산 몫이라 빼고, 줄어드는 것(정산 중 뽑기)은 바로 뺌
			walletBase += change
			if flightOver and walletAfter ~= nil then
				walletAfter = (walletAfter :: number) + change
			end
		end
		if official ~= nil and not counting and #sprites == 0 and wallet >= (walletAfter or 0) then
			inFlight = false -- 정산 코인이 다 날아와 닿았고 서버의 보유 코인에도 들어감: 이제 그 값을 그대로 보임
		end
	end
	lastWallet = wallet
	animateSprites(dt)
	updateHeadLabels(dt)
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
		Position = UDim2.new(1, -(CoinFx.Right + CoinFx.Width / 2), 0, CoinFx.Top + CoinFx.Height / 2),
		Size = UDim2.fromOffset(CoinFx.Width, CoinFx.Height),
		BackgroundTransparency = 0.3,
	})
	counterStroke = Ui.stroke(counter, GOLD, 2, 0.35)
	counterScale = Ui.make("UIScale", { Parent = counter })
	local icon = makeCoin(counter, "CoinIcon", ICON, nil, nil)
	icon.Position = UDim2.fromOffset(ICON_X + ICON / 2, CoinFx.Height / 2)
	Ui.label(counter, "CoinCaption", "보유 코인", CAPTION_SIZE, {
		Position = UDim2.fromOffset(TEXT_X, 3),
		Size = UDim2.fromOffset(TEXT_WIDTH, 13),
		Font = Ui.FontLight,
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
	})
	flightLabel = Ui.label(counter, "CoinFlight", "", CAPTION_SIZE, {
		Position = UDim2.fromOffset(TEXT_X, 3),
		Size = UDim2.fromOffset(TEXT_WIDTH, 13),
		TextColor3 = GOLD_LIGHT,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
		Visible = false,
	})
	numberLabel = Ui.label(counter, "CoinCount", "0", NUMBER_SIZE, {
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

	State.on("FlightEnd", function(_info: any)
		flightOver = true
	end)
	State.on("ItemUsed", function(info: any)
		-- 부스터 코인은 그 부스터를 쓴 사람 캐릭터에서 나옴
		if type(info) == "table" and type(info.item) == "string" and type(info.seat) == "number" then
			userSeat[info.item] = info.seat
		end
	end)
	State.on("Results", function(data: any)
		if type(data) == "table" and type(data.me) == "table" and type(data.me.coins) == "number" then
			official = data.me.coins
			if type(data.me.wallet) == "number" then
				walletAfter = data.me.wallet
				-- 정산 전 보유 코인 (비행 중 따로 받은 코인 포함). 신호가 어떤 순서로 와도 끝 숫자가 서버와 같게 다시 맞춤
				walletBase = data.me.wallet - data.me.coins
			end
			counter:SetAttribute("Official", data.me.coins)
		end
	end)
end

return CoinFx
