--!strict
-- ROFLY 데모 1의 모든 수치. 밸런스는 이 파일만 고치면 됩니다.
-- 비행 수치는 기획서 '수치 밸런스' 탭 1차 안(시뮬레이터 v8)과 같습니다.
-- 단, 데모 1에는 인접 시너지가 없어서(그리드의 어느 칸에 꽂아도 수치는 같음) 탭의 표(시너지 포함)보다 조금 짧게 납니다
-- (기본인 일반 Lv1 10명은 약 1%, 전설 Lv10 50명은 약 12%. 그래서 최대 구성도 80만 km 탈출에는 조금 못 미칩니다).
-- 맞춰 볼 값은 시너지 없는 확인값입니다: 일반 Lv1 10개 = 종류별 합계 32.2187, 전원 성공 + 완벽한 발사 26.9741 km, 82.05초.
-- "임시"라고 적힌 값은 기획서에 수치가 없어서 데모 1을 만들며 새로 잡은 값입니다.

local Config = {}

Config.Version = "demo1"

-- 페이즈 길이(초)
Config.Phase = {
	Join = 30, -- 참여 확인 ("붕괴까지" 타이머)
	JoinAllReady = 5, -- 임시: 서버의 모든 사람이 탑승을 누르면 이만큼만 더 기다림 (혼자 테스트할 때 30초를 다 기다리지 않게)
	Build = 45, -- 부품 조립 (기획서 본문 값)
	BuildAllPlaced = 5, -- 임시: 탄 사람이 모두 부품을 다 꽂으면 이만큼만 더 기다림 (혼자 테스트할 때 45초를 다 기다리지 않게)
	Countdown = 10,
	Results = 25, -- 정산 화면 + 다음 행성 슬롯 (임시: 슬롯을 넣으며 20초에서 늘림)
	FlightMax = 600, -- 안전장치: 이보다 길어지면 비행을 끝냄
}

-- 다음 행성 슬롯 (정산 페이즈 안에서, 임시 값): 정산 화면을 StartAfter 초 보여 준 뒤 슬롯이 Spin 초 돌고 멈춤.
-- 멈춘 뒤 정산이 끝날 때까지(25 - 15 - 5 = 5초) 뽑힌 행성을 보여 주고, 판이 끝나면 그 행성으로 바뀝니다.
Config.PlanetSlot = {
	StartAfter = 15,
	Spin = 5,
	Intro = 0.6, -- 돌기 전에 슬롯 판이 먼저 나와 있는 시간
	Cycles = 3, -- 멈추기 전에 후보를 몇 바퀴 돌리는지
	RarePercent = 10, -- 확률이 이 % 이하면 '희귀'로 표시
}

-- 비행 계산 (FlightSim.luau 가 사용)
Config.Flight = {
	Dt = 0.05, -- 계산 한 칸(초)
	RefPower = 1, -- 파워 자릿수 기준: 자릿수 = log10(1 + 합계 / RefPower)
	BaseSpeed = 0.00575, -- 기준 발사 속도 (km/s)
	EngineExp = 0.2, -- 엔진 자릿수 1당 발사 속도 10^0.2배
	HotRate = 0.10, -- 최대 출력 구간: 초당 속도 증가율
	CruiseRate = 0.05, -- 순항 구간
	SailRate = 0.03, -- 솔라 세일 구간
	DecayRate = 0.08, -- 관성 구간: 초당 속도 감소율
	HotBase = 0, -- 최대 출력 시간 = HotBase + HotPerDigit × 방열판 자릿수
	HotPerDigit = 8,
	FuelBase = 16, -- 연료 시간 = FuelBase + FuelPerDigit × 연료탱크 자릿수
	FuelPerDigit = 9,
	SailBase = 14, -- 세일 시간 = SailBase + SailPerDigit × 솔라 세일 자릿수
	SailPerDigit = 11,
	KickBase = 0.40, -- 미션 1회 성공 가속 (항법컴퓨터)
	NavExp = 0.2,
	ComboStepBase = 0.065, -- 콤보 1단계당 가속 증가 (코어)
	CoreExp = 0.2,
	ComboMax = 5,
	PerfectMultiplier = 1.2, -- 전원 성공 보너스
	BoostDecayTime = 12, -- 미션 가속이 줄어드는 시간 상수(초)
	WaveStartRatio = 0.5, -- 충격파 시작 속도 = 로켓 발사 속도 × 이 값
	WaveRate = 0.06, -- 충격파 초당 가속률
	WaveRateGrowth = 0.0003, -- 충격파 가속률이 초마다 커지는 양
	WaveGraceTime = 1.0, -- 발사 직후 이 시간 동안은 따라잡히지 않음
	RouteEnd = 800000, -- 폭발권 밖 (km)
}

-- 방향 미션
Config.Mission = {
	FirstAt = 6, -- 첫 미션 판정 시각(비행 시작 후 초)
	Interval = 9, -- 판정 간격(초)
	ComboRule = 0.8, -- 팀 성공률이 이 이상이면 콤보 +1, 아니면 0
	-- 챕터별 입력 수와 제한 시간(초): 대기권, 지구 궤도, 달, 태양계
	ByChapter = {
		{ Inputs = 3, Limit = 3.0 },
		{ Inputs = 4, Limit = 2.67 },
		{ Inputs = 5, Limit = 2.33 },
		{ Inputs = 6, Limit = 2.0 },
	},
	InputGrace = 0.25, -- 통신 지연 여유(초)
	WrongInputResets = true, -- 틀리면 처음부터 다시 (제한 시간 안에서)
	AfkMissions = 5, -- 이만큼 연속으로 아무 입력이 없으면 판정에서 빠지고 코인 절반
	Keys = { "Up", "Left", "Right", "Down", "Jump" },
	ResultShowSeconds = 1.6,
}

