-- 디버그 패널 명령 (데모 전용). Studio 에서 실행 중이거나 게임 주인만 쓸 수 있습니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Metrics = require(script.Parent.Metrics)
local Round = require(script.Parent.Round)

local DebugCommands = {}

function DebugCommands.isAllowed(player: Player): boolean
	if Config.Debug.AllowInStudio and RunService:IsStudio() then
		return true
	end
	if Config.Debug.AllowCreator and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

local function reply(player: Player, text: string)
	Net.event("Announce"):FireClient(player, "[디버그] " .. text)
end

local function handle(player: Player, command: any, value: any)
	if not DebugCommands.isAllowed(player) then
		return
	end
	if command == "Skip" then
		Round.skip()
		reply(player, "다음 단계로 넘어갑니다")
	elseif command == "Ticket" then
		local tickets = player:GetAttribute("Tickets")
		player:SetAttribute("Tickets", (if typeof(tickets) == "number" then tickets else 0) + 1)
		reply(player, "티켓 +1")
	elseif command == "Coins" then
		local coins = player:GetAttribute("Coins")
		player:SetAttribute("Coins", (if typeof(coins) == "number" then coins else 0) + Config.Debug.CoinGrant)
		reply(player, string.format("코인 +%d", Config.Debug.CoinGrant))
	elseif command == "BotFill" and typeof(value) == "number" and value == value then
		Round.setBotFill(value)
		reply(player, string.format("다음 판부터 승무원을 %d명까지 봇으로 채웁니다", math.clamp(math.floor(value), 1, 50)))
	elseif command == "BotSkill" and typeof(value) == "string" then
		Round.setBotSkill(value)
		reply(player, "봇 실력을 바꿨습니다 (다음 미션부터)")
	elseif command == "Gear" and typeof(value) == "string" then
		Round.setGear(value)
		reply(player, "다음 판부터 전원 장비가 바뀝니다")
	elseif command == "BotRescue" then
		if Round.botUseRescue() then
			reply(player, "봇이 구원 연료를 썼습니다")
		else
			reply(player, "지금은 쓸 수 없습니다 (위기 구간에서 한 비행에 한 번)")
		end
	elseif command == "Crisis" then
		if Round.forceCrisis() then
			reply(player, "위기 구간 직전으로 건너뜁니다")
		else
			reply(player, "비행 중에만 쓸 수 있습니다")
		end
	elseif command == "Planet" then
		reply(player, "행성을 바꿨습니다: " .. Round.nextPlanet())
	elseif command == "Metrics" then
		Metrics.print()
		reply(player, Metrics.summary())
	end
end

function DebugCommands.init()
	local function mark(player: Player)
		player:SetAttribute("Debug", DebugCommands.isAllowed(player))
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in ipairs(Players:GetPlayers()) do
		mark(player)
	end
	Net.event("Debug").OnServerEvent:Connect(handle)
end

return DebugCommands
