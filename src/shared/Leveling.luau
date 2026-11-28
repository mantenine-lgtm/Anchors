--!strict
-- 부품 레벨과 경험치 곡선 (수치는 Config.Progress, 밸런스 스레드 11-27).
-- 다음 레벨까지 경험치 = 내림(ExpRarityFactor[레어도] × (레벨 + ExpLevelOffset)² / ExpDivisor). 만렙(MaxLevel)이면 더 쌓이지 않음.
-- 초반엔 잘 오르고 갈수록 힘들어짐 (Nick 11-27: 만렙까지 약 2000판).
-- 경험치는 '지금 레벨에서 쌓인 양'으로 다룹니다 (레벨이 오르면 넘친 만큼만 남음). 만렙이면 경험치는 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Leveling = {}

local P = Config.Progress

Leveling.MaxLevel = P.MaxLevel

local function factor(rarity: number?): number
	local list = P.ExpRarityFactor
	return list[math.clamp(math.floor(rarity or 1), 1, #list)]
end

-- 그 레벨에서 다음 레벨까지 필요한 경험치 (만렙이면 0)
function Leveling.need(level: number, rarity: number?): number
	level = math.max(math.floor(level), 1)
	if level >= P.MaxLevel then
		return 0
	end
	local base = level + P.ExpLevelOffset
	return math.floor(factor(rarity) * base * base / P.ExpDivisor)
end

-- 경험치 gain 을 더한 뒤의 (레벨, 지금 레벨에서 쌓인 경험치, 오른 레벨 수)
function Leveling.add(level: number, exp: number, gain: number, rarity: number?): (number, number, number)
	level = math.clamp(math.floor(level), 1, P.MaxLevel)
	if level >= P.MaxLevel then
		return P.MaxLevel, 0, 0
	end
	-- 음수·NaN 은 0 으로 (NaN 이 들어가면 비교가 모두 거짓이라 만렙까지 올라 버림)
	exp = (if exp > 0 then exp else 0) + (if gain > 0 then gain else 0)
	local ups = 0
	while level < P.MaxLevel do
		local need = Leveling.need(level, rarity)
		if exp < need then
			break
		end
		exp -= need
		level += 1
		ups += 1
	end
	if level >= P.MaxLevel then
		exp = 0
	end
	return level, exp, ups
end

-- 그 레벨에서 levels 만큼 오르는 데 필요한 경험치 (지금 쌓인 양 exp 를 뺀 값, 만렙에서 멈춤)
function Leveling.toGain(level: number, exp: number, levels: number, rarity: number?): number
	level = math.clamp(math.floor(level), 1, P.MaxLevel)
	local total = if exp > 0 then -exp else 0
	local target = math.min(level + math.max(math.floor(levels), 0), P.MaxLevel)
	for l = level, target - 1 do
		total += Leveling.need(l, rarity)
	end
	local gain = math.max(total, 0)
	-- 쌓인 경험치에 소수가 있으면 빼고 다시 더할 때 반올림으로 아주 조금 모자라 한 레벨 덜 오를 수 있음
	-- (디버그 +1000 이 가끔 999 만 오르던 것). 그러면 레벨 하나에 드는 양보다 훨씬 작게 조금 더 줌
	for _ = 1, 4 do
		local _, _, ups = Leveling.add(level, exp, gain, rarity)
		if ups >= target - level then
			break
		end
		gain += math.max(gain, 1) * 1e-12
	end
	return gain
end

-- 경험치 막대 길이 (0~1). 만렙이면 1
function Leveling.fraction(level: number, exp: number, rarity: number?): number
	local need = Leveling.need(level, rarity)
	if need <= 0 then
		return 1
	end
	return math.clamp(exp / need, 0, 1)
end

return Leveling
