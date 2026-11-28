-- 부품 뽑기 (Nick 11-28 "부품 뽑기도 추가", "발사 전에 뽑을 수 있게"). 규칙과 수치는 Config.Gacha, 뽑기 계산은 Gacha.luau.
-- 'GachaPull' (종류 Id, 10회인지) 를 받으면: 뽑을 수 있는 단계(탑승 대기·조립·정산)인지, 코인이 되는지 보고
-- (값은 그 사람의 최고 기록 BestKm 으로 정함, Gacha.price)
-- 코인을 빼고 결과를 하나씩 PartProgress.applyPull 로 그 종류 부품에 넣은 뒤, 그 사람에게 'GachaResult' 와 바뀐 내 부품을 보냅니다.
-- 전설(Config.Gacha.AnnounceRarity 이상)이 나오면 모두에게 'GachaNews' (다른 사람 화면에 축하 버튼). 축하를 누르면 누른 사람이
-- CheerCoins 를 받고, 모두에게 'GachaCheered' 로 축하 수를 알립니다 (감사 버튼과 같은 방식).
-- 판의 파워는 조립이 시작할 때의 부품으로 정해지므로(Round.newMember), 뽑은 부품은 다음 조립부터 로켓에 들어갑니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Gacha = require(Shared:WaitForChild("Gacha"))
local Net = require(Shared:WaitForChild("Net"))

local PartProgress = require(script.Parent.PartProgress)

local GachaService = {}

local G = Config.Gacha
local KEEP_NEWS = 8 -- 축하를 받아 주는 최근 알림 수

type News = { id: number, userId: number, untilAt: number, cheered: { [number]: boolean }, count: number }

local rng = Random.new()
local state: Instance? = nil
local lastPull: { [Player]: number } = {}
local news: { News } = {}
local newsSerial = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function coins(player: Player): number
	local value = player:GetAttribute("Coins")
	return if typeof(value) == "number" and value == value then value else 0
end

local function phase(): string
	local found = state or ReplicatedStorage:FindFirstChild(Net.StateName)
	state = found
	local value = if found then found:GetAttribute("Phase") else nil
	return if type(value) == "string" then value else ""
end

local function refuse(player: Player, reason: string)
	Net.event("GachaResult"):FireClient(player, { ok = false, reason = reason })
end

local function announce(player: Player, typeId: string, best: PartProgress.PullResult)
	newsSerial += 1
	local item: News = {
		id = newsSerial,
		userId = player.UserId,
		untilAt = now() + G.CheerSeconds,
		cheered = {},
		count = 0,
	}
	table.insert(news, item)
	while #news > KEEP_NEWS do
		table.remove(news, 1)
	end
	Net.event("GachaNews"):FireAllClients({
		id = item.id,
		userId = player.UserId,
		name = player.DisplayName,
		typeId = typeId,
		variantId = best.id,
		rarity = best.rarity,
		seconds = G.CheerSeconds,
	})
end

-- 뽑기 한 번 (1회 또는 10회)
local function pull(player: Player, typeId: any, ten: any)
	local t = now()
	if t - (lastPull[player] or -math.huge) < G.RequestGap then
		return -- 너무 빨리 연달아 옴: 무시 (화면은 결과를 받을 때까지 버튼을 막음)
	end
	lastPull[player] = t
	if type(typeId) ~= "string" or not Gacha.isType(typeId) then
		refuse(player, "뽑을 부품 종류를 골라 주세요")
		return
	end
	if not Gacha.open(phase()) then
		refuse(player, "카운트다운·비행 중에는 뽑을 수 없어요")
		return
	end
	local isTen = ten == true
	local record = player:GetAttribute("BestKm")
	local price = Gacha.price(if typeof(record) == "number" then record else 0, isTen)
	local wallet = coins(player)
	if wallet < price then
		refuse(player, string.format("코인이 모자라요 (%s 코인 더 필요)", Fmt.comma(price - wallet)))
		return
	end
	player:SetAttribute("Coins", wallet - price)
	local results = {}
	local ups: { [string]: number } = {}
	local best: PartProgress.PullResult? = nil
	for _ = 1, Gacha.count(isTen) do
		local variant = Gacha.roll(typeId, rng)
		local result = if variant then PartProgress.applyPull(player.UserId, typeId, variant.Id) else nil
		if result then
			table.insert(results, result)
			if result.ups > 0 then
				ups[typeId] = (ups[typeId] or 0) + result.ups
			end
			if best == nil or result.rarity > (best :: PartProgress.PullResult).rarity then
				best = result
			end
		end
	end
	local part = PartProgress.get(player.UserId, typeId)
	Net.event("GachaResult"):FireClient(player, {
		ok = true,
		typeId = typeId,
		ten = isTen,
		price = price,
		coins = coins(player),
		results = results,
		rarity = if part then part.rarity else 1,
		star = if part then part.star else 1,
		level = if part then part.level else 1,
	})
	PartProgress.send(player, ups, true)
	if best and best.rarity >= G.AnnounceRarity then
		announce(player, typeId, best)
	end
end

local function cheer(player: Player, id: any)
	if type(id) ~= "number" then
		return
	end
	for _, item in ipairs(news) do
		if item.id == id then
			if now() > item.untilAt + G.CheerGrace or item.userId == player.UserId or item.cheered[player.UserId] then
				return
			end
			item.cheered[player.UserId] = true
			item.count += 1
			player:SetAttribute("Coins", coins(player) + G.CheerCoins)
			Net.event("GachaCheered"):FireAllClients({ id = item.id, count = item.count, fromUserId = player.UserId })
			return
		end
	end
end

function GachaService.init()
	Net.event("GachaPull").OnServerEvent:Connect(pull)
	Net.event("GachaCheer").OnServerEvent:Connect(cheer)
	Net.event("GachaLook").OnServerEvent:Connect(function(player: Player, typeId: any, variantId: any)
		if type(typeId) == "string" and Catalog.get(variantId) ~= nil and PartProgress.setLook(player.UserId, typeId, variantId) then
			PartProgress.send(player, nil, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastPull[player] = nil
	end)
end

return GachaService
