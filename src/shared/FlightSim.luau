--!strict
-- 비행 계산. Roblox 기능을 쓰지 않는 순수 계산이라 서버·클라이언트 어디서나 같은 결과가 나옵니다.
-- 식과 계산 순서는 기획서 '수치 밸런스' 탭의 시뮬레이터(v8)와 같습니다.
-- 로켓도 충격파도 실제로 움직이지 않고, 숫자(거리·속도)만 계산합니다.

local Boosters = require(script.Parent.Boosters)
local Config = require(script.Parent.Config)

local F = Config.Flight

local FlightSim = {}

-- 종류별 파워 합계 (Parts.totals 가 만듦)
export type Totals = {
	engine: number,
	heat: number,
	fuel: number,
	sail: number,
	nav: number,
	core: number,
}

-- 파워 합계에서 나온 비행 성능
export type Stats = {
	v0: number, -- 발사 속도 (km/s)
	hot: number, -- 최대 출력이 끝나는 시각(초)
	fuel: number, -- 연료가 끝나는 시각(초)
	sail: number, -- 세일이 버티는 시간(초)
	kick: number, -- 미션 성공 가속
	step: number, -- 콤보 1단계당 가속 증가
}

export type Sim = {
	stats: Stats,
	t: number, -- 비행 시간(초)
	vb: number, -- 기본 속도 (km/s)
	boost: number, -- 미션 가속 (속도에 1 + boost 를 곱함)
	x: number, -- 로켓 거리 (km)
	w: number, -- 충격파 속도 (km/s)
	s: number, -- 충격파 거리 (km)
	combo: number,
	ended: boolean,
	escaped: boolean,
	rescueUntil: number, -- 구원 연료가 끝나는 시각 (안 썼으면 -1)
	rescueExtra: number,
	turboUntil: number, -- 터보 엔진이 끝나는 시각 (안 썼으면 -1)
	turboMultiplier: number, -- 터보 엔진이 켜져 있는 동안의 속도 배율
	resonanceUntil: number, -- 공명 코어가 끝나는 시각 (안 썼으면 -1)
	resonanceMultiplier: number, -- 공명 코어가 켜져 있는 동안의 미션 가속 배율
}

-- 파워 자릿수: 파워가 10배가 되면 1씩 늘어남
local function digits(total: number): number
	return math.log10(1 + math.max(total, 0) / F.RefPower)
end

function FlightSim.computeStats(totals: Totals): Stats
	local gEngine = digits(totals.engine)
	local gHeat = digits(totals.heat)
	local gFuel = digits(totals.fuel)
	local gSail = digits(totals.sail)
	local gNav = digits(totals.nav)
	local gCore = digits(totals.core)
	local fuelTime = F.FuelBase + F.FuelPerDigit * gFuel
	return {
		v0 = F.BaseSpeed * 10 ^ (gEngine * F.EngineExp),
		hot = math.min(F.HotBase + F.HotPerDigit * gHeat, fuelTime),
		fuel = fuelTime,
		sail = F.SailBase + F.SailPerDigit * gSail,
		kick = F.KickBase * 10 ^ (gNav * F.NavExp),
		step = F.ComboStepBase * 10 ^ (gCore * F.CoreExp),
	}
end

-- captainBonus: 선장 발사 타이밍 보너스 (0, 0.05, 0.10)
function FlightSim.new(totals: Totals, captainBonus: number): Sim
	local stats = FlightSim.computeStats(totals)
	return {
		stats = stats,
		t = 0,
		vb = stats.v0 * (1 + captainBonus),
		boost = 0,
		x = 0,
		w = F.WaveStartRatio * stats.v0,
		s = 0,
		combo = 0,
		ended = false,
		escaped = false,
		rescueUntil = -1,
		rescueExtra = 0,
		turboUntil = -1,
		turboMultiplier = 1,
		resonanceUntil = -1,
		resonanceMultiplier = 1,
	}
end

function FlightSim.clone(sim: Sim): Sim
	return table.clone(sim)
end

-- 지금 구간의 초당 속도 증가율
function FlightSim.rate(sim: Sim): number
	local st = sim.stats
	local t = sim.t
	if t < sim.rescueUntil then
		return F.WaveRate + F.WaveRateGrowth * t + sim.rescueExtra
	end
	if t < st.hot then
		return F.HotRate
	elseif t < st.fuel then
		return F.CruiseRate
	elseif t < st.fuel + st.sail then
		return F.SailRate
	end
	return -F.DecayRate
end

-- 화면 표시용 구간 이름: "rescue" | "hot" | "cruise" | "sail" | "coast"
function FlightSim.phaseAt(t: number, hot: number, fuel: number, sail: number, rescueUntil: number): string
	if t < rescueUntil then
		return "rescue"
	elseif t < hot then
		return "hot"
	elseif t < fuel then
		return "cruise"
	elseif t < fuel + sail then
		return "sail"
	end
	return "coast"
end

