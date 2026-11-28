--!strict
-- 부품 피버타임 규칙 (순수 계산, 수치는 Config.Fever).
-- 방향 미션이 판정될 때마다 꽂힌 부품 하나하나가 따로 피버를 뽑고, 다음 미션 판정까지 이어집니다.
-- 부품 주인이 그 미션에 성공했으면 더 잘 걸립니다. 피버 중인 부품 비율만큼 로켓이 빨라집니다.
-- 서버(Round)가 뽑고, 화면(FeverFx·PartsBoard·MyParts)은 Grid 폴더의 F<좌석> 속성을 보고 반짝임을 띄웁니다.

local Config = require(script.Parent.Config)

local F = Config.Fever

local Fever = {}

-- 시험 방식 Id 가 맞으면 그 Id, 아니면 기본 ("normal" | "all" | "off")
function Fever.mode(id: any): string
	for _, mode in ipairs(F.Modes) do
		if mode.Id == id then
			return mode.Id
		end
	end
	return F.Default
end

function Fever.modeName(id: any): string
	local mode = Fever.mode(id)
	for _, info in ipairs(F.Modes) do
		if info.Id == mode then
			return info.Name
		end
	end
	return mode
end

-- 부품 하나가 이번 미션 뒤 피버에 들어갈 확률. success = 부품 주인이 이번 미션에 성공함
function Fever.chance(success: boolean, mode: string?): number
	local m = Fever.mode(mode)
	if m == "off" then
		return 0
	elseif m == "all" then
		return 1
	end
	return if success then F.SuccessChance else F.FailChance
end

-- 꽂힌 부품 placed 개 중 fevered 개가 피버일 때 로켓 속도 배율 (1 = 피버 없음)
function Fever.multiplier(fevered: number, placed: number): number
	if placed <= 0 or fevered <= 0 then
		return 1
	end
	return 1 + F.SpeedBonus * math.clamp(fevered / placed, 0, 1)
end

-- 미션 팀 성공률이 늘 rate 일 때의 평균 속도 배율 (조립 화면 예상 거리용)
function Fever.expected(rate: number, mode: string?): number
	local r = math.clamp(rate, 0, 1)
	local share = r * Fever.chance(true, mode) + (1 - r) * Fever.chance(false, mode)
	return 1 + F.SpeedBonus * share
end

-- Grid/<종류> 폴더에서 그 좌석 부품의 피버 여부를 담는 속성 이름
function Fever.attribute(seat: number): string
	return "F" .. tostring(seat)
end

return Fever
