-- 머리 뒤 희귀도 구 (Nick 11-28): 캐릭터마다 머리 뒤에 장착 부품 6종의 희귀도 색으로 빛나는 작은 구 6개를 둥글게 띄웁니다.
-- 다른 사람이 그 캐릭터의 부품 희귀도를 볼 수 있게 (색만. 이름·레벨 같은 다른 부품 정보는 없음). 수치는 Config.Halo.
--  · 사람: 장비 묶음이 '각자 부품'이면 자기 부품(PartProgress.parts)의 희귀도, 시험용 묶음이면 그 묶음 희귀도
--  · 봇: 묶음 희귀도 (봇이 꽂는 장비와 같음. '각자 부품'이면 일반)
--  · 관전자(유령): 몸과 같은 투명도
--  · 구 자리는 종류 순서대로 고정이라, 자리만 보고도 어느 종류인지 알 수 있습니다 (뒤에서 볼 때 엔진부터 시계 방향).
-- 서버가 만들어 머리에 붙이므로 모두에게 복제되고 캐릭터와 함께 움직입니다(구는 Massless, 충돌·조회·그림자 없음).
-- 서버가 Config.Halo.Interval 초마다 희귀도를 다시 봐서 바뀐 구만 색을 바꿉니다. 그래서 뽑기 등 어떤 길로 희귀도가 바뀌어도,
-- 캐릭터가 새로 생기거나(판 끝 교체·리스폰) 아바타 머리가 바뀌어도 따로 알려 줄 필요가 없습니다.
-- 폰 사양: 캐릭터마다 파트 6개 + Weld 6개. 빛(PointLight)·파티클·그림자 없음, Neon 재질로만 빛나 보이게.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Parts = require(Shared:WaitForChild("Parts"))

local PartProgress = require(script.Parent.PartProgress)
local World = require(script.Parent.World)

local RarityHalo = {}

RarityHalo.FolderName = "RarityHalo"

local H = Config.Halo
local TYPES = Config.Parts.Types
local COLORS = Config.Parts.RarityColors

-- 캐릭터(또는 봇 모델) 하나의 구
type Halo = {
	head: BasePart,
	folder: Folder,
	orbs: { BasePart },
	rarities: { number },
	ghost: boolean,
}

local halos: { [Model]: Halo } = {}
local started = false