-- 터보 엔진이 켜져 있으면 그 배율, 아니면 1
local function turboFactor(sim: Sim): number
	if sim.t < sim.turboUntil then
		return sim.turboMultiplier
	end
	return 1
end

function FlightSim.speed(sim: Sim): number
	return sim.vb * (1 + sim.boost) * turboFactor(sim)
end

-- 미션 판정 반영. r = 팀 성공률(0~1)
function FlightSim.applyMission(sim: Sim, r: number)
	if r >= Config.Mission.ComboRule - 1e-9 then
		sim.combo = math.min(sim.combo + 1, F.ComboMax)
	else
		sim.combo = 0
	end
	local perfect = if r >= 1 - 1e-9 then F.PerfectMultiplier else 1
	local resonance = if sim.t < sim.resonanceUntil then sim.resonanceMultiplier else 1
	sim.boost += sim.stats.kick * r * (1 + sim.stats.step * sim.combo) * perfect * resonance
end

-- 한 칸(Dt) 진행. 이 칸에서 미션이 판정되면 missionRate 에 팀 성공률을 넘깁니다.
function FlightSim.step(sim: Sim, missionRate: number?)
	if sim.ended then
		return
	end
	local dt = F.Dt
	sim.vb *= math.exp(FlightSim.rate(sim) * dt)
	sim.boost *= math.exp(-dt / F.BoostDecayTime)
	if missionRate ~= nil then
		FlightSim.applyMission(sim, missionRate)
	end
	local v = sim.vb * (1 + sim.boost) * turboFactor(sim)
	sim.x += v * dt
	sim.w *= math.exp((F.WaveRate + F.WaveRateGrowth * sim.t) * dt)
	sim.s += sim.w * dt
	sim.t += dt
	if sim.x >= F.RouteEnd then
		sim.x = F.RouteEnd
		sim.ended = true
		sim.escaped = true
	elseif sim.s >= sim.x and sim.t > F.WaveGraceTime then
		sim.ended = true
	end
end

-- 앞으로 미션이 없다고 보고, 충격파에 따라잡힐 때까지 남은 시간(초). limit 보다 멀면 limit.
function FlightSim.eta(sim: Sim, limit: number): number
	local c = FlightSim.clone(sim)
	local t0 = c.t
	while not c.ended and c.t - t0 < limit do
		FlightSim.step(c)
	end
	if c.ended and not c.escaped then
		return c.t - t0
	end
	return limit
end

-- 구원 연료: 로켓 속도를 충격파 속도까지 끌어올리고 잠깐 같이 가속
function FlightSim.rescue(sim: Sim)
	local R = Config.Rescue
	local need = sim.w * R.Match / ((1 + sim.boost) * turboFactor(sim))
	if sim.vb < need then
		sim.vb = need
	end
	sim.rescueUntil = sim.t + R.Hold
	sim.rescueExtra = R.Extra
end

-- 부스터 효과를 비행 계산에 넣음. 황금 항로는 보상만 바꾸므로 여기서는 하는 일이 없습니다.
-- 효과를 넣을 수 있으면 true (이미 끝난 비행이거나 모르는 Id 면 false)
function FlightSim.applyBooster(sim: Sim, id: string): boolean
	local info = Boosters.get(id)
	if info == nil or sim.ended then
		return false
	end
	if id == "RescueFuel" then
		FlightSim.rescue(sim)
	elseif id == "Turbo" then
		sim.turboUntil = sim.t + info.Seconds
		sim.turboMultiplier = info.Value
	elseif id == "Slingshot" then
		sim.vb *= 1 + info.Value
	elseif id == "Wormhole" then
		-- 충격파는 그대로 두고 로켓만 앞으로. 루트 끝을 넘으면 탈출
		sim.x += FlightSim.speed(sim) * info.Seconds
		if sim.x >= F.RouteEnd then
			sim.x = F.RouteEnd
			sim.ended = true
			sim.escaped = true
		end
	elseif id == "Resonance" then
		sim.resonanceUntil = sim.t + info.Seconds
		sim.resonanceMultiplier = info.Value
	end
	return true
end

-- 미션 없이 끝까지 진행 (부스터를 안 썼을 때의 거리 계산용)
function FlightSim.runToEnd(sim: Sim)
	local guard = 0
	local maxSteps = Config.Phase.FlightMax / F.Dt
	while not sim.ended and guard < maxSteps do
		FlightSim.step(sim)
		guard += 1
	end
end

-- 미션 성공률이 계속 missionRate 라고 보고 처음부터 끝까지 계산. 거리(km)와 시간(초)을 돌려줌.
function FlightSim.predict(totals: Totals, captainBonus: number, missionRate: number): (number, number)
	local sim = FlightSim.new(totals, captainBonus)
	local nextMission = Config.Mission.FirstAt
	while not sim.ended and sim.t < Config.Phase.FlightMax do
		if sim.t >= nextMission then
			FlightSim.step(sim, missionRate)
			nextMission += Config.Mission.Interval
		else
			FlightSim.step(sim)
		end
	end
	return sim.x, sim.t
end

return FlightSim
