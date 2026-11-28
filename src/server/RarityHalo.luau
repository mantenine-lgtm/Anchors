-- 희귀도 구 (Nick 11-28): 캐릭터마다 머리 둘레 위쪽 반원에 장착 부품 6종의 희귀도 색으로 빛나는 작은 구 6개를 띄웁니다.
-- 다른 사람이 그 캐릭터의 부품 희귀도를 볼 수 있게 (색만. 이름·레벨 같은 다른 부품 정보는 없음). 수치는 Config.Halo.
--  · 자리: 머리 위로 둥근 반원(무지개 모양)이라 앞에서도 6개가 다 보임 (Nick 11-28: 고리 대신). 앞에서 볼 때 왼쪽 엔진부터
--    종류 순서. 자리가 고정이라 자리만 보고도 어느 종류인지 알 수 있습니다
--  · 등급이 높을수록 화려하게 (Config.Halo.Looks): 일반은 작은 구만, 희귀는 은은한 글로우, 영웅은 큰 글로우 + 맥박,
--    전설은 더 큰 글로우 + 일렁이는 ForceField 고리 + 빠른 맥박 + 반짝이. 맥박·반짝이는 각자 화면(client/HaloFx)이 한도 안에서 붙임
--  · 사람: 장비 묶음이 '각자 부품'이면 자기 부품(PartProgress.parts)의 희귀도, 시험용 묶음이면 그 묶음 희귀도
--  · 봇: 묶음 희귀도 (봇이 꽂는 장비와 같음. '각자 부품'이면 일반)
--  · 관전자(유령): 몸과 같은 투명도 (글로우도 같은 비율로 옅게)
-- 서버가 만들어 머리에 붙이므로 모두에게 복제되고 캐릭터와 함께 움직입니다(Massless, 충돌·조회·그림자 없음).
-- 서버가 Config.Halo.Interval 초마다 희귀도를 다시 봐서 바뀐 구만 새로 만듭니다. 그래서 뽑기 등 어떤 길로 희귀도가 바뀌어도,
-- 캐릭터가 새로 생기거나(판 끝 교체·리스폰) 아바타 머리가 바뀌어도 따로 알려 줄 필요가 없습니다.
-- 폰 사양: 캐릭터마다 알맹이 6개 + 희귀 이상만 글로우 껍질 하나씩 + 전설만 고리 하나씩 (파트 6~18개, 전설은 드묾),
-- 파트마다 Weld 하나. 빛(PointLight)·파티클은 서버에서 만들지 않음 (Neon·ForceField 재질로만 빛나 보이게).

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
RarityHalo.GlowName = "Glow" -- 알맹이(Orb_<종류>) 안에 든 글로우 껍질 이름 (Neon)
RarityHalo.RingName = "Ring" -- 알맹이 안에 든 바깥 고리 껍질 이름 (ForceField, 전설)

local H = Config.Halo
local TYPES = Config.Parts.Types
local WHITE = Color3.new(1, 1, 1)

-- 희귀도 색 (Config 에는 0~255 RGB 숫자로 있음)
local COLORS: { Color3 } = {}
for index, rgb in ipairs(Config.Parts.RarityColors) do
	COLORS[index] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

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

-- 그 등급의 모습 (Config.Halo.Looks)
function RarityHalo.look(rarity: number): any
	return H.Looks[rarityIndex(rarity)] or H.Looks[1]
end

-- 머리 크기에 맞춘 배율 (기준 Config.Halo.HeadSize)
local function headScale(head: BasePart): number
	return math.clamp(head.Size.Y / H.HeadSize, 0.75, 1.6)
end

-- index 번째 종류 구의 자리 (머리 기준). 머리 위 반원: 앞에서 볼 때 왼쪽(캐릭터의 오른쪽 +X) = 0도, 위 = 90도.
-- 종류 순서대로 ArcFrom 에서 ArcTo 까지 같은 간격
function RarityHalo.offset(index: number, scale: number): CFrame
	local count = #TYPES
	local t = if count > 1 then (index - 1) / (count - 1) else 0.5
	local angle = math.rad(H.ArcFrom + (H.ArcTo - H.ArcFrom) * t)
	local x = math.cos(angle) * H.Radius
	local y = H.Lift + math.sin(angle) * H.Radius
	return CFrame.new(x * scale, y * scale, H.Behind * scale)