-- 연타 미션 (Nick 11-28, 수치는 임시): 방향 미션 몇 번에 한 번은 연타 미션입니다. Seconds 초 동안 탄 사람 모두가 버튼(또는
-- 스페이스·방향키)을 빠르게 누르고, 로켓 전체의 연타 합계가 클수록 그 미션의 가속이 커집니다.
-- 미션 번호 First, First + Every, First + 2 × Every ... 가 연타 미션 (기본 3·7·11번째 = 비행 24초·60초·96초 판정).
-- 한 사람이 MinTaps 번 이상 누르면 그 사람은 성공. 팀 성공률·콤보·선장(연속 성공)·부품 피버는 방향 미션과 같은 규칙입니다.
-- 연타 단계 = log2(1 + 합계 / Ref), 최대 MaxLevel: 합계가 Ref·3Ref·7Ref·15Ref ... (두 배씩)를 넘을 때마다 1단계 (25·75·175·375 ...).
-- 그 미션의 가속 × (1 + PerLevel × 단계). 혼자 + 봇 9 ≈ 합계 220 → 3.3단계 ×1.66 (거리 약 +11%),
-- 50명 × 25번 → 5.7단계 ×2.13 (약 +21%), 100명 → 6.7단계 ×2.33 (약 +25%). 인원이 늘수록 조금씩만 더 세짐 (인원 효과 완만).
-- 원격 호출이 몰리지 않게 클라이언트는 누른 횟수를 모아서 SendInterval 초마다 한 번(누적 횟수) 보내고,
-- 서버는 합계를 ShowInterval 초마다 RoundState.TapTotal 로 알립니다.
Config.Tap = {
	First = 3,
	Every = 4,
	Seconds = 4, -- 연타 시간 (판정 Seconds + Mission.InputGrace 초 전에 시작)
	MinTaps = 10, -- 한 사람이 이만큼 누르면 성공 (초당 2.5번)
	Ref = 25, -- 연타 단계 기준 합계
	PerLevel = 0.2, -- 단계 1당 미션 가속 +20%
	MaxLevel = 7, -- 합계 3,175번이면 최대
	MaxPerSecond = 20, -- 한 사람이 1초에 셀 수 있는 최대 횟수 (그보다 많이 보내면 잘라냄)
	SendInterval = 0.4, -- 클라이언트가 누른 횟수를 모아서 보내는 간격(초)
	ShowInterval = 0.2, -- 서버가 합계를 알리는 간격(초)
	ExpectedPerPerson = 20, -- 조립 화면 예상 거리에 쓰는 한 사람 연타 수 (초당 5번, 봇 포함)
	BotRateMin = 4, -- 성공하는 봇이 1초에 누르는 횟수 (판마다 이 사이에서 무작위)
	BotRateMax = 7,
	-- 디버그 패널에서 바꾸는 시험 방식. 전부 연타 = 모든 미션이 연타 미션 (폰에서 눌러 보기용)
	Default = "normal",
	Modes = {
		{ Id = "normal", Name = "보통" },
		{ Id = "all", Name = "전부 연타" },
		{ Id = "off", Name = "끄기" },
	},
}

-- 부품 피버타임 (Nick 11-28, 수치는 임시): 방향 미션이 판정될 때마다 로켓에 꽂힌 부품 하나하나가 따로 무작위로
-- 피버에 들어가고, 다음 미션 판정까지 이어집니다 (그때 다시 뽑음). 피버 중인 부품은 둘레에 반짝임이 뜹니다.
-- 부품 주인이 그 미션에 성공했으면 SuccessChance, 아니면(실패·자리 비움·나감) FailChance.
-- 피버 동안 로켓 속도 × (1 + SpeedBonus × 피버 부품 수 / 꽂힌 부품 수): 전부 피버면 +50%.
-- 봇 10명 보통 실력이면 평균 28%가 피버(속도 +14%), 시뮬레이션 200판 평균 거리 +15% (20.2 → 23.3 km).
-- 조립 화면의 예상 거리도 이 평균을 넣어 계산합니다 (Fever.expected).
Config.Fever = {
	SuccessChance = 0.3,
	FailChance = 0.1,
	SpeedBonus = 0.5,
	-- 디버그 패널에서 바꾸는 시험 방식. 전부 피버 = 미션마다 모든 부품이 피버 (반짝임·휴대폰 성능 확인용)
	Default = "normal",
	Modes = {
		{ Id = "normal", Name = "보통" },
		{ Id = "all", Name = "전부 피버" },
		{ Id = "off", Name = "끄기" },
	},
}

-- 선장 발사 버튼
Config.Captain = {
	PerfectWindow = 0.12, -- 0초와의 차이가 이 안이면 완벽
	PerfectBonus = 0.10, -- 초반 속도 +10%
	GoodWindow = 0.35,
	GoodBonus = 0.05,
	EarlyLimit = 1.0, -- 0초보다 이만큼 일찍부터 누를 수 있음
	AutoDelay = 0.6, -- 안 누르면 0초에서 이만큼 지나 자동 발사
	CloseupSeconds = 3, -- 카운트다운 시작 때 선장 클로즈업
	GaugeSeconds = 3, -- 발사 게이지가 움직이는 시간
	AlertSeconds = 5, -- 임시: 카운트다운이 이만큼 남으면 선장 화면에 '발사 임박' 알림 (금색 테두리, 경보음)
	BuildWarnSeconds = 5, -- 임시: 조립이 이만큼 남으면 조립 화면에서 선장에게 곧 카운트다운이라고 미리 알림
}

-- 구원 연료 (임시: 기획서에 수치 없음. 시뮬레이션으로 잡음)
-- 쓰는 순간 로켓 속도를 충격파 속도 × Match 까지 끌어올리고, Hold 초 동안 충격파와 같은 비율(+Extra)로 가속.
-- 신규 10명 기준 위기 막바지에 쓰면 거리 약 1.7~2.2배.
-- 티켓 값은 아래 Config.Boosters 에 있습니다. 클로즈업·감사 버튼 값은 부스터 6종이 함께 씁니다.
Config.Rescue = {
	Match = 1.0,
	Hold = 5,
	Extra = 0,
	CloseupSeconds = 2, -- 사용자 좌석 클로즈업
	ThanksWindow = 5, -- 감사 버튼이 떠 있는 시간(초)
	ThanksGrace = 1, -- 서버가 더 받아 주는 여유(초)
	ThanksCoins = 50, -- 임시: 감사를 누른 사람이 받는 코인 (경제 v9 에서 코인을 10배로 늘리며 5 → 50)
}

