--!strict
-- 부품 파워 계산. 데모 1은 모두 같은 장비 묶음을 종류별 1개씩 꽂습니다(그리드·시너지 없음).

local Config = require(script.Parent.Config)

local P = Config.Parts

local Parts = {}

-- 한 사람의 부품: 종류 Id -> 파워
export type Loadout = { [string]: number }

export type GearPreset = { Id: string, Name: string, Rarity: number, Level: number }

function Parts.power(rarity: number, level: number): number
	local r = math.clamp(rarity, 1, #P.RarityPower)
	local l = math.clamp(level, 1, #P.LevelMultiplier)
	return P.RarityPower[r] * P.LevelMultiplier[l]
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
