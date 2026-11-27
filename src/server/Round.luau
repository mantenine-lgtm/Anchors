-- 판 진행: 참여 확인 → 빌드 → 카운트다운 → 비행 → 정산 을 계속 반복합니다.
-- 거리·속도·충격파는 숫자로만 계산하고(FlightSim), 결과를 RoundState 속성으로 클라이언트에 알립니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local FlightSim = require(Shared:WaitForChild("FlightSim"))
local Missions = require(Shared:WaitForChild("Missions"))
local Net = require(Shared:WaitForChild("Net"))
local Parts = require(Shared:WaitForChild("Parts"))
local Planets = require(Shared:WaitForChild("Planets"))
local Route = require(Shared:WaitForChild("Route"))
local Scoring = require(Shared:WaitForChild("Scoring"))

local Assembly = require(script.Parent.Assembly)
local Bots = require(script.Parent.Bots)
local Metrics = require(script.Parent.Metrics)
local Seating = require(script.Parent.Seating)
local World = require(script.Parent.World)

local Round = {}

-- 승무원 한 명 (사람 또는 봇)
type Member = {
	id: string,
	name: string,
	userId: number,
	player: Player?,
	isBot: boolean,
	botIndex: number,
	seat: number,
	isCaptain: boolean,
	loadout: { [string]: number },
	power: number,
	successes: number,
	attempts: number,
	streak: number,
	bestStreak: number,
	noInput: number, -- 연속 무입력 미션 수
	afk: boolean, -- 자리 비움으로 판정됨 (코인 절반)
	left: boolean, -- 판 도중에 나감
	lastResult: string,
}

local rng = Random.new()
local planetRng = Random.new() -- 행성 고르기 전용 (판 진행에 쓰는 rng 의 순서를 바꾸지 않게)
local state: Folder
local current: any = nil -- 진행 중인 판 (없으면 nil)
local roundNumber = 0
local skipRequested = false
local bestKm = 0
local lastKingUserId = 0
local lastCaptainUserId = 0
local lateGhosts = 0