-- 부스터: 비행 중에 쓰는 현질 아이템 6종. 화면 왼쪽 메뉴에 떠 있고, 누르면 바로 씁니다.
-- 종류마다 한 비행에 로켓 전체에서 1번 (먼저 누른 사람이 씀). 데모는 Robux 대신 티켓을 씁니다.
-- 효과는 기획서 표 그대로이고, 수치(Seconds, Value)는 임시입니다 (기획서에 수치 없음).
-- 모든 줄이 같은 칸을 갖게 해서 타입 검사가 편하도록, 안 쓰는 칸은 0 입니다.
Config.Boosters = {
	List = {
		-- 위기 구간에서만. 효과 수치는 위의 Config.Rescue
		{ Id = "RescueFuel", Name = "구원 연료", Cost = 1, Seconds = 0, Value = 0, Desc = "위기 때 충격파 속도까지 가속" },
		-- Seconds 초 동안 속도 × Value
		{ Id = "Turbo", Name = "터보 엔진", Cost = 1, Seconds = 20, Value = 2, Desc = "20초간 속도 2배" },
		-- 쓰는 순간 기본 속도 × (1 + Value). 빠를 때 쓸수록 더 많이 빨라짐
		{ Id = "Slingshot", Name = "중력 새총", Cost = 1, Seconds = 0, Value = 0.5, Desc = "지금 속도에 비례해 +50% 가속" },
		-- 지금 속도로 Seconds 초 갈 거리를 순간이동 (충격파는 그대로)
		{ Id = "Wormhole", Name = "웜홀", Cost = 1, Seconds = 15, Value = 0, Desc = "지금 속도로 15초 갈 거리를 순간이동" },
		-- 쓴 뒤로 나는 거리의 코인 × Value (탄 사람 모두)
		{ Id = "Golden", Name = "황금 항로", Cost = 1, Seconds = 0, Value = 2, Desc = "이후 거리의 코인 2배 (모두)" },
		-- Seconds 초 동안 미션 가속 × Value
		{ Id = "Resonance", Name = "공명 코어", Cost = 1, Seconds = 30, Value = 2, Desc = "30초간 미션 보너스 2배" },
	},
	PendingSeconds = 1.5, -- 누른 뒤 서버가 받아 주지 않으면 이만큼 뒤 다시 누를 수 있게 함
}

-- 위기 구간: 충격파 도달 예상 시간이 EnterEta 이하면 시작
Config.Crisis = {
	EnterEta = 10,
	ExitEta = 12.5,
	CheckInterval = 0.25,
	EtaLimit = 30, -- 이보다 먼 도달 시간은 계산하지 않음
	MinFlightTime = 5, -- 발사 직후에는 위기를 띄우지 않음
}

-- 봇 승무원 (데모 전용)
Config.Bots = {
	FillTo = 10, -- 사람이 모자라면 이 인원까지 봇으로 채움
	Skill = "normal",
	-- 챕터별 미션 성공 확률: 대기권, 지구 궤도, 달, 태양계
	Skills = {
		{ Id = "normal", Name = "보통", Rates = { 0.90, 0.85, 0.80, 0.75 } },
		{ Id = "good", Name = "잘함", Rates = { 0.97, 0.94, 0.91, 0.88 } },
		{ Id = "perfect", Name = "전원 성공", Rates = { 1, 1, 1, 1 } },
		{ Id = "fail", Name = "전부 실패", Rates = { 0, 0, 0, 0 } },
	},
	-- 임시: 봇이 감사 하트를 보낼 확률. 혼자 테스트할 때 호응을 보여 주는 연출이며,
	-- 화면의 "감사 N" 에는 들어가고 Output 지표에는 세지 않음. 사람끼리 테스트할 때는 0 으로.
	ThanksChance = 0.7,
}

-- 부품
Config.Parts = {
	Types = {
		{ Id = "engine", Name = "엔진" },
		{ Id = "heat", Name = "방열판" },
		{ Id = "fuel", Name = "연료탱크" },
		{ Id = "sail", Name = "솔라 세일" },
		{ Id = "nav", Name = "항법컴퓨터" },
		{ Id = "core", Name = "코어" },
	},
	RarityNames = { "일반", "희귀", "영웅", "전설" },
	RarityPower = { 10, 100, 1000, 10000 },
	-- 희귀도 색 (일반·희귀·영웅·전설). 머리 뒤 희귀도 구(Config.Halo)와 뽑기 화면이 같이 씀.
	-- 0~255 RGB 숫자 { R, G, B } 로 두고, 쓰는 쪽에서 Color3.fromRGB(c[1], c[2], c[3]) 로 바꿈
	-- (Config 에는 Color3 같은 Roblox 자료형 없이 순수 값만: 검사기가 Config 를 Roblox 없이 불러와 계산을 맞춰 봄)
	-- 구는 Neon 이라 밝게 번져 보이므로 진하고 또렷한 색으로 (옅은 색은 흰빛으로 바래 등급끼리 헷갈림)
	RarityColors = {
		{ 130, 138, 150 }, -- 일반: 회색
		{ 40, 130, 255 }, -- 희귀: 파랑
		{ 140, 60, 255 }, -- 영웅: 보라
		{ 255, 130, 0 }, -- 전설: 주황금
	},
	-- 레벨 배율은 Parts.levelMultiplier (Config.Progress 아래 설명)
	SlotBonus = 0.01, -- 꽂은 부품 1개당 그 종류 합계 +1%
	RankExp = 1, -- 종류별 합계에서 센 순서 k번째 부품은 1 / k^RankExp 만 더함 (인원 효과를 완만하게)
}

