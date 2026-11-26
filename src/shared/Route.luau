--!strict
-- 루트: 거리(km)가 어느 스테이지·챕터인지 알려 줍니다.

local Config = require(script.Parent.Config)

local Route = {}

export type Stage = { Name: string, EndKm: number, Chapter: number }

local stages = Config.Route.Stages
local chapters = Config.Route.Chapters

function Route.stageCount(): number
	return #stages
end

-- 거리(km)가 속한 스테이지 번호 (1부터). 루트 끝을 넘으면 마지막 스테이지.
function Route.stageIndex(km: number): number
	for i, stage in ipairs(stages) do
		if km < stage.EndKm then
			return i
		end
	end
	return #stages
end

function Route.stage(index: number): Stage
	local i = math.clamp(index, 1, #stages)
	return stages[i]
end

function Route.stageStartKm(index: number): number
	if index <= 1 then
		return 0
	end
	return Route.stage(index - 1).EndKm
end

-- 챕터 번호 (1 대기권, 2 지구 궤도, 3 달, 4 태양계)
function Route.chapterIndex(km: number): number
	for i, chapter in ipairs(chapters) do
		if km < chapter.EndKm then
			return i
		end
	end
	return #chapters
end

function Route.chapterName(index: number): string
	local i = math.clamp(index, 1, #chapters)
	return chapters[i].Name
end

-- 스테이지 번호, 그 스테이지 안에서의 진행(0~1), 다음 스테이지까지 남은 km
function Route.progress(km: number): (number, number, number)
	local index = Route.stageIndex(km)
	local startKm = Route.stageStartKm(index)
	local endKm = Route.stage(index).EndKm
	local span = math.max(endKm - startKm, 1e-9)
	local fraction = math.clamp((km - startKm) / span, 0, 1)
	return index, fraction, math.max(endKm - km, 0)
end

-- 전광판 궤적 표시용: 0~1 (로그 눈금이라 초반 스테이지도 보임)
function Route.logPosition(km: number): number
	local total = math.log10(1 + Config.Flight.RouteEnd)
	return math.clamp(math.log10(1 + math.max(km, 0)) / total, 0, 1)
end

return Route