local function rarityIndex(rarity: any): number
	local r = if type(rarity) == "number" and rarity == rarity then math.floor(rarity) else 1
	return math.clamp(r, 1, #COLORS)
end

function RarityHalo.color(rarity: number): Color3
	return COLORS[rarityIndex(rarity)]
end

-- 머리 크기에 맞춘 배율 (기준 Config.Halo.HeadSize)
local function headScale(head: BasePart): number
	return math.clamp(head.Size.Y / H.HeadSize, 0.75, 1.6)
end

-- index 번째 종류 구의 자리 (머리 기준). 뒤에서 볼 때 오른쪽(+X) = 0도, 위 = 90도, 종류 순서대로 시계 방향
function RarityHalo.offset(index: number, scale: number): CFrame
	local angle = math.rad(H.StartAngle - (index - 1) * 360 / #TYPES)
	local x = math.cos(angle) * H.Radius
	local y = H.Lift + math.sin(angle) * H.Radius
	return CFrame.new(x * scale, y * scale, H.Behind * scale)
end

local function build(model: Model, head: BasePart, rarities: { number }, ghost: boolean): Halo
	local folder = Instance.new("Folder")
	folder.Name = RarityHalo.FolderName
	local scale = headScale(head)
	local orbs: { BasePart } = {}
	local kept: { number } = {}
	for index, info in ipairs(TYPES) do
		local rarity = rarityIndex(rarities[index])
		local offset = RarityHalo.offset(index, scale)
		local orb = Instance.new("Part")
		orb.Name = "Orb_" .. info.Id
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.one * (H.OrbSize * scale)
		orb.Material = Enum.Material.Neon
		orb.Color = COLORS[rarity]
		orb.Transparency = if ghost then H.GhostTransparency else 0
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CastShadow = false
		orb.Massless = true
		orb.Anchored = false
		orb.CFrame = head.CFrame * offset
		orb:SetAttribute("PartType", info.Id)
		orb:SetAttribute("Rarity", rarity)
		-- 머리에 붙임 (C0 를 직접 정해서, 붙이는 순간 머리가 어디 있든 자리가 같음)
		local weld = Instance.new("Weld")
		weld.Name = "HaloWeld"
		weld.Part0 = head
		weld.Part1 = orb
		weld.C0 = offset
		weld.C1 = CFrame.identity
		weld.Parent = orb
		orb.Parent = folder
		orbs[index] = orb
		kept[index] = rarity
	end
	folder.Parent = model
	return { head = head, folder = folder, orbs = orbs, rarities = kept, ghost = ghost }
end

-- 구가 있으면 색·투명도만 맞추고, 없거나 망가졌으면(머리가 바뀜·누가 지움) 새로 만듦
local function ensure(model: Model, head: BasePart, rarities: { number }, ghost: boolean)
	local halo = halos[model]
	if halo then
		local broken = halo.head ~= head or halo.folder.Parent ~= model
		if not broken then
			for _, orb in ipairs(halo.orbs) do
				if orb.Parent ~= halo.folder then
					broken = true
					break
				end
			end
		end
		if broken then
			halo.folder:Destroy()
			halos[model] = nil
			halo = nil
		end
	end
	if not halo then
		halos[model] = build(model, head, rarities, ghost)
		return
	end
	for index, orb in ipairs(halo.orbs) do
		local rarity = rarityIndex(rarities[index])
		if halo.rarities[index] ~= rarity then
			halo.rarities[index] = rarity
			orb.Color = COLORS[rarity]
			orb:SetAttribute("Rarity", rarity)
		end
	end
	if halo.ghost ~= ghost then
		halo.ghost = ghost
		for _, orb in ipairs(halo.orbs) do
			orb.Transparency = if ghost then H.GhostTransparency else 0
		end
	end
end

-- 지금 장비 묶음 (디버그 패널에서 바꾸면 RoundState 속성 OptGear 가 바뀜)
local function gearPreset(): Parts.GearPreset
	local state = ReplicatedStorage:FindFirstChild(Net.StateName)
	local id = if state then state:GetAttribute("OptGear") else nil
	return Parts.preset(if type(id) == "string" then id else Config.Gear.Default)
end

local function headOf(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

-- 종류 순서대로 희귀도 (out 에 채움)
local function playerRarities(player: Player, preset: Parts.GearPreset, out: { number })
	local own = if preset.Own then PartProgress.parts(player.UserId) else nil
	for index, info in ipairs(TYPES) do
		local part = if own then own[info.Id] else nil
		out[index] = if part then part.rarity else preset.Rarity
	end
end

local scratch: { number } = {}

-- 한 번 훑기: 모든 사람 캐릭터와 봇의 구를 맞추고, 없어진 캐릭터의 기록을 지움
function RarityHalo.step()
	local preset = gearPreset()
	local seen: { [Model]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		-- 아바타를 다 불러와 Workspace 에 들어온 뒤에만 (불러오는 중에는 머리가 바뀔 수 있음)
		if character and character:IsDescendantOf(Workspace) then
			local head = headOf(character)
			if head then
				playerRarities(player, preset, scratch)
				ensure(character, head, scratch, player:GetAttribute("Role") == "Ghost")
				seen[character] = true
			end
		end
	end
	local rocket = World.rocket()
	local bots = if rocket then rocket:FindFirstChild("Bots") else nil
	if bots then
		for index = 1, #TYPES do
			scratch[index] = preset.Rarity
		end
		for _, model in ipairs(bots:GetChildren()) do
			local head = if model:IsA("Model") then headOf(model) else nil
			if head then
				ensure(model :: Model, head, scratch, false)
				seen[model :: Model] = true
			end
		end
	end
	for model, halo in pairs(halos) do
		if not seen[model] then
			halo.folder:Destroy()
			halos[model] = nil
		end
	end
end

-- 지금 구를 띄운 캐릭터·봇 수 (검사·디버그용)
function RarityHalo.tracked(): number
	local count = 0
	for _ in pairs(halos) do
		count += 1
	end
	return count
end

function RarityHalo.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local warned = false
		while true do
			local ok, message = pcall(RarityHalo.step)
			if not ok and not warned then
				warned = true
				warn("[ROFLY] 희귀도 구 오류: " .. tostring(message))
			end
			task.wait(H.Interval)
		end
	end)
end

return RarityHalo