-- 희귀도 구 (Nick 11-28): 캐릭터마다 머리 살짝 뒤에 후광처럼 장착 부품 6종의 희귀도 색(Config.Parts.RarityColors)으로
-- 빛나는 작은 구 6개를 띄워, 다른 사람이 그 캐릭터의 부품 희귀도를 볼 수 있게 합니다(색만. 다른 부품 정보는 없음).
-- 구 자리는 부품 종류 순서(Config.Parts.Types)대로 고정: 앞에서 볼 때 왼쪽 어깨 살짝 위(엔진)에서 머리 위를 지나 오른쪽 어깨 살짝 위까지.
-- 크기는 머리 높이 HeadSize 기준이고, 머리가 크거나 작으면 후광·구도 그 비율로 (0.75~1.6배).
-- 폰 사양: 서버는 캐릭터마다 작은 Neon 구 6개(+ Weld 6개)만 만듦. 빛 번짐·맥박·반짝이는 각자 화면(client/HaloFx)이
-- 카메라에 가까운 것만 한도 안에서 붙임. 빛(PointLight)·그림자 없음
Config.Halo = {
	-- 자리 (Nick 11-28: 머리 위가 아니라 후광처럼 머리 살짝 뒤, 어깨 살짝 위부터. 앞에서도 6개가 다 보이게):
	-- 머리 가운데를 둘러싼 원(반지름 Radius)에서 아래쪽(목·어깨)만 비운 모양. 맨 위 구들은 선장 왕관 위로 비켜 감
	OrbSize = 0.24, -- 구(가운데 알맹이) 지름(스터드). 등급마다 Looks[].Core 배율을 곱함
	Radius = 1.6, -- 후광 반지름: 후광 가운데에서 구 가운데까지
	Lift = 0.1, -- 후광 가운데를 머리 가운데보다 올림
	Behind = 0.8, -- 후광을 머리 가운데보다 뒤로 (머리 뒷면 살짝 뒤. 얼굴 앞으로 나오지 않음)
	ArcFrom = -20, -- 첫 종류(엔진)의 자리(도). 앞에서 볼 때 왼쪽 = 0, 위 = 90. 0 보다 작으면 어깨 쪽으로 내려감.
	ArcTo = 200, -- 종류 순서대로 후광을 따라 ArcTo 까지 같은 간격 (양 끝이 어깨 살짝 위)
	HeadSize = 1.2, -- 기준 머리 높이(스터드)
	Interval = 0.5, -- 서버가 희귀도를 다시 보는 간격(초). 바뀐 구만 다시 만듦 (뽑기 등 어떤 길로 바뀌어도 따라감)
	GhostTransparency = 0.65, -- 관전자(유령) 구의 투명도 (몸과 같게). 관전자 구에는 빛 번짐·맥박·반짝이 없음
	-- 등급별 모습 (Nick 11-28: 희귀도가 높을수록 화려하게, 테두리 말고 빛나게). 순서 = 일반·희귀·영웅·전설. Studio 실제 화면으로 맞춤
	--  Core: 알맹이 크기 배율 · CoreWhite: 알맹이 색을 흰빛 쪽으로 (0~1, 가운데가 달아오른 느낌)
	--  Glow: 빛 번짐 지름 = 알맹이 지름 × Glow (없으면 빛 없음) · GlowTransparency: 겹친 원 한 장의 투명도 (작을수록 진함)
	--  Pulse: 빛이 숨쉬듯 커졌다 돌아오는 주기(초) · Glint: 반짝 별 지름 = 알맹이 지름 × Glint (천천히 돎)
	--  Sparkle: 알맹이 둘레에서 반짝이가 튀어 나옴. 빛·맥박·별·반짝이는 모두 각자 화면에서만
	Looks = {
		{ Core = 1.0, CoreWhite = 0 },
		{ Core = 1.0, CoreWhite = 0.1, Glow = 4, GlowTransparency = 0.88 },
		{ Core = 1.1, CoreWhite = 0.2, Glow = 5, GlowTransparency = 0.84, Pulse = 1.6 },
		{ Core = 1.2, CoreWhite = 0.35, Glow = 6.5, GlowTransparency = 0.8, Pulse = 0.9, Glint = 5, Sparkle = true },
	},
	GlowSteps = { 1, 0.8, 0.62, 0.46, 0.32 }, -- 빛 번짐: 겹쳐 그리는 둥근 판들의 지름(빛 지름 대비). 가운데로 갈수록 진해져 퍼지는 빛처럼 보임
	GlowBrightness = 2, -- 빛 번짐 밝기 (주변 조명과 상관없이)
	PulseScale = 0.18, -- 맥박 때 빛 지름이 이만큼(비율) 커졌다 돌아옴
	GlintSpin = 6, -- 전설 반짝 별이 한 바퀴 도는 시간(초)
	MaxGlows = 72, -- 한 화면에서 빛 번짐을 붙이는 구 수 한도 (카메라에서 가까운 것부터. 나머지는 작은 구만)
	GlowRange = 80, -- 빛 번짐을 붙이는 거리 한도(스터드)
	MaxSparkles = 24, -- 한 화면에서 반짝이를 뿌리는 전설 구 수 한도 (카메라에서 가까운 것부터)
	SparkleRange = 60, -- 반짝이를 뿌리는 거리 한도(스터드)
	SparkleRate = 5, -- 전설 구 하나의 반짝이 수(초당)
}

-- 부품 조립 (빌드 페이즈). 기획서 '부품 그리드': 종류마다 정사각형 그리드, 판마다 승무원 수만큼 칸이 무작위로 열림,
-- 각자 종류마다 1개씩 열린 칸에 직접 꽂음, 시간이 끝나면 못 꽂은 부품은 빈 칸에 자동 장착.
-- 조립 중에는 꽂은 부품만으로 종류별 합계와 예상 거리를 계산해 보여 줍니다 (꽂을수록 예상 거리가 오름).
Config.Build = {
	CellsPerCrew = 1.5, -- 그리드 칸 수 ≈ 승무원 × 1.5 (그 이상인 가장 작은 정사각형)
	MinSize = 3, -- 그리드 한 변의 최소 칸 수 (6명까지 3×3)
	BotPlaceFrom = 1.5, -- 임시: 봇이 부품을 꽂기 시작하는 시각 (조립 시작 후 초)
	BotPlaceTo = 15, -- 임시: 봇은 이 시각까지 부품 6개를 무작위 시각에 하나씩 꽂음
	BotHurryMargin = 1.5, -- 사람이 모두 꽂아 조립이 줄어들면, 봇은 끝나기 이만큼 전까지 남은 부품을 서둘러 꽂음
	RecalcInterval = 0.2, -- 부품이 꽂힐 때 종류별 합계와 예상 거리를 다시 계산하는 최소 간격(초)
	AnnounceRarity = 3, -- 사람이 이 레어도(3 = 영웅) 이상 부품을 처음 꽂으면 전원에게 알림 (기획서 '장착 연출')
}

-- 장비 묶음 (디버그 패널에서 바꿈). 기본 "각자 부품": 사람은 자기 부품 6개(레어도·레벨, PartProgress)를 꽂고 봇은 일반 Lv1.
-- 나머지 묶음은 시험용으로 사람·봇 모두 같은 장비. 옛 Lv k(1~10 표)는 Lv 1+1111(k−1) 과 파워가 거의 같음 (Lv5 → 4,445)
Config.Gear = {
	Default = "own",
	Presets = {
		{ Id = "own", Name = "각자 부품", Rarity = 1, Level = 1, Own = true }, -- Rarity·Level 은 봇 장비
		{ Id = "common1", Name = "일반 Lv1", Rarity = 1, Level = 1 },
		{ Id = "rare5", Name = "희귀 Lv4,445", Rarity = 2, Level = 4445 },
		{ Id = "epic5", Name = "영웅 Lv4,445", Rarity = 3, Level = 4445 },
		{ Id = "legend10", Name = "전설 Lv10,000", Rarity = 4, Level = 10000 },
	},
}