end

-- 관전자면 몸과 같은 비율로 옅게 (불투명한 알맹이는 GhostTransparency 가 됨)
function RarityHalo.fade(transparency: number, ghost: boolean): number
	if not ghost then
		return transparency
	end
	return 1 - (1 - transparency) * (1 - H.GhostTransparency)
end

local function ball(name: string, size: number, color: Color3, material: Enum.Material, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * size
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	return part
end

-- part1 을 part0 에 붙임 (C0 를 직접 정해서, 붙이는 순간 어디 있든 자리가 같음)
local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Name = "HaloWeld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.C1 = CFrame.identity
	w.Parent = part1
end

-- 종류 하나의 구: 머리에 붙은 알맹이(Orb_<종류>, Neon) + 희귀 이상이면 알맹이 안에 글로우 껍질(Glow, Neon)
-- + 전설이면 바깥 고리 껍질(Ring, ForceField). 껍질은 알맹이에 붙어 같이 움직임
local function buildOrb(halo: Halo, index: number, rarity: number): BasePart
	local info = TYPES[index]
	local look = RarityHalo.look(rarity)
	local scale = headScale(halo.head)
	local offset = RarityHalo.offset(index, scale)
	local color = COLORS[rarity]
	local size = H.OrbSize * (look.Core or 1) * scale
	local orb = ball("Orb_" .. info.Id, size, color:Lerp(WHITE, look.CoreWhite or 0), Enum.Material.Neon, RarityHalo.fade(0, halo.ghost))
	orb.CFrame = halo.head.CFrame * offset
	orb:SetAttribute("PartType", info.Id)
	orb:SetAttribute("Rarity", rarity)
	orb:SetAttribute("Ghost", halo.ghost)
	weld(halo.head, orb, offset)
	if look.Glow then
		local transparency = RarityHalo.fade(look.GlowTransparency or 0.7, halo.ghost)
		local glow = ball(RarityHalo.GlowName, size * look.Glow, color, Enum.Material.Neon, transparency)
		glow.CFrame = orb.CFrame
		glow:SetAttribute("BaseTransparency", transparency) -- 각자 화면의 맥박이 이 값에서 시작해 돌아옴
		weld(orb, glow, CFrame.identity)
		glow.Parent = orb
	end
	if look.Ring then
		local ring = ball(RarityHalo.RingName, size * look.Ring, color, Enum.Material.ForceField, RarityHalo.fade(0, halo.ghost))
		ring.CFrame = orb.CFrame
		weld(orb, ring, CFrame.identity)
		ring.Parent = orb
	end
	orb.Parent = halo.folder
	return orb
end

local function build(model: Model, head: BasePart, rarities: { number }, ghost: boolean): Halo
	local folder = Instance.new("Folder")
	folder.Name = RarityHalo.FolderName
	local halo: Halo = { head = head, folder = folder, orbs = {}, rarities = {}, ghost = ghost }
	for index = 1, #TYPES do
		local rarity = rarityIndex(rarities[index])
		halo.rarities[index] = rarity
		halo.orbs[index] = buildOrb(halo, index, rarity)
	end
	folder.Parent = model
	return halo
end

-- 구가 있으면 바뀐 구만 새로 만들고, 없거나 망가졌으면(머리가 바뀜·누가 지움) 또는 관전자가 되거나 풀리면 통째로 새로 만듦
local function ensure(model: Model, head: BasePart, rarities: { number }, ghost: boolean)
	local halo = halos[model]
	if halo then
		local broken = halo.head ~= head or halo.folder.Parent ~= model or halo.ghost ~= ghost
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
	-- 등급마다 껍질·크기가 달라서 색만 바꾸지 않고 그 구를 새로 만듦 (다른 구는 그대로)
	for index, orb in ipairs(halo.orbs) do
		local rarity = rarityIndex(rarities[index])
		if halo.rarities[index] ~= rarity then
			halo.rarities[index] = rarity
			orb:Destroy()
			halo.orbs[index] = buildOrb(halo, index, rarity)
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
