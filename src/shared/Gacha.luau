--!strict
-- 부품 뽑기 규칙 (Nick 11-28 "부품 뽑기도 추가"). 수치·규칙 설명은 Config.Gacha.
-- 서버(GachaService)가 뽑고, 화면(GachaUi)은 값·확률·뽑을 수 있는 단계를 보여 줄 때 씁니다.

local Catalog = require(script.Parent.Catalog)
local Config = require(script.Parent.Config)

local Gacha = {}

local G = Config.Gacha

-- 확률표 (일반·희귀·영웅·전설). 뽑기는 하나 (Nick 11-28 "일반 고급 최고급 넣지 말고 뽑기 일괄")
Gacha.Odds = G.Odds :: { number }

-- 뽑을 수 있는 단계 (카운트다운·비행 중에는 막힘)
local OPEN_PHASES: { [string]: boolean } = { Join = true, Build = true, Results = true }

function Gacha.isType(typeId: any): boolean
	for _, info in ipairs(Config.Parts.Types) do
		if info.Id == typeId then
			return true
		end
	end
	return false
end

function Gacha.typeName(typeId: string): string
	for _, info in ipairs(Config.Parts.Types) do
		if info.Id == typeId then
			return info.Name
		end
	end
	return typeId
end

function Gacha.open(phase: string): boolean
	return OPEN_PHASES[phase] == true
end

-- 앞 세 자리만 남기고 반올림 (217,615 -> 218,000)
local function round3(x: number): number
	if x < 1000 then
		return math.floor(x + 0.5)
	end
	local unit = 10 ^ (math.floor(math.log10(x)) - 2)
	return math.floor(x / unit + 0.5) * unit
end

-- 1회 값: 내 최고 기록(km) × PricePerKm, 적어도 BasePrice (코인을 km 만큼 받으므로 늘 한 판에 2번쯤)
function Gacha.unitPrice(bestKm: number?): number
	local km = if type(bestKm) == "number" and bestKm == bestKm and bestKm > 0 then bestKm else 0
	return math.max(G.BasePrice, round3(km * G.PricePerKm))
end

-- 값: 10회 뽑기는 1회 값 × TenPrice
function Gacha.price(bestKm: number?, ten: boolean): number
	return Gacha.unitPrice(bestKm) * (if ten then G.TenPrice else 1)
end

-- 받는 개수: 1 또는 TenCount
function Gacha.count(ten: boolean): number
	return if ten then G.TenCount else 1
end

-- 0~1 사이 수 u 로 레어도를 고름 (확률표를 차례로 더해 u 가 들어가는 칸). 확률이 0 인 레어도는 나오지 않음
function Gacha.rarityAt(u: number, odds: { number }?): number
	local list = odds or Gacha.Odds
	local total = 0
	for _, p in ipairs(list) do
		total += p
	end
	local x = math.clamp(u, 0, 1) * total
	local top = 1
	for rarity, p in ipairs(list) do
		if p > 0 then
			top = rarity
			if x < p then
				return rarity
			end
			x -= p
		end
	end
	return top -- 끝자리 오차: 확률이 있는 가장 높은 레어도
end

-- 한 번 뽑기: 그 종류·레어도 부품 중 하나 (같은 확률)
function Gacha.roll(typeId: string, rng: Random): Catalog.Variant?
	local rarity = Gacha.rarityAt(rng:NextNumber())
	local pool = Catalog.ofRarity(typeId, rarity)
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- 지금 부품(레어도·★)에 레어도 rarity 결과가 오면 어떻게 되는지: "new" 바꿔 낌 / "star" 돌파 / "exp" 경험치
function Gacha.outcome(currentRarity: number, currentStar: number, rarity: number): string
	if rarity > currentRarity then
		return "new"
	elseif rarity == currentRarity and currentStar < Config.Progress.MaxStars then
		return "star"
	end
	return "exp"
end

-- 확률 글자: 0.78 -> "78%", 0.0395 -> "3.95%", 0.0005 -> "0.05%"
function Gacha.percent(p: number): string
	local value = p * 100
	local text = string.format(if value >= 0.01 then "%.2f" else "%.3f", value)
	-- 끝의 0 과 소수점 지우기 (10.00 -> 10, 0.50 -> 0.5)
	while string.sub(text, -1) == "0" and string.find(text, ".", 1, true) ~= nil do
		text = string.sub(text, 1, -2)
	end
	if string.sub(text, -1) == "." then
		text = string.sub(text, 1, -2)
	end
	return text .. "%"
end

return Gacha