-- 부품 레벨·경험치 (Nick 11-27: 만렙 약 10000, 비행 중 경험치 바가 쭉쭉 차고 레벨업마다 폭죽. 만렙까지 약 2000판, 초반엔 잘
-- 오르다가 갈수록 힘들게). Nick 11-28 "부품 레벨이 너무 빨리 오름" → 경제 v9 (뽑기 스레드): 초반을 느리게, 돌파(★)를 넣음.
-- 사람마다 부품 6종(종류별 1개)이 각자 레어도·레벨·경험치·돌파를 가짐. 시작은 6종 모두 일반 Lv1 ★1, 서버가 켜져 있는 동안만 기억.
-- 다음 레벨까지 경험치 = 내림(ExpRarityFactor[레어도] × (지금 레벨 + ExpLevelOffset)² / ExpDivisor).
-- 일반 부품은 첫 판(약 80초)에 Lv37 안팎, 10판 Lv350, 50판 Lv1,500 (전에는 Lv600 · 1,800 · 3,450).
-- 만렙까지 2.5분 비행으로 일반 약 460판·전설 약 1,850판 (전에는 510판·2,060판). 레벨업은 첫 판 2초에 한 번쯤, 전설 만렙 근처는 한 판에 2~3번.
-- 돌파(★): 만렙 한도 = LevelsPerStar × ★ (★1 Lv2,000 … ★5 Lv10,000). 같은 레어도 부품을 또 뽑으면 ★+1 (Config.Gacha).
-- 한도에 닿으면 레벨은 멈추고 경험치는 쌓아 두었다가, 돌파하는 순간 쌓인 경험치만큼 레벨이 한꺼번에 오름.
-- 파워 = 레어도 기본값 × 레벨 배율 10^((레벨−1)/(만렙−1)): Lv1 ×1, Lv1,000 ×1.26, Lv5,000 ×3.16, Lv10,000 ×10 (Parts.power).
-- 비행 중 오른 레벨은 다음 판 조립부터 파워에 들어감 (판 도중에는 그대로).
Config.Progress = {
	MaxLevel = 10000,
	ExpRarityFactor = { 1, 2, 3, 4 }, -- 일반·희귀·영웅·전설
	ExpLevelOffset = 7000,
	ExpDivisor = 2200,
	MaxStars = 5, -- 돌파 단계 (★1~★5)
	LevelsPerStar = 2000, -- ★ 하나당 만렙 한도
	ExpPerSecond = 10000, -- 발사부터 비행이 끝날 때까지 1초마다 탄 사람(봇·관전자 제외)의 부품 하나가 얻는 경험치. 데모 2는 2배
	SendInterval = 0.25, -- 비행 중 경험치를 주고 그 사람 화면에 알리는 간격(초). 레벨업 폭죽도 이 간격으로 묶어서 터짐
	DebugLevels = 1000, -- 디버그 패널의 "내 부품 레벨 +" 버튼 한 번에 오르는 레벨 (열 번이면 만렙, 폭죽도 터짐). 한도에 닿으면 ★도 같이 올림
}

-- 보상 (임시)
Config.Rewards = {
	CoinsPerKm = 100, -- 코인 = 거리(km) × 이 값 (버림). 경제 v9 (Nick 11-28 "코인 얻는 양도 늘리고 소모량도 늘릴 것"): 10 → 100
	StartCoins = 10000, -- 서버에 들어올 때 받는 코인 (처음 값으로 뽑기 두 번)
	AfkCoinFactor = 0.5,
	AwardTickets = 1, -- 시상 1개당 티켓
	StartTickets = 3, -- 임시: 서버에 들어올 때 받는 티켓 (첫 판부터 부스터를 눌러 볼 수 있게)
	ExpectedRate = 0.85, -- 빌드 페이즈 예상 거리에 쓰는 미션 성공률
}

-- 부품 뽑기 (Nick 11-28 "부품 뽑기도 추가", "발사 전에 뽑을 수 있게"): 화면 오른쪽 위 버튼 줄(시점·디버그 아래)의 '부품 뽑기' 버튼.
-- 부품 종류(엔진 등 6종)를 고르고 1회 또는 10회. 탑승 대기·조립·정산 때만 되고 카운트다운·비행 중에는 막힘.
-- 뽑은 부품은 바로 내 부품이 되지만 판의 파워는 다음 조립부터 바뀜 (조립이 시작할 때의 부품으로 그 판을 날기 때문).
-- 결과마다 지금 그 종류 부품과 비교해서:
--   더 높은 레어도 → 새 부품으로 바꿔 낌 (Lv1·★1부터. 레어도 기본값이 10배라 파워는 그래도 오름)
--   같은 레어도 → 돌파 ★+1 (만렙 한도 +2,000, Config.Progress). 이미 ★5 면 경험치 DupeExp
--   더 낮은 레어도 → 경험치 DupeExp[뽑은 레어도]
-- 부품 이름·모양 180종(Catalog.luau, Nick 11-28 "300종은 너무 많은것 같다 180종 정도로")은 뽑을 때마다 도감에 모이고, 같은 레어도끼리는 도감에서
-- 모양을 바꿔 낄 수 있음 (능력치는 같음).
-- 값은 경제 v10 시뮬레이션 (4분에 한 판, 보통 실력, 아이템·보너스 코인 없음, 6종 중 약한 것부터 뽑음, 50명 서버):
-- 한 판에 약 2번 (1시간 30번), 6종 희귀 0.7시간, 첫 영웅 0.5시간, 6종 영웅 5시간, 첫 전설 약 44시간, 6종 전설 400시간 넘게.
-- (경제 v9 의 캡슐 3종은 첫 전설 10시간·6종 전설 29시간이었음 → Nick "전설 너무 빨리 나옴")
Config.Gacha = {
	-- 뽑기는 하나 (Nick 11-28 "일반 고급 최고급 넣지 말고 뽑기 일괄, 전설 너무 빨리 나옴")
	Odds = { 0.78, 0.18, 0.0395, 0.0005 }, -- 일반·희귀·영웅·전설 (전설 2,000번에 1번, Nick 11-28 카드에서 고름)
	-- 1회 값 = 내 최고 기록(km) × PricePerKm, BasePrice 보다 작으면 BasePrice. 앞 세 자리만 남기고 반올림.
	-- 코인은 km 만큼 받으므로 기록이 늘어도 늘 한 판에 2번쯤 뽑음 (값을 고정하면 후반엔 한 판에 수천 번)
	BasePrice = 5000,
	PricePerKm = 50,
	TenPrice = 10, -- 10회 뽑기 값 = 1회 값 × 이것
	TenCount = 11, -- 10회 뽑기로 받는 개수 (1개 덤)
	DupeExp = { 300000, 600000, 1200000, 2400000 }, -- 낮은 레어도·★5 중복을 경험치로 바꿀 때 (뽑은 레어도별). 일반은 비행 30초어치
	RequestGap = 0.3, -- 같은 사람의 뽑기 신호 사이 최소 간격(초). 더 빨리 오면 무시
	AnnounceRarity = 4, -- 이 레어도(4 = 전설) 이상을 뽑으면 서버 모두에게 알림 + 다른 사람에게 축하 버튼
	CheerSeconds = 6, -- 축하 버튼이 떠 있는 시간(초)
	CheerGrace = 1, -- 서버가 축하를 더 받아 주는 여유(초)
	CheerCoins = 50, -- 축하를 누른 사람이 받는 코인 (감사 버튼과 같은 값)
	ResultsDelay = 2.5, -- 정산 때는 비행 코인이 '보유 코인' 칸에 다 날아온 뒤에 뽑기 버튼을 보임 (초)
}

