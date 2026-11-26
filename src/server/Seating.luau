-- 캐릭터를 좌석에 고정합니다.
-- 기본 Seat 는 점프하면 내려지므로 쓰지 않고, 캐릭터 중심을 좌석 위치에 고정(Anchored)합니다.
-- 그래서 점프 입력을 미션 버튼으로 써도 내려지지 않습니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local World = require(script.Parent.World)

local Seating = {}

local R15_SIT = "rbxassetid://2506281703"
local R6_SIT = "rbxassetid://178130996"
local GOLD = Color3.fromRGB(255, 205, 60)
local GUARD_INTERVAL = 0.5 -- 자리에 고정한 캐릭터가 제자리에 있는지 다시 보는 간격(초)
local GHOST_REFRESH = 6 -- 유령의 투명 처리를 되풀이하는 횟수 (늦게 붙는 장신구 대비, 약 3초 동안)

-- 플레이어마다 지금 잡아 둔 캐릭터와 자리 ("Crew:8", "Ghost:1"). 같은 캐릭터를 같은 자리에 두 번 꾸미지 않으려고
-- 기억합니다. 판이 끝날 때(releaseAll) 모두 지웁니다.
local placed: { [Player]: { character: Model, key: string } } = {}

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

-- 캐릭터를 cframe 에 고정
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

local function playSit(character: Model, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animationId = ""
	local animate = character:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local sitAnimation = sit and sit:FindFirstChildOfClass("Animation")
	if sitAnimation and sitAnimation:IsA("Animation") then
		animationId = sitAnimation.AnimationId
	end
	if animationId == "" then
		animationId = if humanoid.RigType == Enum.HumanoidRigType.R15 then R15_SIT else R6_SIT
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
	end
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

-- 자리에 고정한 캐릭터를 그 자리가 풀릴 때(판이 끝나거나 캐릭터가 바뀔 때)까지 지켜봄.
-- 엔진이 새 캐릭터를 리스폰 지점으로 옮기는 때는 문서에 순서만 있고 시간은 없어서, 자리를 잡은 뒤에
-- 뒤늦게 발사장으로 옮겨질 수 있습니다. 그때나 다른 이유로 자리를 벗어나면 다시 제자리에 둡니다.
local function guard(player: Player, character: Model, key: string, cframe: CFrame, ghost: boolean)
	task.spawn(function()
		local checks = 0
		while true do
			task.wait(GUARD_INTERVAL)
			if player.Parent ~= Players or player.Character ~= character or not isPlaced(player, character, key) then
				return
			end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if rootPart and rootPart:IsA("BasePart") and humanoid then
				if not rootPart.Anchored or (rootPart.Position - cframe.Position).Magnitude > 2 then
					hold(character, cframe)
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
		local seatIndex = player:GetAttribute("Seat")
		if typeof(seatIndex) ~= "number" or seatIndex < 1 or seatIndex > World.seatCount() then
			return
		end
		local key = "Crew:" .. tostring(seatIndex)
		local target = World.seatCFrame(seatIndex) * CFrame.new(0, Config.World.SeatRootOffset, 0.2)
		local humanoid = hold(character, target)
		if humanoid and not isPlaced(player, character, key) then
			placed[player] = { character = character, key = key }
			playSit(character, humanoid)
			if player:GetAttribute("Captain") == true then
				addCrown(character)
			end
			guard(player, character, key, target, false)
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
				placed[player] = { character = character, key = key }
				guard(player, character, key, target, true)
			end
		end
	end
end

function Seating.seat(player: Player, seatIndex: number, isCaptain: boolean)
	player:SetAttribute("Role", "Crew")
	player:SetAttribute("Seat", seatIndex)
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
	for index, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Role", "Lobby")
		player:SetAttribute("Seat", 0)
		player:SetAttribute("Captain", false)
		player:SetAttribute("SpawnIndex", index)
		-- 아직 불러오는 중인 캐릭터(방금 들어온 사람, 리스폰 중인 사람)는 고정도 투명 처리도 없으니 그대로 둡니다.
		-- 불러오기가 끝나기 전에 또 부르지 말라는 것이 공식 문서의 안내이고, 다 만들어지면 onCharacterAdded 가
		-- 방금 바꾼 역할(Lobby)대로 발사장에 둡니다.
		local character = player.Character
		if character and character:IsDescendantOf(Workspace) then
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

-- 캐릭터가 생길 때: 판 중이면 좌석/유령 자리로, 아니면 발사장 리스폰 자리로
function Seating.onCharacterAdded(player: Player, character: Model)
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
