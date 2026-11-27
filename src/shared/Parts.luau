--!strict
-- 부품 파워 계산. 사람마다 종류별 1개씩 꽂습니다 (시너지 없음). 장비 묶음이 '각자 부품'이면 사람은 자기 부품의
-- 레어도·레벨(PartProgress), 봇은 묶음 장비. 다른 묶음은 시험용으로 모두 같은 장비.

local Config = require(script.Parent.Config)

local P = Config.Parts

local Parts = {}

-- 한 사람의 부품: 종류 Id -> 파워
export type Loadout = { [string]: number }

export type GearPreset = { Id: string, Name: string, Rarity: number, Level: number, Own: boolean? }

-- 부품 하나의 레어도·레벨 (종류 Id -> 이것)
export type PartLevels = { [string]: { rarity: number, level: number } }

-- 레벨 배율 (밸런스 스레드 11-27): 10^((레벨−1)/(만렙−1)). Lv1 ×1, Lv1,000 ×1.26, Lv5,000 ×3.16, Lv10,000 ×10
function Parts.levelMultiplier(level: number): number
	local max = Config.Progress.MaxLevel
	local l = math.clamp(math.floor(level), 1, max)
	return 10 ^ ((l - 1) / (max - 1))
end

-- 파워 = 레어도 기본값 × 레벨 배율
function Parts.power(rarity: number, level: number): number
	local r = math.clamp(math.floor(rarity), 1, #P.RarityPower)
	return P.RarityPower[r] * Parts.levelMultiplier(level)
end

function Parts.preset(id: string): GearPreset
	for _, preset in ipairs(Config.Gear.Presets) do
		if preset.Id == id then
			return preset
		end
	end
	return Config.Gear.Presets[1]
end

-- 장비 묶음 하나를 종류별 1개씩 든 사람의 부품
function Parts.loadout(presetId: string): Loadout
	local preset = Parts.preset(presetId)
	local power = Parts.power(preset.Rarity, preset.Level)
	local loadout: Loadout = {}
	for _, partType in ipairs(P.Types) do
		loadout[partType.Id] = power
	end
	return loadout
end

-- 자기 부품(종류별 레어도·레벨)을 종류별 1개씩 든 사람의 부품. 없는 종류는 일반 Lv1
function Parts.ownLoadout(parts: PartLevels): Loadout
	local loadout: Loadout = {}
	for _, partType in ipairs(P.Types) do
		local part = parts[partType.Id]
		loadout[partType.Id] = if part then Parts.power(part.rarity, part.level) else Parts.power(1, 1)
	end
	return loadout
end

function Parts.loadoutPower(loadout: Loadout): number
	local sum = 0
	for _, partType in ipairs(P.Types) do
		sum += loadout[partType.Id] or 0
	end
	return sum
end

-- 종류별 파워 합계 (FlightSim.Totals 와 같은 모양)
export type Totals = {
	engine: number,
	heat: number,
	fuel: number,
	sail: number,
	nav: number,
	core: number,
}

-- 한 종류의 합계. 센 순서로 줄 세워 k번째 부품은 1/k 만 더하고(인원이 늘어도 완만하게 오름),
-- 꽂은 부품 1개당 그 종류 합계 +1%.
local function sumType(loadouts: { Loadout }, typeId: string): number
	local powers: { number } = {}
	for _, loadout in ipairs(loadouts) do
		local power = loadout[typeId] or 0
		if power > 0 then
			table.insert(powers, power)
		end
	end
	table.sort(powers, function(a: number, b: number): boolean
		return a > b
	end)
	local sum = 0
	for k, power in ipairs(powers) do
		sum += power * (1 / k ^ P.RankExp)
	end
	return sum * (1 + P.SlotBonus * #powers)
end

-- 승무원 전원의 부품을 종류별로 합침
function Parts.totals(loadouts: { Loadout }): Totals
	return {
		engine = sumType(loadouts, "engine"),
		heat = sumType(loadouts, "heat"),
		fuel = sumType(loadouts, "fuel"),
		sail = sumType(loadouts, "sail"),
		nav = sumType(loadouts, "nav"),
		core = sumType(loadouts, "core"),
	}
end

return Parts