-- 비행 중 코인 연출 (CoinFx.luau). 거리만큼 쌓이는 이번 비행 코인이 화면 오른쪽 위 '보유 코인' 칸으로 날아 들어가고,
-- 부스터로 더 번 코인은 부스터 색으로 모았다가 화면 가운데에서 한꺼번에 터져 나와 들어갑니다.
-- 한 번에 들어오는 코인이 많을수록 코인 수·크기·퍼지는 폭·글자·반짝임·소리가 커집니다. 크기는 이번 판 예상 코인
-- (조립 때 계산한 예상 거리 × CoinsPerKm)에 대한 비율로 정해서, 장비가 좋아져도 같은 양이면 같은 느낌입니다.
Config.CoinFx = {
	DistanceInterval = 0.3, -- 거리 코인은 이만큼(초)마다 모아서 날림
	BoostGather = 1.2, -- 부스터 코인은 첫 코인부터 이만큼(초) 모았다가 한꺼번에 날림 (웜홀처럼 한 번에 생긴 코인은 한 무더기로)
	SmallRatio = 0.004, -- 한 번에 들어오는 코인이 예상 코인의 이 비율 이하면 가장 작은 효과 (코인 1개)
	HugeRatio = 0.25, -- 이 비율 이상이면 가장 화려한 효과
	MinExpected = 50, -- 예상 코인이 이보다 작거나 아직 모르면 이 값으로 봄
	MaxSprites = 80, -- 화면에 한꺼번에 날아다니는 코인 수 한도
	MaxPerBurst = 30, -- 한 무더기에 날리는 코인 수 한도 (가장 화려할 때)
	DistanceMaxSprites = 4, -- 거리 코인 한 번에 날리는 코인 수 한도 (작은 효과로 유지)
	-- 코인 소리: ROFLY_Coin (ElevenLabs 로 만든 0.31초 밝은 코인 차임, Nick 계정으로 Roblox 에 올림).
	-- ElevenLabs 약관 때문에 소리 파일은 저장소에 두지 않고 에셋 ID 만 씀
	SoundId = "rbxassetid://125291667623272",
	SoundVolume = 0.55, -- 가장 작은 효과일 때. 클수록 0.3 더 커짐 (Nick 11-28: 레벨업 소리보다 커야 함)
	SoundSpeedMin = 1.0, -- 작은 코인의 재생 속도 (1.0~1.1). 빠르게 틀수록 날카롭고 짧아짐
	SoundSpeedMax = 1.3, -- 큰 무더기의 뒤쪽 코인도 이만큼까지만 높게
	SoundAccentSpeed = 0.85, -- 큰 무더기가 처음 닿을 때 한 번 더 내는 낮고 굵은 소리
	SoundGap = 0.045, -- 코인 소리 사이의 최소 간격(초). 많이 들어올 때 소리가 뭉개지지 않게
}

-- 루트: 챕터와 스테이지 끝 지점(km). 이름은 데모 스테이지 5개만 확정.
Config.Route = {
	EscapeName = "폭발권 밖", -- 루트 끝(80만 km)에 닿아 탈출했을 때의 도착 지점 이름 (16번째)
	Chapters = {
		{ Name = "대기권", EndKm = 100 },
		{ Name = "지구 궤도", EndKm = 36000 },
		{ Name = "달", EndKm = 400000 },
		{ Name = "태양계", EndKm = 800000 },
	},
	Stages = {
		{ Name = "붕괴하는 고향 행성", EndKm = 3, Chapter = 1 },
		{ Name = "폭풍 구름층", EndKm = 10, Chapter = 1 },
		{ Name = "화산재 하늘", EndKm = 30, Chapter = 1 },
		{ Name = "오로라 하늘", EndKm = 100, Chapter = 1 },
		{ Name = "궤도 고철 지대", EndKm = 400, Chapter = 2 },
		{ Name = "지구 궤도 2", EndKm = 2000, Chapter = 2 },
		{ Name = "지구 궤도 3", EndKm = 10000, Chapter = 2 },
		{ Name = "지구 궤도 4", EndKm = 36000, Chapter = 2 },
		{ Name = "달 1", EndKm = 80000, Chapter = 3 },
		{ Name = "달 2", EndKm = 180000, Chapter = 3 },
		{ Name = "달 3", EndKm = 400000, Chapter = 3 },
		{ Name = "태양계 1", EndKm = 500000, Chapter = 4 },
		{ Name = "태양계 2", EndKm = 600000, Chapter = 4 },
		{ Name = "태양계 3", EndKm = 700000, Chapter = 4 },
		{ Name = "태양계 4", EndKm = 800000, Chapter = 4 },
	},
}

