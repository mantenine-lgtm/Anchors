-- 판 동안 캐릭터를 선실에 둡니다.
--  · 승무원: 판이 시작하면 선실 바닥의 탑승 자리로 옮기고, 그 뒤로는 선실 안을 자유롭게 걸어다닙니다(의자 없음).
--    선실 밖으로 나가면(엔진이 새 캐릭터를 뒤늦게 리스폰 지점으로 옮긴 경우 등) 탑승 자리로 되돌립니다.
--  · 관전자(유령): 천장 가까이 정해진 자리에 고정(Anchored)하고 반투명하게. 둘러보기만 합니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cabin = require(Shared:WaitForChild("Cabin"))
local Config = require(Shared:WaitForChild("Config"))
local World = require(script.Parent.World)

local Seating = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local GUARD_INTERVAL = 0.5 -- 승무원이 선실 안에 있는지, 관전자가 제자리에 있는지 다시 보는 간격(초)
local CABIN_MARGIN = 2 -- 캐릭터 중심이 선실 벽·바닥에서 이보다 더 벗어나면 선실 밖으로 봄
local GHOST_REFRESH = 6 -- 유령의 투명 처리를 되풀이하는 횟수 (늦게 붙는 장신구 대비, 약 3초 동안)
local LOAD_STUCK = 60 -- 캐릭터가 생긴 뒤 이만큼(초) 지나도 Workspace 에 나타나지 않으면 불러오기가 멈춘 것으로 봄

-- 플레이어마다 지금 잡아 둔 캐릭터와 자리 ("Crew:8", "Ghost:1"). 같은 캐릭터를 같은 자리에 두 번 꾸미지 않으려고
-- 기억합니다. 자리를 지키는 반복(guard)은 이 기록(표) 자체를 들고 있다가, 기록이 바뀌거나 지워지면 멈춥니다.
-- 판이 끝날 때(releaseAll) 모두 지웁니다.
type Placement = { character: Model, key: string }
local placed: { [Player]: Placement } = {}

-- 플레이어마다 지금 캐릭터와 그 캐릭터가 생긴(CharacterAdded) 시각(게임이 돈 시간, time()). 멈춘 불러오기를 알아보는 데 씀
local addedAt: { [Player]: { character: Model, at: number } } = {}

local function isPlaced(player: Player, character: Model, key: string): boolean
	local entry = placed[player]
	return entry ~= nil and entry.character == character and entry.key == key
end

-- 캐릭터가 다 만들어질 때까지 잠깐 기다렸다가 중심 파트와 Humanoid 를 돌려줌
local function getParts(character: Model): (BasePart?, Humanoid?)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if rootPart and rootPart:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid") then
		return rootPart, humanoid
	end
	return nil, nil
end

-- 캐릭터를 cframe 에 고정 (관전자)
local function hold(character: Model, cframe: CFrame): Humanoid?
	local rootPart, humanoid = getParts(character)
	if not rootPart or not humanoid then
		return nil
	end
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	rootPart.Anchored = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(cframe)
	return humanoid
end

-- 캐릭터를 cframe 으로 옮기고 자유롭게 움직이게 함 (승무원)
local function free(character: Model, cframe: CFrame): Humanoid?
	local rootPart, humanoid = getParts(character)
	if not rootPart or not humanoid then
		return nil
	end
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	rootPart.Anchored = false
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(cframe)
	return humanoid
end

