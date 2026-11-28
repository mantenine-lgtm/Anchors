--!strict
-- 부품 레벨과 경험치 곡선 (수치는 Config.Progress, 경제 v9 11-28).
-- 다음 레벨까지 경험치 = 내림(ExpRarityFactor[레어도] × (레벨 + ExpLevelOffset)² / ExpDivisor). 만렙(MaxLevel)이면 더 쌓이지 않음.
-- 초반엔 잘 오르고 갈수록 힘들어짐 (Nick 11-27: 만렙까지 약 2000판, 11-28: 초반을 더 느리게).
-- 경험치는 '지금 레벨에서 쌓인 양'으로 다룹니다 (레벨이 오르면 넘친 만큼만 남음). 만렙이면 경험치는 0.
-- 돌파(★) 한도: 레벨은 Leveling.cap(★) 에서 멈추고, 그 뒤로 얻는 경험치는 지금 레벨에 쌓아 둡니다(다음 레벨 필요량보다 많을 수 있음).
-- 돌파로 한도가 오르면 쌓인 경험치가 한꺼번에 레벨로 바뀝니다 (Leveling.add 에 gain 0 과 새 한도를 줌).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Leveling = {}

local P = Config.Progress

Leveling.MaxLevel = P.MaxLevel
Leveling.MaxStars = P.MaxStars

local function factor(rarity: number?): number
	local list = P.ExpRarityFactor
	return list[math.clamp(math.floor(rarity or 1), 1, #list)]
end

-- 돌파 단계(★)의 만렙 한도: ★1 2,000 … ★5 10,000 (만렙을 넘지 않음)
function Leveling.cap(star: number?): number
	local s = math.clamp(math.floor(star or 1), 1, P.MaxStars)
	return math.min(P.MaxLevel, P.LevelsPerStar * s)
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

-- 경험치 gain 을 더한 뒤의 (레벨, 지금 레벨에서 쌓인 경험치, 오른 레벨 수).
-- cap 을 주면 그 레벨에서 멈추고 남은 경험치는 쌓아 둠 (없으면 만렙까지)
function Leveling.add(level: number, exp: number, gain: number, rarity: number?, cap: number?): (number, number, number)
	level = math.clamp(math.floor(level), 1, P.MaxLevel)
	if level >= P.MaxLevel then
		return P.MaxLevel, 0, 0
	end
	local top = math.clamp(math.floor(cap or P.MaxLevel), 1, P.MaxLevel)
	-- 음수·NaN 은 0 으로 (NaN 이 들어가면 비교가 모두 거짓이라 만렙까지 올라 버림)
	exp = (if exp > 0 then exp else 0) + (if gain > 0 then gain else 0)
	local ups = 0
	while level < top do
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
	return math.max(total, 0)
end

-- 경험치 막대 길이 (0~1). 만렙이면 1, 한도에 닿아 쌓아 둔 경험치가 필요량보다 많아도 1
function Leveling.fraction(level: number, exp: number, rarity: number?): number
	local need = Leveling.need(level, rarity)
	if need <= 0 then
		return 1
	end
	return math.clamp(exp / need, 0, 1)
end

return Leveling