-- 대기권(첫 챕터, 100 km까지) 연출. 대기권 안에서는 마찰로 코와 외창이 달아오르고 화면이 흔들립니다.
-- 별빛 줄기는 대기권을 벗어난 뒤에만 나옵니다.
Config.Atmosphere = {
	HeatStartSpeed = 80, -- 이 속도(m/s)부터 달아오르기 시작
	HeatFullSpeed = 450, -- 이 속도(m/s)에서 가장 뜨거움 (보통 한 판의 최고 속도쯤)
	ThinAirKm = 70, -- 여기부터 대기권 끝까지 공기가 옅어져 열과 흔들림이 줄어듦
	ShakeDeg = 0.7, -- 가장 뜨거울 때 화면 흔들림 각도(도)
	ShakeStuds = 0.35, -- 가장 뜨거울 때 화면 흔들림 거리(스터드)
}

-- 회색 상자 월드 치수(스터드). 로켓은 원점에 서 있고 배경이 움직입니다.
-- 선실은 승무원이 걸어다니는 둥근 방이고 4면으로 나뉩니다 (Cabin.luau):
-- +Z·-Z 는 외창, +X 는 진행도 전광판(Board), -X 는 부품 장착판(PartsBoard)과 그 아래 내 부품 판(MyPartsBoard).
-- 전광판들은 둥근 벽 앞에 세운 평평한 벽에 붙음.
Config.World = {
	GroundSize = 2048,
	MountRadius = 46,
	MountHeight = 4,
	RocketBaseY = 12, -- 선체 바닥
	RocketTopY = 212, -- 선체 꼭대기(코 제외)
	HullRadius = 38,
	CabinRadius = 36, -- 선실 바닥 반지름 (100명이 서도 한 사람에 약 40 제곱스터드)
	CabinFloorY = 120,
	CabinCeilY = 160,
	WallSegments = 48,
	WindowHalfAngle = 40, -- 외창 하나(+Z, -Z 두 곳)가 차지하는 각도의 절반(도)
	WindowBottomY = 121, -- 외창 아래 끝 (바닥 위 1 스터드). 낮게 두어 선실 어디에서 보든 창 너머 행성이 보임 (Planet.placement)
	WindowTopY = 154,
	PanelWallX = 28, -- 전광판을 붙이는 평평한 벽: 선실 가운데에서 ±X 로 이 거리 (벽 너비 약 45)
	BoardWidth = 40, -- 진행도 전광판 (+X 벽)
	BoardHeight = 20,
	BoardY = 140, -- 전광판 가운데 높이 (바닥에서 20)
	PartsBoardWidth = 40, -- 부품 장착판 (-X 벽 위쪽)
	PartsBoardHeight = 20,
	PartsBoardY = 147,
	MyPartsBoardWidth = 40, -- 내 부품 판 (-X 벽, 부품 장착판 바로 아래). 화면은 사람마다 자기 부품을 그림
	MyPartsBoardHeight = 9,
	MyPartsBoardY = 130.5,
	SpotRadius = 26, -- 탑승 자리(승무원이 처음 서는 곳)를 퍼뜨리는 반지름
	SpotHeight = 3.5, -- 탑승 자리 바닥에서 캐릭터 중심까지 (조금 떠서 내려앉음)
	CabinMaxZoom = 30, -- 선실 안에서 카메라가 내 캐릭터에서 멀어질 수 있는 최대 거리
	SpawnDistance = 95, -- 로켓 중심에서 리스폰 지점까지
	OutsideCamera = { 241, 60, 380, 36 }, -- 바깥 시점 카메라 자리 (x, y, z)와 바라보는 로켓 축의 높이. 로켓과 그 아래 추진운이 함께 보이게 조금 멀리서
	StudsPerMeter = 3.57,
}

-- 발사탑 엘리베이터 (Lift.luau). 판을 기다리는 동안(참여 확인) 광장과 탑승 팔 사이를 오르내림.
-- 칸 모양과 오르는 높이(칸의 속성 Rise, 약 119 스터드)는 LaunchPad.luau 가 정함
Config.Lift = {
	RideSeconds = 3, -- 한 번 오르거나 내려가는 시간 (출발·도착은 부드럽게)
	ButtonDistance = 10, -- 버튼을 누를 수 있는 거리(스터드)
	RiderHeight = 10, -- 칸 바닥 위로 이 높이 안에 캐릭터 중심이 있으면 태움 (뛰는 중이어도)
}

