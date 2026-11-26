-- 봇 승무원 (데모 전용): 빈 좌석을 채우는 회색 블록 인형.
-- 봇은 기본 부품을 꽂고 미션을 정해진 확률로 성공합니다. 시상·지표에서는 빠집니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local World = require(script.Parent.World)

local Bots = {}

local BODY = Color3.fromRGB(150, 154, 162)
local LIMB = Color3.fromRGB(118, 122, 132)
local HEAD = Color3.fromRGB(205, 208, 214)

local folder: Folder? = nil

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

function Bots.name(index: number): string
	return "봇 " .. index
end

-- 봇의 챕터별 미션 성공 확률
function Bots.rate(skillId: string, chapter: number): number
	local skills = Config.Bots.Skills
	local chosen = skills[1]
	for _, skill in ipairs(skills) do
		if skill.Id == skillId then
			chosen = skill
		end
	end
	local rates = chosen.Rates
	return rates[math.clamp(chapter, 1, #rates)]
end

-- 좌석에 앉은 블록 인형을 만듦
function Bots.place(index: number, seatIndex: number)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Bots"
		created.Parent = World.rocket()
		folder = created
	end
	local seat = World.seatCFrame(seatIndex)
	local model = Instance.new("Model")
	model.Name = "Bot" .. index
	model:SetAttribute("Seat", seatIndex)

	local torso = piece(model, "Torso", Vector3.new(2, 2, 1), seat * CFrame.new(0, 1.9, 0.2), BODY)
	model.PrimaryPart = torso
	local head = piece(model, "Head", Vector3.new(1.2, 1.2, 1.2), seat * CFrame.new(0, 3.5, 0.2), HEAD)
	piece(model, "LeftArm", Vector3.new(0.8, 1.9, 0.8), seat * CFrame.new(-1.45, 1.85, 0.1), LIMB)
	piece(model, "RightArm", Vector3.new(0.8, 1.9, 0.8), seat * CFrame.new(1.45, 1.85, 0.1), LIMB)
	piece(model, "LeftThigh", Vector3.new(0.9, 0.9, 2), seat * CFrame.new(-0.5, 0.75, -0.9), LIMB)
	piece(model, "RightThigh", Vector3.new(0.9, 0.9, 2), seat * CFrame.new(0.5, 0.75, -0.9), LIMB)
	piece(model, "LeftShin", Vector3.new(0.9, 1.8, 0.9), seat * CFrame.new(-0.5, -0.4, -1.9), LIMB)
	piece(model, "RightShin", Vector3.new(0.9, 1.8, 0.9), seat * CFrame.new(0.5, -0.4, -1.9), LIMB)

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	-- 크기를 스터드로 잡아서, 멀리서 볼 때 옆자리 이름표와 겹치지 않게 함
	tag.Size = UDim2.fromScale(5, 1.5)
	tag.StudsOffset = Vector3.new(0, 1.6, 0)
	tag.MaxDistance = 90
	tag.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Bots.name(index)
	label.TextColor3 = Color3.fromRGB(210, 214, 222)
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = tag
	tag.Parent = head

	model.Parent = folder
end

function Bots.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Bots