-- 디버그 패널에서 바꾸는 값
local options = {
	botFillTo = Config.Bots.FillTo,
	botSkill = Config.Bots.Skill,
	gear = Config.Gear.Default,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function pick(n: number): number
	return rng:NextInteger(1, n)
end

local function getNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return 0
end

local function announce(text: string)
	Net.event("Announce"):FireAllClients(text)
end

local function setPhase(name: string, duration: number)
	state:SetAttribute("PhaseEndsAt", if duration > 0 then now() + duration else 0)
	state:SetAttribute("Phase", name)
end

-- 발사 행성을 바꿈: 종류(Planet)를 먼저, 배치 씨앗(PlanetSeed)을 나중에 씀.
-- 클라이언트는 씨앗이 바뀌면 그때의 종류로 행성을 다시 만듭니다(씨앗이 같으면 모두 같은 행성).
local function setPlanet(planet: Planets.Planet)
	local previous = getNumber(state, "PlanetSeed")
	local seed = planetRng:NextInteger(1, 999999)
	if seed == previous then
		seed = seed % 999999 + 1
	end
	state:SetAttribute("Planet", planet.Id)
	state:SetAttribute("PlanetSeed", seed)
end

local function currentPlanetId(): string
	local id = state:GetAttribute("Planet")
	return if typeof(id) == "string" then id else ""
end

-- 다음 행성 슬롯: 정산을 시작할 때 다음 판 행성을 미리 뽑고, 슬롯이 돌기 시작하는 시각·멈추는 시각을 알림.
-- 화면(PlanetSlot.luau)은 SlotFrom(뺀 행성 = 지금 행성)으로 확률표를 만들고, SlotSeed 로 칸 순서를 섞어
-- 모든 사람이 같은 슬롯을 보다가 SlotStopAt 에 NextPlanet 에서 멈춥니다. 바뀌는 것은 판이 끝날 때(cleanup)입니다.
-- 쓰는 순서: 행성·씨앗을 먼저, 시작 시각(SlotStartAt)을 맨 나중에 (화면은 시작 시각이 오면 나머지를 읽음)
local function rollNextPlanet(resultsSeconds: number)
	local from = currentPlanetId()
	local planet = Planets.pick(from, planetRng)
	local spin = Config.PlanetSlot.Spin
	local startAfter = math.clamp(Config.PlanetSlot.StartAfter, 0, math.max(0, resultsSeconds - spin - 1))
	local startAt = now() + startAfter
	state:SetAttribute("NextPlanet", planet.Id)
	state:SetAttribute("SlotFrom", from)
	state:SetAttribute("SlotSeed", planetRng:NextInteger(1, 999999))
	state:SetAttribute("SlotStopAt", startAt + spin)
	state:SetAttribute("SlotStartAt", startAt)
end

local function clearSlot()
	state:SetAttribute("SlotStartAt", 0)
	state:SetAttribute("SlotStopAt", 0)
	state:SetAttribute("NextPlanet", "")
	state:SetAttribute("SlotFrom", "")
	state:SetAttribute("SlotSeed", 0)
end

local function consumeSkip(): boolean
	if skipRequested then
		skipRequested = false
		return true
	end
	return false
end

-- seconds 동안 기다림. 디버그 "건너뛰기"가 오면 일찍 끝남.
local function waitPhase(seconds: number)
	local endsAt = now() + seconds
	while now() < endsAt do
		if consumeSkip() then
			state:SetAttribute("PhaseEndsAt", now())
			return
		end
		task.wait(0.1)
	end
end

local function resetFlightState()
	state:SetAttribute("T", 0)
	state:SetAttribute("Km", 0)
	state:SetAttribute("Speed", 0)
	state:SetAttribute("WaveKm", 0)
	state:SetAttribute("WaveSpeed", 0)
	state:SetAttribute("Boost", 0)
	state:SetAttribute("Combo", 0)
	state:SetAttribute("LastRate", -1)
	state:SetAttribute("MissionCount", 0)
	state:SetAttribute("Eta", Config.Crisis.EtaLimit)
	state:SetAttribute("Crisis", false)
	state:SetAttribute("Stage", 1)
	state:SetAttribute("HotTime", 0)
	state:SetAttribute("FuelTime", 0)
	state:SetAttribute("SailTime", 0)
	state:SetAttribute("RescueUntil", -1)
	state:SetAttribute("ItemUsed", false) -- 이번 비행에 부스터를 하나라도 썼는지
	for _, info in ipairs(Boosters.List) do
		state:SetAttribute(Boosters.usedAttribute(info.Id), false)
		state:SetAttribute(Boosters.byAttribute(info.Id), "")
		state:SetAttribute(Boosters.untilAttribute(info.Id), -1)
	end
	state:SetAttribute("Escaped", false)
end

local function showOptions()
	state:SetAttribute("OptBotFill", options.botFillTo)
	state:SetAttribute("OptBotSkill", options.botSkill)
	state:SetAttribute("OptGear", options.gear)
end

-- 조립 화면에 쓸 값: 부품 종류별 합계와 이번 판 장비 이름.
-- 긴 글자 하나로 묶지 않고 짧은 속성 여러 개로 보냅니다 (글자 속성은 길이 제한이 있을 수 있음).
local function showBuild(totals: { [string]: number }?, gearName: string)
	for _, info in ipairs(Config.Parts.Types) do
		state:SetAttribute("Total_" .. info.Id, if totals then totals[info.Id] or 0 else 0)
	end
	state:SetAttribute("GearName", gearName)
end

-- ------------------------------------------------------------ 참여 확인
local function runJoin(): { Player }
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			player:SetAttribute("Joined", false)
		end
		state:SetAttribute("JoinedCount", 0)
		state:SetAttribute("PlayerCount", #Players:GetPlayers())
		local endsAt = now() + Config.Phase.Join
		setPhase("Join", Config.Phase.Join)
		local shortened = false
		local skipped = false
		while now() < endsAt do
			if consumeSkip() then
				skipped = true
				break
			end
			local players = Players:GetPlayers()
			local joined = 0
			for _, player in ipairs(players) do
				if player:GetAttribute("Joined") == true then
					joined += 1
				end
			end
			state:SetAttribute("JoinedCount", joined)
			state:SetAttribute("PlayerCount", #players)
			if not shortened and #players > 0 and joined == #players and endsAt - now() > Config.Phase.JoinAllReady then
				-- 모두 탔으면 오래 기다리지 않음
				shortened = true
				endsAt = now() + Config.Phase.JoinAllReady
				state:SetAttribute("PhaseEndsAt", endsAt)
			end
			task.wait(0.1)
		end
		local list: { Player } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if skipped or player:GetAttribute("Joined") == true then
				table.insert(list, player)
			end
		end
		if #list > 0 then
			return list
		end
		if #Players:GetPlayers() > 0 then
			announce("아무도 타지 않아 다시 기다립니다")
		end
	end
end

-- ------------------------------------------------------------ 빌드
local function newMember(id: string, name: string, player: Player?, botIndex: number): Member
	local loadout = Parts.loadout(options.gear)
	return {
		id = id,
		name = name,
		userId = if player then player.UserId else 0,
		player = player,
		isBot = player == nil,
		botIndex = botIndex,
		seat = 0,
		isCaptain = false,
		loadout = loadout,
		power = Parts.loadoutPower(loadout),
		successes = 0,
		attempts = 0,
		streak = 0,
		bestStreak = 0,
		noInput = 0,
		afk = false,
		left = false,
		lastResult = "none",
	}
end

-- 선장: 지난 판 미션왕. 2판 연속은 안 되고, 기록이 없으면 무작위. 봇은 선장이 되지 않음.
local function pickCaptain(crew: { Member }): Member?
	local humans: { Member } = {}
	for _, member in ipairs(crew) do
		if not member.isBot then
			table.insert(humans, member)
		end
	end
	if #humans == 0 then
		return nil
	end
	local candidates: { Member } = {}
	for _, member in ipairs(humans) do
		if member.userId ~= lastCaptainUserId then
			table.insert(candidates, member)
		end
	end
	if #candidates == 0 then
		candidates = humans -- 혼자면 계속 선장
	end
	for _, member in ipairs(candidates) do
		if member.userId == lastKingUserId then
			return member
		end
	end
	return candidates[pick(#candidates)]
end

-- 조립 중 수치: 꽂힌 부품만으로 종류별 합계와 예상 거리를 계산해 알림 (기획서 '장착 연출': 꽂으면 예상 거리가 오름).
-- 꽂힌 부품이 바뀌었을 때만, RecalcInterval 보다 자주는 하지 않음 (force 면 바로).
local function refreshAssembly(round: any, force: boolean)
	local session = round.assembly
	if not force and (not session.dirty or now() - round.lastRecalc < Config.Build.RecalcInterval) then
		return
	end
	session.dirty = false
	round.lastRecalc = now()
	local totals = Parts.totals(Assembly.loadouts(session))
	round.totals = totals
	round.expectedKm = FlightSim.predict(totals, 0, Config.Rewards.ExpectedRate)
	state:SetAttribute("ExpectedKm", round.expectedKm)
	showBuild(totals :: any, round.gearName)
end

-- 조립 시간: 사람은 조립 화면에서(PlacePart), 봇은 시간을 두고 하나씩 꽂음. 탄 사람이 모두 다 꽂으면 BuildAllPlaced 초만
-- 더 기다리고(그동안 남은 봇 부품도 서둘러 꽂음), 시간이 끝나면 못 꽂은 부품을 빈 칸에 자동으로 꽂습니다.
local function runAssembly(round: any)
	local session = round.assembly
	local endsAt = now() + Config.Phase.Build
	local hurried = false
	while now() < endsAt do
		if consumeSkip() then
			state:SetAttribute("PhaseEndsAt", now())
			break
		end
		Assembly.runBots(session, now())
		if not hurried and Assembly.allHumansDone(session) then
			hurried = true
			if endsAt - now() > Config.Phase.BuildAllPlaced then
				endsAt = now() + Config.Phase.BuildAllPlaced
				state:SetAttribute("PhaseEndsAt", endsAt)
			end
			Assembly.hurryBots(session, now(), endsAt - Config.Build.BotHurryMargin)
		end
		refreshAssembly(round, false)
		task.wait(0.1)
	end
	for member, count in pairs(Assembly.finish(session)) do
		local player = member.player
		if player and player.Parent == Players then
			Net.event("Announce"):FireClient(player, string.format("못 꽂은 부품 %d개를 빈 칸에 자동으로 꽂았습니다", count))
		end
	end
	refreshAssembly(round, true)
end

local function runBuild(joined: { Player }): any
	local crew: { Member } = {}
	local byPlayer: { [Player]: Member } = {}
	for _, player in ipairs(joined) do
		if player.Parent == Players then
			local member = newMember("p" .. tostring(player.UserId), player.DisplayName, player, 0)
			table.insert(crew, member)
			byPlayer[player] = member
		end
	end
	if #crew == 0 then
		return nil
	end
	roundNumber += 1
	local botCount = math.max(0, options.botFillTo - #crew)
	for i = 1, botCount do
		table.insert(crew, newMember("b" .. tostring(i), Bots.name(i), nil, i))
	end

	-- 좌석: 선장은 맨 윗줄 가운데, 나머지는 윗줄부터 채우고 줄 안에서는 가운데부터 (사람 먼저, 그다음 봇)
	local captain = pickCaptain(crew)
	local order = World.buildSeats(#crew)
	local nextSeat = 1
	if captain then
		captain.isCaptain = true
		captain.seat = order[1]
		nextSeat = 2
	end
	for _, member in ipairs(crew) do
		if member ~= captain then
			member.seat = order[nextSeat]
			nextSeat += 1
		end
	end

	Bots.clear()
	for _, member in ipairs(crew) do
		local player = member.player
		if player then
			Seating.seat(player, member.seat, member.isCaptain)
		else
			Bots.place(member.botIndex, member.seat)
		end
	end
	-- 타지 않은 사람은 유령으로 선실에서 관전
	lateGhosts = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not byPlayer[player] then
			lateGhosts += 1
			Seating.ghost(player, lateGhosts)
		end
	end

	-- 부품 조립: 종류마다 그리드를 열고, 꽂힌 부품만으로 합계와 예상 거리를 셈 (처음에는 아무것도 안 꽂힘)
	local preset = Parts.preset(options.gear)
	local assembly = Assembly.begin(state, roundNumber, crew, preset.Rarity, preset.Level, rng, now())

	state:SetAttribute("Round", roundNumber)
	state:SetAttribute("CrewCount", #crew)
	state:SetAttribute("CaptainUserId", if captain then captain.userId else 0)
	state:SetAttribute("CaptainName", if captain then captain.name else "")
	state:SetAttribute("CaptainSeat", if captain then captain.seat else 0)
	state:SetAttribute("BestKm", bestKm)
	resetFlightState()

	local round = {
		number = roundNumber,
		crew = crew,
		byPlayer = byPlayer,
		captain = captain,
		totals = nil, -- 조립이 끝나면 꽂힌 부품 전체의 종류별 합계 (refreshAssembly)
		expectedKm = 0,
		assembly = assembly,
		gearName = preset.Name,
		lastRecalc = 0,
		launchPress = nil,
		launchQuality = "auto",
		captainBonus = 0,
		sim = nil,
		mission = nil,
		items = {}, -- 이번 비행에 쓴 부스터 (쓴 순서)
		used = {}, -- 부스터 Id -> 쓴 기록 (종류마다 한 번)
		lastItem = nil, -- 감사 버튼이 가리키는 마지막 부스터
		goldenFromKm = nil, -- 황금 항로를 쓴 지점 (km)
		missionCount = 0,
		rateSum = 0,
		humanAttempts = 0,
		humanSuccesses = 0,
		ticketsUsed = 0,
		ended = false,
		fastForward = false, -- 디버그: 위기 구간 직전으로 건너뛰기
	}
	refreshAssembly(round, true)
	current = round
	setPhase("Build", Config.Phase.Build)
	runAssembly(round)
	return round
end

-- ------------------------------------------------------------ 카운트다운
local function runCountdown(round: any)
	local launchAt = now() + Config.Phase.Countdown
	state:SetAttribute("LaunchAt", launchAt)
	setPhase("Countdown", Config.Phase.Countdown)
	while true do
		if round.launchPress ~= nil then
			break
		end
		if now() >= launchAt + Config.Captain.AutoDelay then
			break
		end
		if consumeSkip() then
			break
		end
		RunService.Heartbeat:Wait()
	end
	local quality = "auto"
	local bonus = 0
	local press = round.launchPress
	if press ~= nil then
		local diff = math.abs(press - launchAt)
		if diff <= Config.Captain.PerfectWindow then
			quality = "perfect"
			bonus = Config.Captain.PerfectBonus
		elseif diff <= Config.Captain.GoodWindow then
			quality = "good"
			bonus = Config.Captain.GoodBonus
		elseif press < launchAt then
			quality = "early"
		else
			quality = "late"
		end
	end
	round.launchQuality = quality
	round.captainBonus = bonus
end

-- ------------------------------------------------------------ 비행
local function syncFlight(round: any)
	local sim = round.sim
	state:SetAttribute("T", sim.t)
	state:SetAttribute("Km", sim.x)
	state:SetAttribute("Speed", FlightSim.speed(sim))
	state:SetAttribute("WaveKm", sim.s)
	state:SetAttribute("WaveSpeed", sim.w)
	state:SetAttribute("Boost", sim.boost)
	state:SetAttribute("Stage", Route.stageIndex(sim.x))
end

local function updateCrisis(round: any)
	local sim = round.sim
	local eta = FlightSim.eta(sim, Config.Crisis.EtaLimit)
	state:SetAttribute("Eta", eta)
	local crisis = state:GetAttribute("Crisis") == true
	if not crisis and eta <= Config.Crisis.EnterEta and sim.t >= Config.Crisis.MinFlightTime then
		state:SetAttribute("Crisis", true)
	elseif crisis and eta >= Config.Crisis.ExitEta then
		state:SetAttribute("Crisis", false)
	end
end

-- 미션을 띄움. secondsLeft = 판정까지 남은 시간
local function startMission(round: any, index: number, secondsLeft: number)
	local chapter = Route.chapterIndex(round.sim.x)
	local params = Missions.params(chapter)
	local mission = {
		id = index,
		sequence = Missions.generate(params.Inputs, pick),
		limit = params.Limit,
		chapter = chapter,
		done = {}, -- 승무원 id -> 성공 여부
		touched = {}, -- 승무원 id -> 한 번이라도 눌렀는지
	}
	local botRate = Bots.rate(options.botSkill, chapter)
	for _, member in ipairs(round.crew) do
		if member.isBot then
			mission.done[member.id] = rng:NextNumber() < botRate
		end
	end
	round.mission = mission
	Net.event("MissionStart"):FireAllClients({
		id = index,
		sequence = mission.sequence,
		limit = params.Limit,
		closeAt = now() + secondsLeft - Config.Mission.InputGrace,
	})
end

-- 미션 판정. 팀 성공률(0~1)을 돌려줌.
local function resolveMission(round: any, mission: any): number
	local participants = 0
	local successes = 0
	for _, member: Member in ipairs(round.crew) do
		if member.left then
			member.lastResult = "none"
			continue
		end
		local ok = mission.done[member.id] == true
		if not member.isBot then
			if ok or mission.touched[member.id] then
				member.noInput = 0
			else
				member.noInput += 1
			end
			if member.noInput >= Config.Mission.AfkMissions then
				member.afk = true
			end
			if member.noInput >= Config.Mission.AfkMissions then
				-- 자리 비움: 판정에서 빠짐
				member.lastResult = "excluded"
				member.streak = 0
				continue
			end
		end
		participants += 1
		member.attempts += 1
		if ok then
			successes += 1
			member.successes += 1
			member.streak += 1
			member.bestStreak = math.max(member.bestStreak, member.streak)
			member.lastResult = "success"
		else
			member.streak = 0
			member.lastResult = "fail"
		end
		if not member.isBot then
			round.humanAttempts += 1
			if ok then
				round.humanSuccesses += 1
			end
		end
	end
	local rate = if participants > 0 then successes / participants else 0
	round.missionCount += 1
	round.rateSum += rate
	return rate
end

-- 결과는 팀 전체 수치만 알리고, 각자에게는 자기 결과만 따로 보냄
local function broadcastMissionResult(round: any, mission: any, rate: number)
	local sim = round.sim
	state:SetAttribute("Combo", sim.combo)
	state:SetAttribute("LastRate", rate)
	state:SetAttribute("MissionCount", round.missionCount)
	for _, player in ipairs(Players:GetPlayers()) do
		local member = round.byPlayer[player]
		Net.event("MissionResult"):FireClient(player, {
			id = mission.id,
			rate = rate,
			combo = sim.combo,
			perfect = rate >= 1 - 1e-9,
			own = if member then member.lastResult else "none",
		})
	end
end

-- 부스터마다 '그 부스터 하나만 안 쓴' 비행을 같이 진행 (정산 때 부스터로 늘린 거리를 알기 위해)
local function stepShadows(round: any, rate: number?)
	for _, item in ipairs(round.items) do
		local shadow = item.shadow
		if shadow and not shadow.ended then
			FlightSim.step(shadow, rate)
		end
	end
end

local function runFlight(round: any)
	local sim = FlightSim.new(round.totals, round.captainBonus)
	round.sim = sim
	state:SetAttribute("HotTime", sim.stats.hot)
	state:SetAttribute("FuelTime", sim.stats.fuel)
	state:SetAttribute("SailTime", sim.stats.sail)
	syncFlight(round)
	setPhase("Flight", 0)
	Net.event("Launched"):FireAllClients({
		quality = round.launchQuality,
		bonus = round.captainBonus,
		captainName = if round.captain then round.captain.name else "",
	})

	local dt = Config.Flight.Dt
	local missionIndex = 1
	local resolveAt = Missions.resolveTime(1)
	local accumulator = 0
	local lastSync = 0
	local lastEtaCheck = 0

	while not sim.ended do
		accumulator = math.min(accumulator + RunService.Heartbeat:Wait(), 0.25)
		if round.fastForward then
			-- 디버그: 위기 구간 직전까지 빨리 감기. 그 사이 미션은 예상 성공률로 자동 처리합니다.
			round.fastForward = false
			round.mission = nil
			local steps = 0
			while not sim.ended and steps < 12000 do
				if steps % 5 == 0
					and sim.t >= Config.Crisis.MinFlightTime
					and FlightSim.eta(sim, Config.Crisis.EtaLimit) <= Config.Crisis.EnterEta - 0.5
				then
					break
				end
				local autoRate: number? = nil
				if sim.t >= resolveAt then
					autoRate = Config.Rewards.ExpectedRate
					missionIndex += 1
					resolveAt = Missions.resolveTime(missionIndex)
				end
				FlightSim.step(sim, autoRate)
				stepShadows(round, autoRate)
				steps += 1
			end
			-- 다음 미션은 제한 시간을 온전히 주고 시작
			local nextParams = Missions.params(Route.chapterIndex(sim.x))
			resolveAt = math.max(resolveAt, sim.t + nextParams.Limit + Config.Mission.InputGrace)
			accumulator = 0
			lastSync = -1
			lastEtaCheck = -1
			state:SetAttribute("Combo", sim.combo)
		end
		while accumulator >= dt and not sim.ended do
			accumulator -= dt
			-- 미션은 판정 시각보다 (제한 시간 + 여유)만큼 먼저 띄움
			if round.mission == nil then
				local params = Missions.params(Route.chapterIndex(sim.x))
				if sim.t >= resolveAt - params.Limit - Config.Mission.InputGrace then
					startMission(round, missionIndex, resolveAt - sim.t)
				end
			end
			local rate: number? = nil
			local resolved: any = nil
			if sim.t >= resolveAt and round.mission ~= nil then
				resolved = round.mission
				rate = resolveMission(round, resolved)
				round.mission = nil
				missionIndex += 1
				resolveAt = Missions.resolveTime(missionIndex)
			end
			FlightSim.step(sim, rate)
			stepShadows(round, rate)
			if resolved ~= nil and rate ~= nil then
				broadcastMissionResult(round, resolved, rate)
			end
		end
		if sim.t - lastEtaCheck >= Config.Crisis.CheckInterval then
			lastEtaCheck = sim.t
			updateCrisis(round)
		end
		if sim.t - lastSync >= 0.1 then
			lastSync = sim.t
			syncFlight(round)
		end
		if consumeSkip() or sim.t >= Config.Phase.FlightMax then
			sim.ended = true
		end
	end

	round.ended = true
	round.mission = nil
	syncFlight(round)
	state:SetAttribute("Crisis", false)
	state:SetAttribute("Escaped", sim.escaped)
	Net.event("FlightEnd"):FireAllClients({
		escaped = sim.escaped,
		km = sim.x,
		seconds = sim.t,
	})
end

-- 부스터 효과가 끝나는 비행 시각 (시간이 정해진 것만, 아니면 -1)
local function boosterUntil(sim: any, boosterId: string): number
	if boosterId == "RescueFuel" then
		return sim.rescueUntil
	elseif boosterId == "Turbo" then
		return sim.turboUntil
	elseif boosterId == "Resonance" then
		return sim.resonanceUntil
	end
	return -1
end

-- 부스터 사용. 종류마다 한 비행에 로켓 전체로 한 번 (먼저 누른 사람). 구원 연료는 위기 구간에서만.
-- 쓰면 true. 못 쓰면 false 와 까닭 (사람에게 알려 줄 글, 알릴 것이 없으면 nil).
local function useBooster(round: any, member: Member, boosterId: string): (boolean, string?)
	local info = Boosters.get(boosterId)
	local sim = round.sim
	if info == nil or sim == nil or sim.ended or round.ended then
		return false, nil
	end
	if state:GetAttribute("Phase") ~= "Flight" then
		return false, nil
	end
	local usedBefore = round.used[boosterId]
	if usedBefore ~= nil then
		return false, string.format("%s: %s 님이 이미 썼습니다", info.Name, usedBefore.member.name)
	end
	local crisis = state:GetAttribute("Crisis") == true
	if boosterId == "RescueFuel" and not crisis then
		return false, "구원 연료는 위기 때만 쓸 수 있습니다"
	end
	local player = member.player
	if player then
		local tickets = getNumber(player, "Tickets")
		if tickets < info.Cost then
			return false, "티켓이 없습니다. 티켓은 시상으로 받습니다"
		end
		player:SetAttribute("Tickets", tickets - info.Cost)
		round.ticketsUsed += info.Cost
	end

	-- 이 부스터 하나만 안 썼을 때의 비행을 따로 이어 감 (황금 항로는 거리를 바꾸지 않아 필요 없음).
	-- 먼저 쓴 부스터들의 그림자에는 이 부스터를 넣어서, 그림자마다 '그 부스터 하나만 뺀' 비행이 되게 함.
	local shadow = if boosterId == "Golden" then nil else FlightSim.clone(sim)
	for _, other in ipairs(round.items) do
		local otherShadow = other.shadow
		if otherShadow and not otherShadow.ended then
			FlightSim.applyBooster(otherShadow, boosterId)
		end
	end
	FlightSim.applyBooster(sim, boosterId)
	if boosterId == "Golden" then
		round.goldenFromKm = sim.x
	end
	local item = {
		id = boosterId,
		name = info.Name,
		member = member,
		at = sim.t,
		inCrisis = crisis,
		shadow = shadow,
		km = 0, -- 정산 때 계산: 이 부스터로 늘린 거리
		thanks = {}, -- UserId -> 눌렀는지
		thanksCount = 0, -- 하트 수 (봇 포함)
		humanThanks = 0,
		thanksUntil = now() + Config.Rescue.ThanksWindow + Config.Rescue.ThanksGrace,
	}
	table.insert(round.items, item)
	round.used[boosterId] = item
	round.lastItem = item
	state:SetAttribute("ItemUsed", true)
	state:SetAttribute(Boosters.usedAttribute(boosterId), true)
	state:SetAttribute(Boosters.byAttribute(boosterId), member.name)
	state:SetAttribute(Boosters.untilAttribute(boosterId), boosterUntil(sim, boosterId))
	state:SetAttribute("RescueUntil", sim.rescueUntil)
	syncFlight(round) -- 웜홀·새총은 거리·속도가 바로 바뀜
	updateCrisis(round)
	Net.event("ItemUsed"):FireAllClients({
		item = boosterId,
		itemName = info.Name,
		name = member.name,
		userId = member.userId,
		seat = member.seat,
		isBot = member.isBot,
		thanksSeconds = Config.Rescue.ThanksWindow,
	})

	-- 봇도 하트를 보냄 (연출용, 지표에는 세지 않음). 다음 부스터가 쓰이면 그쪽으로 넘어감
	for _, other: Member in ipairs(round.crew) do
		if other.isBot and other ~= member and rng:NextNumber() < Config.Bots.ThanksChance then
			local delaySeconds = 0.4 + rng:NextNumber() * (Config.Rescue.ThanksWindow - 1)
			task.delay(delaySeconds, function()
				if current == round and round.lastItem == item and not round.ended then
					item.thanksCount += 1
					Net.event("ThanksFx"):FireAllClients({
						fromSeat = other.seat,
						toSeat = member.seat,
						count = item.thanksCount,
					})
				end
			end)
		end
	end
	return true, nil
end

-- ------------------------------------------------------------ 정산
local function runResults(round: any)
	local sim = round.sim
	local distance: number = sim.x

	-- 부스터마다 늘린 거리 = 실제 거리 - 그 부스터 하나만 안 썼을 때의 거리
	local itemKm = 0
	local itemKms: { [string]: number } = {}
	local humanThanks = 0
	for _, item in ipairs(round.items) do
		local shadow = item.shadow
		if shadow then
			FlightSim.runToEnd(shadow)
			item.km = math.max(0, distance - shadow.x)
		end
		itemKm += item.km
		itemKms[item.member.id] = (itemKms[item.member.id] or 0) + item.km
		humanThanks += item.humanThanks
	end

	local entries = {}
	local memberById: { [string]: Member } = {}
	for _, member: Member in ipairs(round.crew) do
		memberById[member.id] = member
		if not member.left then
			table.insert(entries, {
				id = member.id,
				isBot = member.isBot,
				power = member.power,
				successes = member.successes,
				bestStreak = member.bestStreak,
			})
		end
	end
	local contributions = Scoring.contributionsFrom(distance, itemKms, entries)

	-- 시상 3종 (사람만)
	local heroId: string? = nil
	if distance > 0 then
		heroId = Scoring.hero(entries, contributions, pick)
	end
	local kingId = Scoring.missionKing(entries, pick)

	-- 구원자: 위기 구간에서 부스터를 쓴 사람 중 늘린 거리가 가장 큰 사람 (같으면 감사를 더 받은 사람, 그래도 같으면 먼저 쓴 사람).
	-- 봇은 시상에서 빠지고, 봇이 위기에 쓴 부스터는 따로 알림
	local saves: { [string]: any } = {}
	local saveOrder: { any } = {}
	local botSaveKm = 0
	local botSaveNames: { string } = {}
	for _, item in ipairs(round.items) do
		local member: Member = item.member
		if item.inCrisis then
			if member.isBot then
				botSaveKm += item.km
				table.insert(botSaveNames, item.name)
			elseif not member.left then
				local save = saves[member.id]
				if save == nil then
					save = { id = member.id, km = 0, thanks = 0, names = {} }
					saves[member.id] = save
					table.insert(saveOrder, save)
				end
				save.km += item.km
				save.thanks += item.thanksCount
				table.insert(save.names, item.name)
			end
		end
	end
	local save: any = nil
	for _, candidate in ipairs(saveOrder) do
		if save == nil
			or candidate.km > save.km + 1e-9
			or (math.abs(candidate.km - save.km) <= 1e-9 and candidate.thanks > save.thanks)
		then
			save = candidate
		end
	end
	local saviorId: string? = if save then save.id else nil
	local function itemLabel(names: { string }): string
		if #names == 1 then
			return names[1]
		end
		return string.format("부스터 %d개", #names)
	end
	local awardTickets: { [string]: number } = {}
	for _, id in ipairs({ heroId or "", kingId or "", saviorId or "" }) do
		if id ~= "" then
			awardTickets[id] = (awardTickets[id] or 0) + Config.Rewards.AwardTickets
		end
	end

	local previousBest = bestKm
	local newServerBest = distance > bestKm
	if newServerBest then
		bestKm = distance
	end

	local function awardInfo(id: string?, value: number, extra: number): any
		if id == nil then
			return nil
		end
		local member = memberById[id]
		return { name = member.name, userId = member.userId, seat = member.seat, value = value, extra = extra }
	end

	local stageIndex = Route.stageIndex(distance)
	local teamRate = if round.missionCount > 0 then round.rateSum / round.missionCount else 0
	local common = {
		round = round.number,
		km = distance,
		seconds = sim.t,
		escaped = sim.escaped,
		stage = stageIndex,
		stageName = Route.arrivalName(distance, sim.escaped),
		previousBest = previousBest,
		newServerBest = newServerBest,
		expectedKm = round.expectedKm,
		missions = round.missionCount,
		teamRate = teamRate,
		launch = round.launchQuality,
		itemKm = itemKm,
		hero = awardInfo(heroId, if heroId then contributions[heroId] or 0 else 0, 0),
		king = awardInfo(kingId, if kingId then memberById[kingId].bestStreak else 0, 0),
		savior = awardInfo(saviorId, if save then save.thanks else 0, if save then save.km else 0),
		saviorItem = if save then itemLabel(save.names) else "", -- 구원자가 위기에 쓴 부스터 이름
		botSave = if #botSaveNames > 0 then { km = botSaveKm, item = itemLabel(botSaveNames) } else nil,
	}

	local humans = 0
	local bots = 0
	for _, member: Member in ipairs(round.crew) do
		if member.isBot then
			bots += 1
		else
			humans += 1
		end
	end

	-- 황금 항로: 쓴 뒤로 난 거리의 코인이 배로 (탄 사람 모두)
	local goldenKm = if round.goldenFromKm ~= nil then math.max(0, distance - round.goldenFromKm) else 0
	local goldenInfo = Boosters.get("Golden")
	local goldenMultiplier = if goldenInfo then goldenInfo.Value else 1

	for _, player in ipairs(Players:GetPlayers()) do
		local member: Member? = round.byPlayer[player]
		local me: any = nil
		if member and not member.left then
			local coins = Scoring.coins(distance, member.afk, goldenKm, goldenMultiplier)
			local goldenCoins = coins - Scoring.coins(distance, member.afk)
			local tickets = awardTickets[member.id] or 0
			local newBest = distance > getNumber(player, "BestKm")
			if newBest then
				player:SetAttribute("BestKm", distance)
			end
			player:SetAttribute("Coins", getNumber(player, "Coins") + coins)
			if tickets > 0 then
				player:SetAttribute("Tickets", getNumber(player, "Tickets") + tickets)
			end
			local rank, people = Scoring.rank(member.id, contributions, entries)
			me = {
				coins = coins,
				goldenCoins = goldenCoins, -- 코인 중 황금 항로로 더 받은 몫
				tickets = tickets,
				contributionKm = contributions[member.id] or 0,
				rank = rank, -- 사람끼리의 순위 (영웅 시상과 같은 기준)
				crew = people,
				successes = member.successes,
				attempts = member.attempts,
				bestStreak = member.bestStreak,
				newBest = newBest,
				afk = member.afk,
				isHero = heroId == member.id,
				isKing = kingId == member.id,
				isSavior = saviorId == member.id,
			}
		end
		Net.event("Results"):FireClient(player, { common = common, me = me })
	end

	Metrics.endRound({
		round = round.number,
		km = distance,
		seconds = sim.t,
		humans = humans,
		bots = bots,
		escaped = sim.escaped,
		missions = round.missionCount,
		teamRate = teamRate,
		humanAttempts = round.humanAttempts,
		humanSuccesses = round.humanSuccesses,
		ticketsUsed = round.ticketsUsed,
		thanks = humanThanks,
		launch = round.launchQuality,
	})

	lastKingUserId = if kingId then memberById[kingId].userId else 0
	lastCaptainUserId = if round.captain then round.captain.userId else 0

	rollNextPlanet(Config.Phase.Results)
	setPhase("Results", Config.Phase.Results)
	waitPhase(Config.Phase.Results)
end

-- 판 정리: 좌석·봇을 치우고 모두 발사장으로
local function cleanup()
	current = nil
	Bots.clear()
	World.clearSeats()
	Assembly.clear(state)
	showBuild(nil, "")
	state:SetAttribute("CrewCount", 0)
	state:SetAttribute("CaptainUserId", 0)
	state:SetAttribute("CaptainName", "")
	state:SetAttribute("CaptainSeat", 0)
	resetFlightState()
	Seating.releaseAll()
	-- 다음 판은 정산 때 슬롯으로 뽑은 행성에서 (모두 발사장으로 돌아간 뒤에 바꿈).
	-- 비행 전에 끝난 판(아무도 안 탐)은 슬롯이 없었으므로 행성을 그대로 둠.
	local nextId = state:GetAttribute("NextPlanet")
	if typeof(nextId) == "string" and nextId ~= "" then
		local planet = Planets.get(nextId)
		if planet.Id == currentPlanetId() then
			planet = Planets.pick(currentPlanetId(), planetRng) -- 그사이 디버그로 같은 행성이 됐으면 다시 뽑음
		end
		setPlanet(planet)
	end
	clearSlot()
end

local function runRound()
	local joined = runJoin()
	local round = runBuild(joined)
	if round == nil then
		cleanup()
		return
	end
	runCountdown(round)
	runFlight(round)
	runResults(round)
	cleanup()
end

-- ------------------------------------------------------------ 플레이어
local function onPlayerAdded(player: Player)
	player:SetAttribute("Tickets", Config.Rewards.StartTickets)
	player:SetAttribute("Coins", 0)
	player:SetAttribute("BestKm", 0)
	player:SetAttribute("Joined", false)
	player:SetAttribute("Seat", 0)
	player:SetAttribute("Captain", false)
	player:SetAttribute("SpawnIndex", #Players:GetPlayers())
	-- 시프트 락을 켜면 마우스가 화면 가운데에 묶여 탑승 버튼을 누를 수 없으므로 끔 (이 값은 서버에서만 바꿀 수 있음)
	pcall(function()
		player.DevEnableMouseLock = false
	end)
	if state:GetAttribute("Phase") == "Join" then
		player:SetAttribute("Role", "Lobby")
	else
		-- 판 도중에 들어온 사람은 유령으로 관전
		lateGhosts += 1
		player:SetAttribute("GhostIndex", lateGhosts)
		player:SetAttribute("Role", "Ghost")
	end
	player.CharacterAdded:Connect(function(character: Model)
		Seating.onCharacterAdded(player, character)
	end)
	local character = player.Character
	if character then
		task.spawn(Seating.onCharacterAdded, player, character)
	end
end

local function onPlayerRemoving(player: Player)
	local round = current
	if round then
		local member = round.byPlayer[player]
		if member then
			member.left = true
		end
	end
end

local function connectRemotes()
	Net.event("Join").OnServerEvent:Connect(function(player: Player, wantJoin: any)
		if state:GetAttribute("Phase") == "Join" then
			player:SetAttribute("Joined", wantJoin == true)
		end
	end)

	Net.event("Launch").OnServerEvent:Connect(function(player: Player, pressedAt: any)
		local round = current
		if round == nil or state:GetAttribute("Phase") ~= "Countdown" or round.launchPress ~= nil then
			return
		end
		if round.captain == nil or round.captain.player ~= player then
			return
		end
		-- 누른 시각은 클라이언트가 잰 서버 시각. 터무니없는 값은 받은 시각으로 고침.
		local t = now()
		local reported = t
		if typeof(pressedAt) == "number" and pressedAt == pressedAt then
			reported = math.clamp(pressedAt, t - 0.5, t)
		end
		if reported < getNumber(state, "LaunchAt") - Config.Captain.EarlyLimit then
			return -- 너무 일찍 누른 것은 무시
		end
		round.launchPress = reported
	end)

	Net.event("MissionInput").OnServerEvent:Connect(function(player: Player, missionId: any, kind: any, inputs: any)
		local round = current
		if round == nil then
			return
		end
		local mission = round.mission
		local member = round.byPlayer[player]
		if mission == nil or member == nil or mission.id ~= missionId then
			return
		end
		mission.touched[member.id] = true
		if kind == "done" and mission.done[member.id] ~= true and Missions.check(mission.sequence, inputs) then
			mission.done[member.id] = true
		end
	end)

	-- 조립 화면에서 칸을 누름 / 남은 부품 자동으로 꽂기 (조립 단계에서 탄 사람만)
	Net.event("PlacePart").OnServerEvent:Connect(function(player: Player, typeId: any, cell: any)
		local round = current
		if round == nil or round.assembly == nil or state:GetAttribute("Phase") ~= "Build" then
			return
		end
		local member = round.byPlayer[player]
		if member then
			Assembly.place(round.assembly, member, typeId, cell)
		end
	end)

	Net.event("AutoPlace").OnServerEvent:Connect(function(player: Player)
		local round = current
		if round == nil or round.assembly == nil or state:GetAttribute("Phase") ~= "Build" then
			return
		end
		local member = round.byPlayer[player]
		if member then
			Assembly.autoPlace(round.assembly, member)
		end
	end)

	Net.event("UseItem").OnServerEvent:Connect(function(player: Player, itemId: any)
		local round = current
		local info = Boosters.get(itemId)
		if round == nil or info == nil then
			return
		end
		local member = round.byPlayer[player]
		if member and not member.left then
			local ok, reason = useBooster(round, member, info.Id)
			if not ok and reason then
				Net.event("Announce"):FireClient(player, reason)
			end
		end
	end)

	Net.event("Thanks").OnServerEvent:Connect(function(player: Player)
		local round = current
		if round == nil or round.lastItem == nil or round.ended then
			return
		end
		local item = round.lastItem
		if now() > item.thanksUntil or item.member.player == player or item.thanks[player.UserId] then
			return
		end
		item.thanks[player.UserId] = true
		item.thanksCount += 1
		item.humanThanks += 1
		player:SetAttribute("Coins", getNumber(player, "Coins") + Config.Rescue.ThanksCoins)
		local member = round.byPlayer[player]
		Net.event("ThanksFx"):FireAllClients({
			fromSeat = if member then member.seat else 0,
			toSeat = item.member.seat,
			count = item.thanksCount,
		})
	end)
end

-- ------------------------------------------------------------ 시작과 디버그
function Round.start()
	state = Instance.new("Folder")
	state.Name = Net.StateName
	state:SetAttribute("Phase", "Join")
	state:SetAttribute("PhaseEndsAt", 0)
	state:SetAttribute("Round", 0)
	state:SetAttribute("JoinedCount", 0)
	state:SetAttribute("PlayerCount", 0)
	state:SetAttribute("CrewCount", 0)
	state:SetAttribute("CaptainUserId", 0)
	state:SetAttribute("CaptainName", "")
	state:SetAttribute("CaptainSeat", 0)
	state:SetAttribute("ExpectedKm", 0)
	state:SetAttribute("BestKm", 0)
	state:SetAttribute("LaunchAt", 0)
	showBuild(nil, "")
	resetFlightState()
	showOptions()
	setPlanet(Planets.pick("", planetRng))
	clearSlot()
	state.Parent = ReplicatedStorage

	connectRemotes()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			local ok, message = xpcall(runRound, debug.traceback)
			if not ok then
				warn("[ROFLY] 판 진행 중 오류가 나서 대기 상태로 돌아갑니다:\n" .. tostring(message))
				pcall(cleanup)
				task.wait(3)
			end
		end
	end)
end

function Round.skip()
	skipRequested = true
end

-- 목록 순서대로 다음 행성으로 바꾸고 그 이름을 돌려줌 (디버그 패널에서 행성을 하나씩 넘겨 볼 때)
function Round.nextPlanet(): string
	local planet = Planets.after(currentPlanetId())
	setPlanet(planet)
	return planet.Name
end

function Round.setBotFill(count: number)
	options.botFillTo = math.clamp(math.floor(count), 1, 50)
	showOptions()
end

function Round.setBotSkill(id: string)
	for _, skill in ipairs(Config.Bots.Skills) do
		if skill.Id == id then
			options.botSkill = id
		end
	end
	showOptions()
end

function Round.setGear(id: string)
	options.gear = Parts.preset(id).Id
	showOptions()
end

-- 봇 하나가 구원 연료를 쓰게 함 (감사 버튼 시험용)
function Round.botUseRescue(): boolean
	local round = current
	if round == nil then
		return false
	end
	local bots: { Member } = {}
	for _, member: Member in ipairs(round.crew) do
		if member.isBot then
			table.insert(bots, member)
		end
	end
	if #bots == 0 then
		return false
	end
	local ok = useBooster(round, bots[pick(#bots)], "RescueFuel")
	return ok
end

-- 위기 구간 직전으로 건너뜀 (구원 연료·감사 버튼 시험용). 실제 건너뛰기는 비행 루프가 합니다.
function Round.forceCrisis(): boolean
	local round = current
	if round == nil or round.sim == nil or round.sim.ended or state:GetAttribute("Phase") ~= "Flight" then
		return false
	end
	round.fastForward = true
	return true
end

return Round
