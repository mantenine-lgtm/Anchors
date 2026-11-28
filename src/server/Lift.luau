-- 발사탑 엘리베이터: 판을 기다리는 동안(참여 확인 단계) 광장과 탑승 팔(TowerArm) 사이를 빠르게 오르내립니다.
-- 플레이어가 탑승 팔까지 올라가 로켓 바로 옆에서 볼 수 있게 하는 것입니다.
--  · 모양은 LaunchPad.luau(GPT)가 만듭니다: 모델 LiftCar(기준 파트 LiftFloor, 속성 Rise = 오르는 높이),
--    칸 안 버튼 LiftButton, 광장 쪽 부르기 버튼 LiftCallBottom, 탑승 팔 쪽 부르기 버튼 LiftCallTop.
--  · World 가 칸(LiftCar)을 발사장 모델 밖(Rofly 바로 아래)으로 옮겨 둡니다. 클라이언트는 발사장 파트의 쉬는 자리를
--    기억했다가 비행 중에 옮기므로(Planet.luau), 움직이는 칸이 그 안에 있으면 서버가 올린 칸을 아래 자리에 그릴 수 있음.
--  · 버튼(ProximityPrompt)은 여기서 붙입니다. 누르면 칸 바닥 위에 있는 사람을 태우고 RideSeconds 동안 움직입니다.
--    타는 동안은 캐릭터를 고정(Anchored)하고 칸과 함께 옮겼다가, 도착하면 풀어 줍니다 (고정 없이 움직이는 바닥은
--    캐릭터를 실어 나르지 못함).
--  · 참여 확인이 끝나면(조립 단계) 바로 멈추고 칸을 아래로 돌려놓습니다. 타고 있던 사람은 Seating 이 선실로 옮깁니다.
--  · 비행·정산 동안은 발사장이 멀어지는데 칸은 함께 움직이지 않으므로 숨깁니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Lift = {}

local L = Config.Lift
local OPEN_PHASE = "Join" -- 엘리베이터가 도는 단계 (모두 광장에서 기다릴 때)
local HIDDEN_PHASES = { Flight = true, Results = true } -- 발사장이 멀어지는 단계

type Rider = { player: Player, character: Model, root: BasePart, offset: CFrame }
type Saved = { transparency: number, collide: boolean, query: boolean }

local car: Model? = nil
local floor: BasePart? = nil
local state: Instance? = nil
local bottomPivot = CFrame.new() -- 아래 정류장에서 칸의 기준 자리
local rise = 0 -- 위 정류장까지 오르는 높이
local height = 0 -- 지금 칸이 아래 정류장에서 올라가 있는 높이
local atTop = false
local moving = false
local hidden = false
local ride = 0 -- 움직임 번호. 멈출 때 올려서 하던 움직임(Heartbeat 연결)을 끝냄
local riders: { Rider } = {}
local saved: { [Instance]: Saved } = {}
local ridePrompt: ProximityPrompt? = nil
local callBottom: ProximityPrompt? = nil
local callTop: ProximityPrompt? = nil

local function phase(): string
	local current = state and state:GetAttribute("Phase")
	return if typeof(current) == "string" then current else ""
end

-- 광장에서 기다리는 사람만 탐 (판에 탄 승무원·관전자는 Seating 이 맡음)
local function isLobby(player: Player): boolean
	local role = player:GetAttribute("Role")
	return role == nil or role == "Lobby"
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function refreshPrompts()
	local open = car ~= nil and not hidden and not moving and phase() == OPEN_PHASE
	if ridePrompt then
		ridePrompt.Enabled = open
		ridePrompt.ActionText = if atTop then "내려가기" else "올라가기"
	end
	if callBottom then
		callBottom.Enabled = open and atTop
	end
	if callTop then
		callTop.Enabled = open and not atTop
	end
end

-- 아직 이 엘리베이터가 붙잡고 있는 사람인지 (나갔거나, 캐릭터가 바뀌었거나, 판에 타서 Seating 이 옮겼으면 손대지 않음)
local function holding(rider: Rider): boolean
	return rider.player.Parent == Players
		and rider.player.Character == rider.character
		and rider.root.Parent ~= nil
		and rider.root.Anchored
		and isLobby(rider.player)
end

-- 칸 바닥 위(발자국 안, 바닥 위 RiderHeight 안)에 캐릭터 중심이 있는 사람
local function collectRiders(): { Rider }
	local list: { Rider } = {}
	local base = floor :: BasePart
	local half = base.Size / 2
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:IsDescendantOf(Workspace) and isLobby(player) then
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and not root.Anchored and humanoid and humanoid.Health > 0 then
				local p = base.CFrame:PointToObjectSpace(root.Position)
				if math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= half.Y - 1 and p.Y <= half.Y + L.RiderHeight then
					table.insert(list, {
						player = player,
						character = character,
						root = root,
						offset = base.CFrame:ToObjectSpace(character:GetPivot()),
					})
				end
			end
		end
	end
	return list
