--!strict
-- 정산 계산 (순수 계산): 기여 거리, 시상, 코인

local Config = require(script.Parent.Config)

local Scoring = {}

export type Entry = {
	id: string,
	isBot: boolean,
	power: number, -- 그 사람 부품 파워 합
	successes: number, -- 미션 성공 수
	bestStreak: number, -- 미션 최고 연속 성공
}

-- 기여 거리(km): 아이템으로 늘린 거리는 쓴 사람 몫, 나머지는 부품 파워 비율과 미션 성공 수로 반씩 나눔.
function Scoring.contributions(
	distanceKm: number,
	itemKm: number,
	itemUserId: string?,
	entries: { Entry }
): { [string]: number }
	local result: { [string]: number } = {}
	local count = #entries
	if count == 0 then
		return result
	end
	local item = 0
	if itemUserId ~= nil then
		item = math.clamp(itemKm, 0, distanceKm)
	end
	local rest = distanceKm - item
	local totalPower = 0
	local totalSuccess = 0
	for _, entry in ipairs(entries) do
		totalPower += entry.power
		totalSuccess += entry.successes
	end
	for _, entry in ipairs(entries) do
		local powerShare = if totalPower > 0 then entry.power / totalPower else 1 / count
		local missionShare = if totalSuccess > 0 then entry.successes / totalSuccess else 1 / count
		local km = rest * 0.5 * powerShare + rest * 0.5 * missionShare
		if entry.id == itemUserId then
			km += item
		end
		result[entry.id] = km
	end
	return result
end

-- 점수가 가장 높은 사람(봇 제외). 동점이면 pick 으로 무작위. 후보가 없으면 nil.
local function best(entries: { Entry }, score: (Entry) -> number, minScore: number, pick: (number) -> number): string?
	local top = -math.huge
	local tied: { string } = {}
	for _, entry in ipairs(entries) do
		if not entry.isBot then
			local value = score(entry)
			if value >= minScore then
				if value > top + 1e-9 then
					top = value
					tied = { entry.id }
				elseif math.abs(value - top) <= 1e-9 then
					table.insert(tied, entry.id)
				end
			end
		end
	end
	if #tied == 0 then
		return nil
	end
	return tied[pick(#tied)]
end

-- 영웅: 기여 거리 1위
function Scoring.hero(entries: { Entry }, contributions: { [string]: number }, pick: (number) -> number): string?
	return best(entries, function(entry: Entry): number
		return contributions[entry.id] or 0
	end, 0, pick)
end

-- 미션왕: 최고 연속 성공 1위 (한 번은 성공해야 함)
function Scoring.missionKing(entries: { Entry }, pick: (number) -> number): string?
	return best(entries, function(entry: Entry): number
		return entry.bestStreak
	end, 1, pick)
end

-- 기여 거리 순위 (1위부터, 봇 포함 전체 승무원 기준)
function Scoring.rank(id: string, contributions: { [string]: number }): number
	local mine = contributions[id] or 0
	local rank = 1
	for otherId, km in pairs(contributions) do
		if otherId ~= id and km > mine + 1e-9 then
			rank += 1
		end
	end
	return rank
end

-- 코인: 거리만큼. 자리 비움이면 절반.
function Scoring.coins(distanceKm: number, afk: boolean): number
	local coins = math.floor(distanceKm * Config.Rewards.CoinsPerKm)
	if afk then
		coins = math.floor(coins * Config.Rewards.AfkCoinFactor)
	end
	return coins
end

return Scoring