-- 소리. 나중에 바꾸려면 Id 만 고치면 됨
-- ROFLY_ 로 표시한 소리(와 아래 엔진음, 코인 소리)는 ElevenLabs 로 만들어(tools/sfx) Nick 의 계정으로 Roblox 에 올린 소리입니다.
-- 게임을 가진 계정으로 올린 소리만 납니다. 다른 계정이 올린 비공개 소리는 "not authorized" 로 안 나므로
-- 게임 주인 계정이 바뀌면 소리를 그 계정으로 다시 올리고 Id 를 바꿉니다 (2026-11-28 에 그렇게 다시 올림).
-- 이 게임에서만 쓰고, 소리 파일은 저장소에 올리지 않습니다 (ElevenLabs 약관). 크기를 같은 기준으로 맞춰 두었으므로
-- 소리끼리의 크기 균형은 Volume 만으로 정합니다 (자주 나는 소리는 작게, 발사·충격파처럼 가끔 오는 큰 순간은 크게).
-- 나머지는 Roblox 가 예전 기본 소리 파일을 공개 에셋으로 올려 둔 것(크리에이터 스토어, 만든 이 @Roblox,
-- 설명이 \sounds\<파일 이름>)입니다. 기본 내장 소리 파일(rbxasset://sounds/...)은 지금 설치본에 11개만 남아 있어
-- (2026-11 맥 Studio 설치 폴더 content/sounds 에서 확인: action_falling.ogg, impact_explosion_03.mp3 등)
-- 예전 경로(Rocket shot.wav, victory.wav 등)로는 소리가 나지 않습니다.
Config.Sounds = {
	Countdown = { Id = "rbxassetid://113912958580265", Volume = 0.6 }, -- ROFLY_Countdown: 짧고 맑은 전자음 삑
	Launch = { Id = "rbxassetid://88737136990816", Volume = 0.9 }, -- ROFLY_Launch: 점화 폭발음이 굉음으로 올라감
	MissionSuccess = { Id = "rbxassetid://123490030245354", Volume = 0.5 }, -- ROFLY_MissionSuccess: 짧고 밝은 성공 차임
	Combo = { Id = "rbxassetid://86110461835347", Volume = 0.6 }, -- ROFLY_Combo: 올라가는 콤보 차임
	CrisisAlarm = { Id = "rbxassetid://12221990", Volume = 0.8 }, -- electronicpingshort.wav
	ItemUse = { Id = "rbxassetid://98161551530447", Volume = 0.8 }, -- ROFLY_ItemUse: 에너지가 차오르는 부스터 소리
	Press = { Id = "rbxassetid://12221976", Volume = 0.5 }, -- clickfast.wav
	Wrong = { Id = "rbxassetid://12222242", Volume = 0.25 }, -- uuhhh.wav
	Caught = { Id = "rbxassetid://98178750186121", Volume = 0.9 }, -- ROFLY_Caught: 충격파가 덮치는 큰 폭발음
	Thunder = { Id = "rbxassetid://12222030", Volume = 0.25 }, -- HalloweenThunder.wav
	Thanks = { Id = "rbxassetid://12222170", Volume = 0.5 }, -- switch.wav
	PartPlace = { Id = "rbxassetid://12221976", Volume = 0.8 }, -- clickfast.wav. 내 부품을 꽂음
	LaunchAlert = { Id = "rbxassetid://12221990", Volume = 1 }, -- electronicpingshort.wav. 선장 발사 임박 (세 번 연달아 울림)
	-- ROFLY_LevelUp: 짧게 올라가다 맑게 끝나는 0.7초 차임. 내 부품 레벨업 (MyParts 가 0.45초 간격으로 틂. 자주 나므로 코인 소리보다 작게, Nick 11-28)
	LevelUp = { Id = "rbxassetid://120908015105749", Volume = 0.2 },
}

-- 엔진음: 비행 내내 반복해서 깔리는 소리 세 겹. 계산은 EngineMix.luau, 소리 내기는 클라이언트 Sfx.luau.
-- 굉음은 비행 구간(최대 출력·구원 연료 > 순항 > 솔라 세일 > 관성)의 추력만큼 커지고, 웅웅 소리는 추력이 없어도
-- 조금은 늘 남아서 비행 중에는 엔진 소리가 끊기지 않습니다. 바람 소리는 대기권 안에서 빠를수록 커집니다.
-- 엔진 소리는 ElevenLabs 로 만든 7.6초 반복 소리(ROFLY_Engine, 선실 안에서 듣는 로켓 엔진)입니다. 노트북·폰 스피커에서도
-- 들리도록 저음의 배음을 중음에 더해 두었습니다(tools/sfx/process.py 의 smallSpeaker).
-- 크기(Volume)는 게임 안에서 들어 보지 않고 잡은 값입니다. 크거나 작으면 이 표의 Volume 만 고치면 됩니다.
Config.EngineSound = {
	-- 엔진 소리 하나를 굉음·웅웅 두 겹이 같이 씀 (용량을 줄이려고). 웅웅 소리는 Pitch 배로 낮게,
	-- 소리 길이의 Offset 비율만큼 어긋난 자리부터 틀어서 굉음과 다른 겹으로 들림
	Roar = { Id = "rbxassetid://72652689019739", Volume = 0.6 },
	Hum = { Id = "rbxassetid://72652689019739", Volume = 0.4, Pitch = 0.75, Offset = 0.5 },
	-- 기본 내장 낙하 바람 소리 (설치본에 있음)
	Wind = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.35 },
	-- 엔진 소리 에셋을 못 불러오면 대신 쓰는 기본 내장 소리. FallbackPitch 배로 낮춰 굉음처럼 들리게 함
	Fallback = "rbxasset://sounds/action_falling.ogg",
	FallbackPitch = 0.45,
	-- 비행 구간(FlightSim.phaseAt)별 추력 (0~1). 굉음 크기 비율이 됨
	Thrust = { rescue = 1, hot = 1, cruise = 0.6, sail = 0.25, coast = 0.1 },
	HumFloor = 0.4, -- 추력이 0이어도 남는 웅웅 소리 비율 (추력 1이면 1)
	TurboThrust = 0.35, -- 터보 엔진이 켜져 있는 동안 추력에 더함 (굉음이 더 커짐)
	TurboPitch = 0.1, -- 터보 엔진이 켜져 있는 동안 높이 +
	RoarPitchLow = 0.8, -- 추력 0일 때 굉음 높이 (추력 1이면 1)
	HumPitchLow = 0.75, -- 추력 0일 때 웅웅 소리 높이
	SpeedPitch = 0.12, -- 빠를수록 높이 + (10 m/s 에서 1만 m/s 까지 로그로 0~이 값)
	SpoolPitch = 0.6, -- 발사 순간의 높이. SpoolSeconds 동안 1까지 오름 (엔진이 힘을 받는 소리)
	SpoolSeconds = 1.5,
	LaunchSurge = 0.4, -- 발사 직후 크기 +40%, SurgeSeconds 동안 줄어듦
	SurgeSeconds = 4,
	PreIgniteSeconds = 3, -- 카운트다운 마지막 이 초 동안 웅웅 소리가 낮게 차오름 (0 이면 끔)
	PreIgniteLevel = 0.5,
	KickVolume = 0.3, -- 미션 성공·부스터를 쓴 순간 굉음 크기 +
	KickPitch = 0.08, -- 그때 높이 +
	KickSeconds = 1.5, -- 그 효과가 사라지는 시간(초)
	WindStartSpeed = 20, -- 바람 소리가 나기 시작하는 속도 (m/s)
	WindFullSpeed = 300, -- 바람 소리가 가장 큰 속도 (m/s)
	WindPitchLow = 0.8,
	WindPitchHigh = 1.3,
	Attack = 6, -- 커질 때 따라가는 빠르기 (초당)
	Release = 2.5, -- 작아질 때 따라가는 빠르기
	CaughtRelease = 10, -- 충격파에 잡혔을 때 엔진이 끊기는 빠르기
	PitchRate = 3, -- 높이가 따라가는 빠르기
	MaxLevel = 1.6, -- 크기 비율 상한
}

-- 디버그 패널을 쓸 수 있는 사람
Config.Debug = {
	AllowInStudio = true,
	AllowCreator = true,
	CoinGrant = 100000000, -- 디버그 패널의 "코인 +" 버튼 한 번에 주는 코인 (뽑기를 많이 눌러 보기)
}

return Config
