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
	ThanksCoins = 5, -- 임시: 감사를 누른 사람이 받는 코인
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
	-- 레벨 배율은 Parts.levelMultiplier (Config.Progress 아래 설명)
	SlotBonus = 0.01, -- 꽂은 부품 1개당 그 종류 합계 +1%
	RankExp = 1, -- 종류별 합계에서 센 순서 k번째 부품은 1 / k^RankExp 만 더함 (인원 효과를 완만하게)
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
-- 오르다가 갈수록 힘들게). 수치는 밸런스 스레드(11-27). 사람마다 부품 6종(종류별 1개)이 각자 레어도·레벨·경험치를 가짐.
-- 시작은 6종 모두 일반 Lv1, 서버가 켜져 있는 동안만 기억.
-- 다음 레벨까지 경험치 = 내림(ExpRarityFactor[레어도] × (지금 레벨 + ExpLevelOffset)² / ExpDivisor).
-- 새 일반 부품은 첫 판에 Lv700 안팎, 만렙까지 일반 약 500판·전설 약 2,000판.
-- 파워 = 레어도 기본값 × 레벨 배율 10^((레벨−1)/(만렙−1)): Lv1 ×1, Lv1,000 ×1.26, Lv5,000 ×3.16, Lv10,000 ×10 (Parts.power).
-- 비행 중 오른 레벨은 다음 판 조립부터 파워에 들어감 (판 도중에는 그대로).
Config.Progress = {
	MaxLevel = 10000,
	ExpRarityFactor = { 1, 2, 3, 4 }, -- 일반·희귀·영웅·전설
	ExpLevelOffset = 500,
	ExpDivisor = 500,
	ExpPerSecond = 10000, -- 발사부터 비행이 끝날 때까지 1초마다 탄 사람(봇·관전자 제외)의 부품 하나가 얻는 경험치. 데모 2는 2배
	SendInterval = 0.25, -- 비행 중 경험치를 주고 그 사람 화면에 알리는 간격(초). 레벨업 폭죽도 이 간격으로 묶어서 터짐
	DebugLevels = 1000, -- 디버그 패널의 "내 부품 레벨 +" 버튼 한 번에 오르는 레벨 (열 번이면 만렙, 폭죽도 터짐)
}

-- 보상 (임시)
Config.Rewards = {
	CoinsPerKm = 10, -- 코인 = 거리(km) × 이 값 (버림)
	AfkCoinFactor = 0.5,
	AwardTickets = 1, -- 시상 1개당 티켓
	StartTickets = 3, -- 임시: 서버에 들어올 때 받는 티켓 (첫 판부터 부스터를 눌러 볼 수 있게)
	ExpectedRate = 0.85, -- 빌드 페이즈 예상 거리에 쓰는 미션 성공률
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
	SoundId = "rbxassetid://93440520253528",
	SoundVolume = 0.3, -- 가장 작은 효과일 때. 클수록 0.3 더 커짐 (Studio 에서 들어 보고 맞추기)
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

-- 소리 (임시: Roblox 기본 내장 소리. 나중에 크리에이터 스토어 소리로 교체)
Config.Sounds = {
	Countdown = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 },
	Launch = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.9 },
	MissionSuccess = { Id = "rbxasset://sounds/victory.wav", Volume = 0.35 },
	Combo = { Id = "rbxasset://sounds/bass.wav", Volume = 0.6 },
	CrisisAlarm = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8 },
	ItemUse = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.9 },
	Press = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5 },
	Wrong = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.25 },
	Caught = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.9 },
	Thunder = { Id = "rbxasset://sounds/HalloweenThunder.wav", Volume = 0.25 },
	Thanks = { Id = "rbxasset://sounds/switch.wav", Volume = 0.5 },
	PartPlace = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.8 }, -- 내 부품을 꽂음
	LaunchAlert = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 1 }, -- 선장 발사 임박 (세 번 연달아 울림)
}

-- 디버그 패널을 쓸 수 있는 사람
Config.Debug = {
	AllowInStudio = true,
	AllowCreator = true,
	CoinGrant = 1000, -- 디버그 패널의 "코인 +" 버튼 한 번에 주는 코인
}

return Config