local function addCrown(character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or character:FindFirstChild("CaptainCrown") then
		return
	end
	local crown = Instance.new("Part")
	crown.Name = "CaptainCrown"
	crown.Size = Vector3.new(1.5, 0.6, 1.5)
	crown.Color = GOLD
	crown.Material = Enum.Material.Neon
	crown.CanCollide = false
	crown.CanQuery = false
	crown.Massless = true
	crown.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.4, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = crown
	weld.Parent = crown
	crown.Parent = character
end

local function makeGhostly(character: Model)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" then
			item.Transparency = math.max(item.Transparency, 0.65)
			item.CastShadow = false
		elseif item:IsA("Decal") then
			item.Transparency = math.max(item.Transparency, 0.65)
		end
	end
end

-- 엔진이 새 캐릭터를 다 만들어 리스폰 지점에 놓을 때까지 기다림.
-- CharacterAdded 는 캐릭터 불러오기의 "시작"에 불립니다. 엔진은 아바타를 다 불러온 뒤에야 캐릭터를
-- Workspace 에 넣고 리스폰 지점으로 옮기므로, 그 전에 자리를 잡으면 엔진이 발사장으로 다시 옮겨 버립니다.
local function waitUntilSpawned(player: Player, character: Model): boolean
	-- 아바타를 불러오는 데 걸리는 시간에는 정해진 한도가 없으므로, 캐릭터가 바뀌거나 플레이어가 나갈 때까지 기다림
	while not character:IsDescendantOf(Workspace) do
		if player.Character ~= character or player.Parent ~= Players then
			return false
		end
		task.wait()
	end
	task.wait(0.2) -- Workspace 에 들어온 직후에 엔진이 리스폰 지점으로 옮기므로 그 뒤에 움직임
	return player.Character == character and character:IsDescendantOf(Workspace)
end

-- 자리를 잡은 캐릭터를 그 자리가 풀릴 때(판이 끝나거나 캐릭터가 바뀔 때)까지 지켜봄.
-- 엔진이 새 캐릭터를 리스폰 지점으로 옮기는 때는 문서에 순서만 있고 시간은 없어서, 자리를 잡은 뒤에
-- 뒤늦게 발사장으로 옮겨질 수 있습니다. 그때나 다른 이유로
--  · 승무원이 선실 밖에 있으면 탑승 자리로 되돌립니다 (선실 안에서 걸어다니는 것은 그대로 둠)
--  · 관전자가 제자리를 벗어나면 다시 고정합니다
-- 자리 기록은 같은 표인지로 알아봅니다: 판이 끝나 기록이 지워진 뒤 같은 캐릭터가 같은 자리 이름으로 다시
-- 잡혀도(새 판의 탑승 자리 위치는 승무원 수에 따라 다를 수 있음) 지난 판의 반복은 멈춥니다.
local function guard(player: Player, entry: Placement, cframe: CFrame, ghost: boolean)
	local character = entry.character
	task.spawn(function()
		local checks = 0
		while true do
			task.wait(GUARD_INTERVAL)
			if player.Parent ~= Players or player.Character ~= character or placed[player] ~= entry then
				return
			end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if rootPart and rootPart:IsA("BasePart") and humanoid then
				if ghost then
					if not rootPart.Anchored or (rootPart.Position - cframe.Position).Magnitude > 2 then
						hold(character, cframe)
					end
				elseif rootPart.Anchored or not Cabin.contains(rootPart.Position, CABIN_MARGIN) then
					free(character, cframe)
				end
			end
			checks += 1
			if ghost and checks <= GHOST_REFRESH then
				makeGhostly(character) -- 늦게 붙은 장신구도 투명하게
			end
		end
	end)
end

-- 플레이어의 역할(속성 Role)에 맞게 지금 캐릭터를 배치. 캐릭터가 새로 생길 때마다 불립니다.
function Seating.apply(player: Player)
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return -- 아직 만들어지는 중이면, 다 만들어진 뒤 onCharacterAdded 가 다시 부름
	end
	local role = player:GetAttribute("Role")
	if role == "Crew" then
		-- 속성 Seat 는 이번 판의 승무원 번호 = 탑승 자리 번호 (조립 그리드·클로즈업도 이 번호로 사람을 알아봄)
		local spotIndex = player:GetAttribute("Seat")
		if typeof(spotIndex) ~= "number" or spotIndex < 1 or spotIndex > World.spotCount() then
			return
		end
		local key = "Crew:" .. tostring(spotIndex)
		if isPlaced(player, character, key) then
			return -- 이미 이 캐릭터를 태웠으면 다시 옮기지 않음 (걸어다니는 중에 탑승 자리로 끌어오지 않게)
		end
		local target = World.spotCFrame(spotIndex) * CFrame.new(0, Config.World.SpotHeight, 0)
		local humanoid = free(character, target)
		if humanoid then
			local entry: Placement = { character = character, key = key }
			placed[player] = entry
			if player:GetAttribute("Captain") == true then
				addCrown(character)
			end
			guard(player, entry, target, false)
		end
	elseif role == "Ghost" then
		local ghostIndex = player:GetAttribute("GhostIndex")
		if typeof(ghostIndex) ~= "number" then
			ghostIndex = 1
		end
		local key = "Ghost:" .. tostring(ghostIndex)
		local target = World.ghostCFrame(ghostIndex)
		if hold(character, target) then
			makeGhostly(character)
			if not isPlaced(player, character, key) then
				local entry: Placement = { character = character, key = key }
				placed[player] = entry
				guard(player, entry, target, true)
			end
		end
	end
end

-- 승무원으로 태움: spotIndex 번 탑승 자리로 옮김
function Seating.board(player: Player, spotIndex: number, isCaptain: boolean)
	player:SetAttribute("Role", "Crew")
	player:SetAttribute("Seat", spotIndex)
	player:SetAttribute("Captain", isCaptain)
	task.spawn(Seating.apply, player)
end

function Seating.ghost(player: Player, ghostIndex: number)
	player:SetAttribute("Role", "Ghost")
	player:SetAttribute("Seat", 0)
	player:SetAttribute("Captain", false)
	player:SetAttribute("GhostIndex", ghostIndex)
	task.spawn(Seating.apply, player)
end

-- 판이 끝나면 모두 발사장으로 돌려보냄 (캐릭터를 새로 만들어 고정·투명 상태를 한 번에 지움)
function Seating.releaseAll()
	table.clear(placed)
	for player in pairs(addedAt) do
		if player.Parent ~= Players then
			addedAt[player] = nil
		end
	end
	for index, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Role", "Lobby")
		player:SetAttribute("Seat", 0)
		player:SetAttribute("Captain", false)
		player:SetAttribute("SpawnIndex", index)
		-- 아직 불러오는 중인 캐릭터(방금 들어온 사람, 리스폰 중인 사람)는 고정도 투명 처리도 없으니 그대로 둡니다.
		-- 불러오기가 끝나기 전에 또 부르지 말라는 것이 공식 문서의 안내이고, 다 만들어지면 onCharacterAdded 가
		-- 방금 바꾼 역할(Lobby)대로 발사장에 둡니다. 다만 LOAD_STUCK 초가 지나도 나타나지 않았으면 불러오기가
		-- 멈춘 것으로 보고 다시 불러옵니다 (그대로 두면 다시 들어올 때까지 아바타가 없음).
		local character = player.Character
		local seen = addedAt[player]
		local stuck = character ~= nil
			and not character:IsDescendantOf(Workspace)
			and seen ~= nil
			and seen.character == character
			and time() - seen.at > LOAD_STUCK
		if character and (character:IsDescendantOf(Workspace) or stuck) then
			task.spawn(function()
				-- 새 이름(LoadCharacterAsync)을 먼저 쓰고, 없는 버전이면 예전 이름으로
				local ok = pcall(function()
					(player :: any):LoadCharacterAsync()
				end)
				if not ok and player.Parent == Players then
					pcall(function()
						(player :: any):LoadCharacter()
					end)
				end
			end)
		end
	end
end

-- 캐릭터가 생길 때: 판 중이면 선실(탑승 자리·유령 자리)로, 아니면 발사장 리스폰 자리로
function Seating.onCharacterAdded(player: Player, character: Model)
	addedAt[player] = { character = character, at = time() }
	if not waitUntilSpawned(player, character) then
		return
	end
	local rootPart = getParts(character)
	if not rootPart or player.Character ~= character then
		return
	end
	local role = player:GetAttribute("Role")
	if role == "Crew" or role == "Ghost" then
		Seating.apply(player)
	else
		local spawnIndex = player:GetAttribute("SpawnIndex")
		if typeof(spawnIndex) ~= "number" then
			spawnIndex = 1
		end
		-- 기본 리스폰 지점이 치워지기 전에 태어나 로켓 안에 끼는 경우를 막음
		local position = rootPart.Position
		local nearRocket = Vector3.new(position.X, 0, position.Z).Magnitude < Config.World.MountRadius + 4
		if nearRocket or position.Y < -20 then
			character:PivotTo(World.spawnCFrame(spawnIndex))
		end
	end
end

return Seating
