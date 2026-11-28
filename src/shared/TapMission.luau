--!strict
-- 연타 미션 규칙 (순수 계산, 수치는 Config.Tap).
-- 방향 미션 몇 번에 한 번은 연타 미션: 정해진 시간 동안 탄 사람 모두가 버튼을 빠르게 누르고,
-- 로켓 전체의 연타 합계가 클수록 그 미션의 가속이 커집니다 (합계가 두 배가 될 때마다 1단계).
-- 서버(Round)가 누적 횟수를 받아 합계를 내고, 화면(MissionUi)은 같은 계산으로 단계 게이지를 그립니다.

local Config = require(script.Parent.Config)

local T = Config.Tap

local TapMission = {}

-- 시험 방식 Id 가 맞으면 그 Id, 아니면 기본 ("normal" | "all" | "off")
function TapMission.mode(id: any): string
	for _, mode in ipairs(T.Modes) do
		if mode.Id == id then
			return mode.Id
		end
	end
	return T.Default
end

function TapMission.modeName(id: any): string
	local mode = TapMission.mode(id)
	for _, info in ipairs(T.Modes) do
		if info.Id == mode then
			return info.Name
		end
	end
	return mode
end

-- index 번째(1부터) 미션이 연타 미션인지
function TapMission.isTap(index: number, mode: string?): boolean
	local m = TapMission.mode(mode)
	if m == "off" then
		return false
	elseif m == "all" then
		return true
	end
	return index >= T.First and (index - T.First) % T.Every == 0
end

-- 연타 단계 (0 ~ MaxLevel, 소수 포함) = log2(1 + 합계 / Ref)
function TapMission.level(total: number): number
	if not (total > 0) then
		return 0
	end
	return math.min(math.log(1 + total / T.Ref) / math.log(2), T.MaxLevel)
end

-- level 단계가 되는 합계 (게이지 눈금): Ref × (2^level − 1)
function TapMission.threshold(level: number): number
	return T.Ref * (2 ^ level - 1)
end

-- 그 미션의 가속 배율: 1 + PerLevel × 단계
function TapMission.factor(total: number): number
	return 1 + T.PerLevel * TapMission.level(total)
end

-- 한 사람이 성공했는지
function TapMission.success(taps: number): boolean
	return taps >= T.MinTaps
end

-- 클라이언트가 보낸 누적 횟수를 받아 줄 값 (서버). previous = 지금까지 받은 값, elapsed = 미션을 띄운 뒤 흐른 초.
-- 숫자가 아니거나 줄어든 값은 무시(previous 그대로), 소수는 버림, 1초에 MaxPerSecond 번(통신 지연 여유 0.5초 포함)
-- 넘게는 세지 않음.
function TapMission.accept(previous: number, reported: any, elapsed: number): number
	if type(reported) ~= "number" or reported ~= reported then
		return previous
	end
	local seconds = math.clamp(elapsed, 0, T.Seconds + Config.Mission.InputGrace) + 0.5
	local cap = math.floor(seconds * T.MaxPerSecond)
	local value = math.clamp(math.floor(reported), 0, cap)
	return math.max(previous, value)
end

-- 승무원 crew 명이 한 사람당 ExpectedPerPerson 번 누를 때의 배율 (조립 화면 예상 거리용). '끄기'면 1
function TapMission.expected(crew: number, mode: string?): number
	if TapMission.mode(mode) == "off" then
		return 1
	end
	return TapMission.factor(math.max(crew, 0) * T.ExpectedPerPerson)
end

return TapMission
