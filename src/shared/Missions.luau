--!strict
-- 방향 미션 규칙 (순수 계산)

local Config = require(script.Parent.Config)

local Missions = {}

export type Params = { Inputs: number, Limit: number }

-- 챕터별 입력 수와 제한 시간
function Missions.params(chapterIndex: number): Params
	local list = Config.Mission.ByChapter
	return list[math.clamp(chapterIndex, 1, #list)]
end

-- k번째(1부터) 미션이 판정되는 시각(비행 시작 후 초)
function Missions.resolveTime(k: number): number
	return Config.Mission.FirstAt + (k - 1) * Config.Mission.Interval
end

-- 입력 순서를 무작위로 만듦. pick(n) 은 1..n 중 하나를 돌려주는 함수.
function Missions.generate(count: number, pick: (number) -> number): { string }
	local keys = Config.Mission.Keys
	local sequence: { string } = {}
	for i = 1, count do
		sequence[i] = keys[pick(#keys)]
	end
	return sequence
end

function Missions.isKey(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	for _, key in ipairs(Config.Mission.Keys) do
		if key == value then
			return true
		end
	end
	return false
end

-- 플레이어가 보낸 입력이 미션과 같은지 확인 (클라이언트가 보낸 값이라 모양부터 확인)
function Missions.check(sequence: { string }, inputs: any): boolean
	if type(inputs) ~= "table" then
		return false
	end
	if #inputs ~= #sequence then
		return false
	end
	for i, key in ipairs(sequence) do
		if inputs[i] ~= key then
			return false
		end
	end
	return true
end

return Missions