end

local function release(rider: Rider)
	if holding(rider) then
		rider.root.Anchored = false
		rider.root.AssemblyLinearVelocity = Vector3.zero
		rider.root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- 칸을 아래 정류장에서 at 만큼 올린 자리에 두고, 탄 사람을 칸 바닥에 대해 같은 자리로 옮김
local function place(at: number)
	height = at
	local model = car :: Model
	model:PivotTo(bottomPivot + Vector3.new(0, at, 0))
	local floorCFrame = (floor :: BasePart).CFrame
	for _, rider in ipairs(riders) do
		if holding(rider) then
			rider.character:PivotTo(floorCFrame * rider.offset)
		end
	end
end

local function go(toTop: boolean)
	if car == nil or moving or hidden or atTop == toTop or phase() ~= OPEN_PHASE then
		return
	end
	moving = true
	ride += 1
	local myRide = ride
	refreshPrompts()
	riders = collectRiders()
	for _, rider in ipairs(riders) do
		rider.root.Anchored = true
		rider.root.AssemblyLinearVelocity = Vector3.zero
		rider.root.AssemblyAngularVelocity = Vector3.zero
	end
	local from = height
	local to = if toTop then rise else 0
	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if ride ~= myRide then
			if connection then
				connection:Disconnect()
			end
			return
		end
		elapsed += dt
		local t = math.min(elapsed / L.RideSeconds, 1)
		place(from + (to - from) * smoothstep(t))
		if t >= 1 then
			if connection then
				connection:Disconnect()
			end
			atTop = toTop
			moving = false
			for _, rider in ipairs(riders) do
				release(rider)
			end
			riders = {}
			refreshPrompts()
		end
	end)
end

-- 하던 움직임을 멈추고 칸을 아래 정류장에 둠 (광장에 아무도 없을 때: 조립 단계부터)
local function park()
	ride += 1
	moving = false
	for _, rider in ipairs(riders) do
		release(rider)
	end
	riders = {}
	if height ~= 0 then
		place(0)
	end
	atTop = false
end

local function setHidden(hide: boolean)
	if hide == hidden or car == nil then
		return
	end
	hidden = hide
	for _, item in ipairs((car :: Model):GetDescendants()) do
		if item:IsA("BasePart") then
			if hide then
				saved[item] = { transparency = item.Transparency, collide = item.CanCollide, query = item.CanQuery }
				item.Transparency = 1
				item.CanCollide = false
				item.CanQuery = false
			else
				local before = saved[item]
				if before then
					item.Transparency = before.transparency
					item.CanCollide = before.collide
					item.CanQuery = before.query
				end
			end
		elseif item:IsA("Decal") or item:IsA("Texture") then
			if hide then
				saved[item] = { transparency = item.Transparency, collide = false, query = false }
				item.Transparency = 1
			else
				local before = saved[item]
				if before then
					item.Transparency = before.transparency
				end
			end
		end
	end
	if not hide then
		table.clear(saved)
	end
end

local function onPhase()
	local current = phase()
	if current ~= OPEN_PHASE then
		park()
	end
	setHidden(HIDDEN_PHASES[current] == true)
	refreshPrompts()
end

local function addPrompt(part: Instance?, actionText: string, onTriggered: () -> ()): ProximityPrompt?
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LiftPrompt"
	prompt.ObjectText = "엘리베이터"
	prompt.ActionText = actionText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = L.ButtonDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Triggered:Connect(function(player: Player)
		if isLobby(player) then
			onTriggered()
		end
	end)
	prompt.Parent = part
	return prompt
end

-- 서버 시작 때 한 번 (World.build·Round.start 뒤). 발사장에 엘리베이터가 없으면 아무것도 하지 않음
function Lift.start()
	local rofly = Workspace:FindFirstChild("Rofly")
	local found = rofly and rofly:FindFirstChild("LiftCar")
	if found == nil or not found:IsA("Model") then
		return
	end
	local primary = found.PrimaryPart
	local riseValue = found:GetAttribute("Rise")
	if primary == nil or typeof(riseValue) ~= "number" or riseValue <= 0 then
		warn("[ROFLY] 엘리베이터 칸에 기준 파트(LiftFloor)나 Rise 속성이 없어 엘리베이터를 끕니다")
		return
	end
	car = found
	floor = primary
	bottomPivot = found:GetPivot()
	rise = riseValue
	local pad = rofly and rofly:FindFirstChild("Pad")
	ridePrompt = addPrompt(found:FindFirstChild("LiftButton", true), "올라가기", function()
		go(not atTop)
	end)
	callBottom = addPrompt(pad and pad:FindFirstChild("LiftCallBottom", true), "부르기", function()
		go(false)
	end)
	callTop = addPrompt(pad and pad:FindFirstChild("LiftCallTop", true), "부르기", function()
		go(true)
	end)
	state = ReplicatedStorage:WaitForChild(Net.StateName, 10)
	if state then
		state:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	end
	onPhase()
end

return Lift
