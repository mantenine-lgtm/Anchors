-- 캐릭터를 좌석에 고정합니다.
-- 기본 Seat 는 점프하면 내려지므로 쓰지 않고, 캐릭터 중심을 좌석 위치에 고정(Anchored)합니다.
-- 그래서 점프 입력을 미션 버튼으로 써도 내려지지 않습니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local World = require(script.Parent.World)

local Seating = {}

local R15_SIT = "rbxassetid://2506281703"
local R6_SIT = "rbxassetid://178130996"
local GOLD = Color3.fromRGB(255, 205, 60)

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

-- 플레이어의 역할(속성 Role)에 맞게 지금 캐릭터를 배치. 캐릭터가 새로 생길 때마다 불립니다.
function Seating.apply(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local role = player:GetAttribute("Role")
	if role == "Crew" then
		local seatIndex = player:GetAttribute("Seat")
		if typeof(seatIndex) ~= "number" or seatIndex < 1 or seatIndex > World.seatCount() then
			return
		end
		local seatCFrame = World.seatCFrame(seatIndex)
		local humanoid = hold(character, seatCFrame * CFrame.new(0, Config.World.SeatRootOffset, 0.2))
		if humanoid then
			playSit(character, humanoid)
			if player:GetAttribute("Captain") == true then
				addCrown(character)
			end
		end
	elseif role == "Ghost" then
		local ghostIndex = player:GetAttribute("GhostIndex")
		if typeof(ghostIndex) ~= "number" then
			ghostIndex = 1
		end
		if hold(character, World.ghostCFrame(ghostIndex)) then
			makeGhostly(character)
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
	for index, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Role", "Lobby")
		player:SetAttribute("Seat", 0)
		player:SetAttribute("Captain", false)
		player:SetAttribute("SpawnIndex", index)
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

-- 캐릭터가 생길 때: 판 중이면 좌석/유령 자리로, 아니면 발사장 리스폰 자리로
function Seating.onCharacterAdded(player: Player, character: Model)
	local rootPart = getParts(character)
	if not rootPart then
		return
	end
	task.wait(0.2) -- 기본 리스폰 배치가 끝난 뒤에 옮김
	if player.Character ~= character then
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
