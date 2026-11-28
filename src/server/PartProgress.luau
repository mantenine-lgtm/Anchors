-- 사람마다 부품 6종(종류별 1개)의 레어도·레벨·경험치·돌파(★)·모양 (만렙 Config.Progress.MaxLevel). 시작은 6종 모두 일반 Lv1 ★1,
-- 모양은 그 종류의 첫 일반 부품(Catalog.starter). 뽑은 부품의 이름·모양은 종류마다 도감(owned)에 모입니다.
-- 서버가 켜져 있는 동안 UserId 로 기억해서 나갔다 들어와도 이어집니다. 저장(DataStore)은 아직 없습니다(코인과 같음).
-- 비행 중 1초마다 탄 사람의 부품 6개가 경험치를 얻습니다 (Round 가 Config.Progress.SendInterval 마다 몰아서 줌).
-- 레벨은 돌파 한도(Leveling.cap)에서 멈추고 남는 경험치는 쌓아 둡니다. 뽑기(GachaService → applyPull)로 돌파하면 한꺼번에 오름.
-- 그 사람 화면에만 'PartProgress' 신호로 알립니다:
--   { lv = { 종류 = 레벨 }, exp = { 종류 = 지금 레벨에서 쌓인 경험치 }, rarity = { 종류 = 레어도 }, ups = { 종류 = 이번에 오른 레벨 수 },
--     star = { 종류 = 돌파 ★ }, cap = { 종류 = 만렙 한도 }, look = { 종류 = 모양 Id },
--     owned = { 종류 = { 모은 부품 Id, ... } } (full 일 때만: 처음 요청·뽑기 뒤. 비행 중 0.25초마다 보내는 값에는 없음) }
-- 장비 묶음이 '각자 부품'이면 조립이 시작할 때의 레어도·레벨이 그 판의 파워가 됩니다 (Round.newMember → Parts.ownLoadout).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Leveling = require(Shared:WaitForChild("Leveling"))
local Net = require(Shared:WaitForChild("Net"))

local PartProgress = {}

export type Part = {
	rarity: number,
	level: number,
	exp: number,
	star: number,
	look: string, -- 끼고 있는 모양 (Catalog Id, 레어도가 같은 것만)
	owned: { [string]: boolean }, -- 모은 부품 (도감)
}
type Record = { [string]: Part }

-- 뽑기 결과 하나가 부품에 한 일
export type PullResult = {
	id: string, -- 뽑은 부품 (Catalog Id)
	rarity: number,
	kind: string, -- "new" 더 높은 레어도로 바꿔 낌 / "star" 돌파 ★+1 / "exp" 경험치로 바뀜
	isNew: boolean, -- 도감에 처음 들어옴
	star: number, -- 결과 뒤 ★
	level: number, -- 결과 뒤 레벨
	exp: number, -- kind 가 "exp" 일 때 받은 경험치
	ups: number, -- 이 결과로 오른 레벨 수
}

local records: { [number]: Record } = {}

local function newPart(typeId: string, rarity: number, look: string?): Part
	local starter = Catalog.ofRarity(typeId, rarity)[1]
	local id = look or (if starter then starter.Id else "")
	return { rarity = rarity, level = 1, exp = 0, star = 1, look = id, owned = { [id] = true } }
end

local function record(userId: number): Record
	local found = records[userId]
	if found then
		return found
	end
	local new: Record = {}
	for _, info in ipairs(Config.Parts.Types) do
		new[info.Id] = newPart(info.Id, 1, nil)
	end
	records[userId] = new
	return new
end

function PartProgress.get(userId: number, typeId: string): Part?
	return record(userId)[typeId]
end

-- 경험치 gain 을 부품 하나에 (돌파 한도에서 멈추고 나머지는 쌓아 둠). 오른 레벨 수
local function gainExp(part: Part, gain: number): number
	local level, exp, up = Leveling.add(part.level, part.exp, gain, part.rarity, Leveling.cap(part.star))
	part.level = level
	part.exp = exp
	return up
end

-- 부품 6개에 경험치 gain 씩. 레벨이 오른 종류와 오른 수를 돌려줌
function PartProgress.award(userId: number, gain: number): { [string]: number }
	local ups: { [string]: number } = {}
	if not (gain > 0) then -- NaN 도 막음
		return ups
	end
	for typeId, part in pairs(record(userId)) do
		local up = gainExp(part, gain)
		if up > 0 then
			ups[typeId] = up
		end
	end
	return ups
end

