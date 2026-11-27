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

-- 기여 거리(km): 부스터로 늘린 거리는 쓴 사람 몫, 나머지는 부품 파워 비율과 미션 성공 수로 반씩 나눔.
-- itemKms: 승무원 id -> 그 사람이 쓴 부스터로 늘린 거리. 합이 비행 거리보다 크면(부스터끼리 효과가 겹칠 때)
-- 비행 거리에 맞게 같은 비율로 줄입니다. 목록에 없는 id(나간 사람 등)의 몫은 나머지로 돌아갑니다.
function Scoring.contributionsFrom(distanceKm: number, itemKms: { [string]: number }, entries: { Entry }): { [string]: number }
	local result: { [string]: number } = {}
	local count = #entries
	if count == 0 then
		return result
	end
	local items: { [string]: number } = {}
	local itemSum = 0
	for _, entry in ipairs(entries) do
		local km = math.max(itemKms[entry.id] or 0, 0)
		if km > 0 then
			items[entry.id] = km
			itemSum += km
		end
	end
	local limit = math.max(distanceKm, 0)
	if itemSum > limit and itemSum > 0 then
		local factor = limit / itemSum
		for id, km in pairs(items) do
			items[id] = km * factor
		end
		itemSum = limit
	end
	local rest = distanceKm - itemSum
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
		result[entry.id] = km + (items[entry.id] or 0)
	end
	return result
end

-- 부스터를 한 사람만 쓴 경우 (예전 형태)
function Scoring.contributions(
	distanceKm: number,
	itemKm: number,
	itemUserId: string?,
	entries: { Entry }
): { [string]: number }
	local itemKms: { [string]: number } = {}
	if itemUserId ~= nil then
		itemKms[itemUserId] = math.clamp(itemKm, 0, math.max(distanceKm, 0))
	end
	return Scoring.contributionsFrom(distanceKm, itemKms, entries)
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

-- 기여 거리 순위(1위부터)와 견준 사람 수. 시상과 같은 기준으로 사람끼리만 견줍니다 (봇 제외).
function Scoring.rank(id: string, contributions: { [string]: number }, entries: { Entry }): (number, number)
	local mine = contributions[id] or 0
	local rank = 1
	local people = 0
	for _, entry in ipairs(entries) do
		if not entry.isBot then
			people += 1
			if entry.id ~= id and (contributions[entry.id] or 0) > mine + 1e-9 then
				rank += 1
			end
		end
	end
	return rank, people
end

-- 코인: 거리만큼. 황금 항로를 쓴 뒤로 난 거리(goldenKm)는 goldenMultiplier 배. 자리 비움이면 절반.
function Scoring.coins(distanceKm: number, afk: boolean, goldenKm: number?, goldenMultiplier: number?): number
	local km = distanceKm
	if goldenKm ~= nil and goldenMultiplier ~= nil and goldenKm > 0 then
		km += math.clamp(goldenKm, 0, math.max(distanceKm, 0)) * (goldenMultiplier - 1)
	end
	local coins = math.floor(km * Config.Rewards.CoinsPerKm)
	if afk then
		coins = math.floor(coins * Config.Rewards.AfkCoinFactor)
	end
	return coins
end

return Scoring
