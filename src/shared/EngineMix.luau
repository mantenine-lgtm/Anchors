--!strict
-- 엔진음 섞기: 지금 비행 상태에서 엔진음 세 겹(굉음·웅웅 소리·바람)의 크기 비율과 높이를 계산합니다.
-- Roblox 기능을 쓰지 않는 순수 계산이라 검사 도구에서 그대로 돌려 볼 수 있습니다. 수치는 Config.EngineSound.
-- 실제로 소리를 내고 값을 부드럽게 따라가는 일은 클라이언트의 Sfx.luau 가 합니다.

local Config = require(script.Parent.Config)
local FlightSim = require(script.Parent.FlightSim)

local EngineMix = {}

export type Input = {
	phase: string, -- 판 페이즈 ("Countdown", "Flight", "Results" ...)
	countdownLeft: number, -- 카운트다운에서 발사 시각까지 남은 초
	t: number, -- 비행 시간(초)
	hot: number, -- 최대 출력이 끝나는 비행 시각 (서버 속성 HotTime)
	fuel: number, -- 연료가 끝나는 시각 (FuelTime)
	sail: number, -- 세일이 버티는 시간 (SailTime)
	rescueUntil: number, -- 구원 연료가 끝나는 시각 (안 썼으면 -1)
	turboUntil: number, -- 터보 엔진이 끝나는 시각 (안 썼으면 -1)
	speed: number, -- km/s
	km: number,
	kick: number, -- 미션 성공·부스터를 쓴 순간에 잠깐 더해지는 힘 (0~1, Sfx 가 줄여 감)
	ended: boolean, -- 비행이 끝났는지 (충격파에 잡힘·탈출)
}

-- 크기는 Config.EngineSound 의 각 소리 Volume 에 곱하는 비율, 높이는 PlaybackSpeed
export type Mix = {
	roar: number,
	roarPitch: number,
	hum: number,
	humPitch: number,
	wind: number,
	windPitch: number,
}

local function silent(): Mix
	return { roar = 0, roarPitch = 1, hum = 0, humPitch = 1, wind = 0, windPitch = 1 }
end

-- 지금 비행 구간("hot" 최대 출력, "cruise" 순항, "sail" 솔라 세일, "coast" 관성, "rescue" 구원 연료)
function EngineMix.segment(input: Input): string
	return FlightSim.phaseAt(input.t, input.hot, input.fuel, input.sail, input.rescueUntil)
end

local function segmentThrust(segment: string): number
	local T = Config.EngineSound.Thrust
	if segment == "rescue" then
		return T.rescue
	elseif segment == "hot" then
		return T.hot
	elseif segment == "cruise" then
		return T.cruise
	elseif segment == "sail" then
		return T.sail
	end
	return T.coast
end

-- 추력 (구간별 0~1, 터보 엔진이 켜져 있으면 1을 넘을 수 있음)
function EngineMix.thrust(input: Input): number
	local E = Config.EngineSound
	local thrust = segmentThrust(EngineMix.segment(input))
	if input.t < input.turboUntil then
		thrust += E.TurboThrust
	end
	return thrust
end

-- 대기권 안에서 빠를수록 커지는 바람 (0~1). 대기권 끝(100 km)에 가까워지면 공기가 옅어져 줄고, 벗어나면 0.
function EngineMix.air(km: number, speedKmPerSecond: number): number
	local E = Config.EngineSound
	local endKm = Config.Route.Chapters[1].EndKm
	local metersPerSecond = speedKmPerSecond * 1000
	local fast = math.clamp((metersPerSecond - E.WindStartSpeed) / (E.WindFullSpeed - E.WindStartSpeed), 0, 1)
	local thick = math.clamp((endKm - km) / (endKm - Config.Atmosphere.ThinAirKm), 0, 1) -- 대기권 밖이면 0
	return fast * thick
end

function EngineMix.mix(input: Input): Mix
	local E = Config.EngineSound
	local out = silent()
	if input.phase == "Countdown" then
		-- 발사 직전 엔진 예열: 마지막 PreIgniteSeconds 초 동안 웅웅 소리가 낮은 소리로 차오름
		local left = input.countdownLeft
		if E.PreIgniteSeconds > 0 and left < E.PreIgniteSeconds then
			out.hum = E.PreIgniteLevel * math.clamp(1 - left / E.PreIgniteSeconds, 0, 1)
			out.humPitch = E.SpoolPitch
		end
		return out
	end
	if input.phase ~= "Flight" or input.ended then
		return out
	end

	local thrust = EngineMix.thrust(input)
	local power = math.clamp(thrust, 0, 1)
	local turbo = math.max(thrust - 1, 0) -- 터보로 1을 넘은 만큼
	local kick = math.clamp(input.kick, 0, 1)
	-- 발사 직후: 엔진이 힘을 받으며 높이가 SpoolPitch 에서 1까지 오르고, 크기가 잠깐 더 큼
	local spool = E.SpoolPitch + (1 - E.SpoolPitch) * math.clamp(input.t / E.SpoolSeconds, 0, 1)
	local surge = 1 + E.LaunchSurge * math.clamp(1 - input.t / E.SurgeSeconds, 0, 1)
	-- 빠를수록 조금 높게 (10 m/s 쯤부터 1만 m/s 까지 로그로 0~1)
	local metersPerSecond = math.max(input.speed, 0) * 1000
	local fast = math.clamp(math.log10(1 + metersPerSecond / 10) / 3, 0, 1)
	local lift = E.SpeedPitch * fast + E.TurboPitch * math.clamp(turbo / E.TurboThrust, 0, 1) + E.KickPitch * kick

	out.roar = math.clamp(power * surge + turbo + E.KickVolume * kick, 0, E.MaxLevel)
	out.roarPitch = spool * (E.RoarPitchLow + (1 - E.RoarPitchLow) * power + lift)
	out.hum = math.clamp((E.HumFloor + (1 - E.HumFloor) * power) * surge, 0, E.MaxLevel)
	out.humPitch = spool * (E.HumPitchLow + (1 - E.HumPitchLow) * power + lift)
	local air = EngineMix.air(input.km, input.speed)
	out.wind = air
	out.windPitch = E.WindPitchLow + (E.WindPitchHigh - E.WindPitchLow) * air
	return out
end

return EngineMix