-- 지금 부품 6개의 레어도·레벨 사본 (종류 Id -> { rarity, level, star, look }). 판에 쓰는 동안 경험치가 올라도 바뀌지 않음
function PartProgress.parts(userId: number): { [string]: { rarity: number, level: number, star: number, look: string } }
	local out = {}
	for typeId, part in pairs(record(userId)) do
		out[typeId] = { rarity = part.rarity, level = part.level, star = part.star, look = part.look }
	end
	return out
end

-- 뽑기 결과 하나를 그 종류 부품에 반영 (규칙은 Config.Gacha 설명). variantId 는 Catalog 에 있는 그 종류의 부품
function PartProgress.applyPull(userId: number, typeId: string, variantId: string): PullResult?
	local variant = Catalog.get(variantId)
	local part = record(userId)[typeId]
	if variant == nil or part == nil or variant.Type ~= typeId then
		return nil
	end
	local isNew = part.owned[variant.Id] ~= true
	local result: PullResult = {
		id = variant.Id,
		rarity = variant.Rarity,
		kind = "exp",
		isNew = isNew,
		star = part.star,
		level = part.level,
		exp = 0,
		ups = 0,
	}
	if variant.Rarity > part.rarity then
		-- 더 센 부품: 바꿔 낌 (모은 도감은 그대로)
		local owned = part.owned
		local fresh = newPart(typeId, variant.Rarity, variant.Id)
		for id in pairs(owned) do
			fresh.owned[id] = true
		end
		record(userId)[typeId] = fresh
		part = fresh
		result.kind = "new"
	elseif variant.Rarity == part.rarity and part.star < Leveling.MaxStars then
		-- 돌파: 한도가 오르고 쌓아 둔 경험치가 레벨로 바뀜
		part.star += 1
		part.owned[variant.Id] = true
		result.kind = "star"
		result.ups = gainExp(part, 0)
	else
		local gain = Config.Gacha.DupeExp[math.clamp(variant.Rarity, 1, #Config.Gacha.DupeExp)]
		part.owned[variant.Id] = true
		result.exp = gain
		result.ups = gainExp(part, gain)
	end
	result.star = part.star
	result.level = part.level
	return result
end

-- 도감에서 모양 바꾸기: 모은 부품 중 지금 부품과 레어도가 같은 것만. 바뀌었으면 true
function PartProgress.setLook(userId: number, typeId: string, variantId: any): boolean
	local part = record(userId)[typeId]
	local variant = Catalog.get(variantId)
	if part == nil or variant == nil or variant.Type ~= typeId or variant.Rarity ~= part.rarity then
		return false
	end
	if part.owned[variant.Id] ~= true or part.look == variant.Id then
		return false
	end
	part.look = variant.Id
	return true
end

-- 디버그: 부품 6개를 levels 만큼 올림 (경험치로 줘서 비행 중 오를 때와 같은 길을 탐). 돌파 한도에 걸리면 ★도 그만큼 올림
function PartProgress.grantLevels(userId: number, levels: number): { [string]: number }
	local ups: { [string]: number } = {}
	for typeId, part in pairs(record(userId)) do
		local target = math.min(part.level + math.max(math.floor(levels), 0), Leveling.MaxLevel)
		while Leveling.cap(part.star) < target and part.star < Leveling.MaxStars do
			part.star += 1
		end
		-- +0.5: 쌓인 경험치에 소수점이 있으면 더하기 오차로 한 레벨 모자랄 수 있음 (필요량은 정수라 0.5 로 더 오르지는 않음)
		local gain = Leveling.toGain(part.level, part.exp, target - part.level, part.rarity) + 0.5
		local up = gainExp(part, gain)
		if up > 0 then
			ups[typeId] = up
		end
	end
	return ups
end

-- full: 도감(owned)까지 보냄
function PartProgress.payload(userId: number, ups: { [string]: number }?, full: boolean?): any
	local lv, exp, rarity, star, cap, look = {}, {}, {}, {}, {}, {}
	local owned: { [string]: { string } }? = if full then {} else nil
	for typeId, part in pairs(record(userId)) do
		lv[typeId] = part.level
		exp[typeId] = part.exp
		rarity[typeId] = part.rarity
		star[typeId] = part.star
		cap[typeId] = Leveling.cap(part.star)
		look[typeId] = part.look
		if owned then
			local ids = {}
			for _, variant in ipairs(Catalog.ofType(typeId)) do
				if part.owned[variant.Id] then
					table.insert(ids, variant.Id)
				end
			end
			owned[typeId] = ids
		end
	end
	return { lv = lv, exp = exp, rarity = rarity, ups = ups or {}, star = star, cap = cap, look = look, owned = owned }
end

function PartProgress.send(player: Player, ups: { [string]: number }?, full: boolean?)
	Net.event("PartProgress"):FireClient(player, PartProgress.payload(player.UserId, ups, full))
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
