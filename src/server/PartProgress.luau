-- 사람마다 부품 6종(종류별 1개)의 레어도·레벨·경험치 (만렙 Config.Progress.MaxLevel). 시작은 6종 모두 일반 Lv1.
-- 서버가 켜져 있는 동안 UserId 로 기억해서 나갔다 들어와도 이어집니다. 저장(DataStore)은 아직 없습니다(코인과 같음).
-- 비행 중 1초마다 탄 사람의 부품 6개가 경험치를 얻습니다 (Round 가 Config.Progress.SendInterval 마다 몰아서 줌).
-- 그 사람 화면에만 'PartProgress' 신호로 알립니다:
--   { lv = { 종류 = 레벨 }, exp = { 종류 = 지금 레벨에서 쌓인 경험치 }, rarity = { 종류 = 레어도 }, ups = { 종류 = 이번에 오른 레벨 수 } }
-- 장비 묶음이 '각자 부품'이면 조립이 시작할 때의 레어도·레벨이 그 판의 파워가 됩니다 (Round.newMember → Parts.ownLoadout).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Leveling = require(Shared:WaitForChild("Leveling"))
local Net = require(Shared:WaitForChild("Net"))

local PartProgress = {}

export type Part = { rarity: number, level: number, exp: number }
type Record = { [string]: Part }

local records: { [number]: Record } = {}

local function record(userId: number): Record
	local found = records[userId]
	if found then
		return found
	end
	local new: Record = {}
	for _, info in ipairs(Config.Parts.Types) do
		new[info.Id] = { rarity = 1, level = 1, exp = 0 }
	end
	records[userId] = new
	return new
end

function PartProgress.get(userId: number, typeId: string): Part?
	return record(userId)[typeId]
end

-- 부품 6개에 경험치 gain 씩. 레벨이 오른 종류와 오른 수를 돌려줌
function PartProgress.award(userId: number, gain: number): { [string]: number }
	local ups: { [string]: number } = {}
	if not (gain > 0) then -- NaN 도 막음
		return ups
	end
	for typeId, part in pairs(record(userId)) do
		local level, exp, up = Leveling.add(part.level, part.exp, gain, part.rarity)
		part.level = level
		part.exp = exp
		if up > 0 then
			ups[typeId] = up
		end
	end
	return ups
end

-- 지금 부품 6개의 레어도·레벨 사본 (종류 Id -> { rarity, level }). 판에 쓰는 동안 경험치가 올라도 바뀌지 않음
function PartProgress.parts(userId: number): { [string]: { rarity: number, level: number } }
	local out = {}
	for typeId, part in pairs(record(userId)) do
		out[typeId] = { rarity = part.rarity, level = part.level }
	end
	return out
end

-- 디버그: 부품 6개를 levels 만큼 올림 (경험치로 줘서 비행 중 오를 때와 같은 길을 탐)
function PartProgress.grantLevels(userId: number, levels: number): { [string]: number }
	local ups: { [string]: number } = {}
	for typeId, part in pairs(record(userId)) do
		local gain = Leveling.toGain(part.level, part.exp, levels, part.rarity)
		local level, exp, up = Leveling.add(part.level, part.exp, gain, part.rarity)
		part.level = level
		part.exp = exp
		if up > 0 then
			ups[typeId] = up
		end
	end
	return ups
end

function PartProgress.payload(userId: number, ups: { [string]: number }?): any
	local lv, exp, rarity = {}, {}, {}
	for typeId, part in pairs(record(userId)) do
		lv[typeId] = part.level
		exp[typeId] = part.exp
		rarity[typeId] = part.rarity
	end
	return { lv = lv, exp = exp, rarity = rarity, ups = ups or {} }
end

function PartProgress.send(player: Player, ups: { [string]: number }?)
	Net.event("PartProgress"):FireClient(player, PartProgress.payload(player.UserId, ups))
end

-- 검사·디버그용: 서버 기억을 지움
function PartProgress.reset(userId: number?)
	if userId then
		records[userId] = nil
	else
		table.clear(records)
	end
end

return PartProgress
