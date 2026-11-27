-- 부품 피버 연출 (Nick 11-28): 미션 판정 뒤 피버에 들어간 부품 둘레에 반짝임을 띄웁니다. 다음 미션 판정까지 이어집니다.
--  · 선실 부품 장착판(PartsBoard)·내 부품 패널(MyParts)의 칸: 금빛 테두리가 깜박이고 둘레에서 네 갈래 별빛이 번갈아 반짝임.
--    그 화면들이 FeverFx.glints 로 만들고 FeverFx.show 로 켜고 끔
--  · 로켓 겉면: 선체 둘레에서 금빛 반짝이가 피어나 뒤(아래)로 흘러감. 피버 부품이 많을수록 많이, 미션 판정 순간에 한 번 확
-- 피버 여부는 서버가 RoundState.Grid/<종류>의 F<좌석> 속성으로 알려 줍니다 (shared/Fever.luau, 서버 Round 의 rollFever).
-- 휴대폰 사양 (프로젝트 규칙): 별빛은 이미지 없이 Frame 막대 2개, 움직임은 반복 트윈(엔진이 돌림, 매 프레임 스크립트 없음)이고
-- 장착판 칸들은 한꺼번에 움직이는 수에 한도(MAX_TWEENS)가 있음 (내 부품 패널 6칸은 늘 움직임). 로켓 반짝이는 파티클 하나
-- (초당 많아야 HULL_RATE 개). 모두 내 화면에서만 만듦.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fever = require(Shared:WaitForChild("Fever"))
local Net = require(Shared:WaitForChild("Net"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local FeverFx = {}

local W = Config.World

FeverFx.Gold = Color3.fromRGB(255, 208, 72) -- 피버 테두리·글자 색 (부품 종류 색·내 부품 분홍과 다른 금색)
local SPARK = Color3.fromRGB(255, 248, 220) -- 별빛 가운데 색
local MAX_TWEENS = 160 -- 장착판에서 한꺼번에 움직이는 별빛·테두리 수 한도. 넘으면 나머지는 멈춘 채로 보임 (50명 판도 가볍게)
local HULL_RATE = 60 -- 로켓의 모든 부품이 피버일 때 선체 반짝이 수(초당). 보통 판(평균 28% 피버)은 초당 약 17개
local HULL_BURST = 50 -- 미션 판정 순간 한 번에 터지는 반짝이 수 × 피버 비율
local HULL_SIZE = 3.5 -- 반짝이 가장 클 때 크기(스터드). 바깥 시점(약 450 스터드 거리)에서도 보이게
-- 별빛 자리 (칸 안의 비율): 귀퉁이부터 번갈아. 칸마다 앞에서부터 count 개를 씀
local STAR_SPOTS = {
	Vector2.new(0.1, 0.1),
	Vector2.new(0.92, 0.88),
	Vector2.new(0.9, 0.14),
	Vector2.new(0.12, 0.9),
	Vector2.new(0.52, 0.02),
	Vector2.new(0.98, 0.5),
}

export type Glints = {
	root: Frame,
	halo: UIStroke,
	stars: { UIScale },
	tweens: { Tween },
	free: boolean, -- true 면 한도(MAX_TWEENS)를 따지지 않음 (내 부품 패널: 6칸뿐이고 내 부품이라 늘 움직이게)
	on: boolean,
}

local stateFolder: Instance = ReplicatedStorage:WaitForChild(Net.StateName)
local random = Random.new()
local activeTweens = 0
local hull: ParticleEmitter? = nil
local hullShare = -1 -- 마지막으로 넣은 피버 비율 (바뀔 때만 Rate 를 다시 넣음)

-- ------------------------------------------------------------ 서버 값
-- 그 종류의 그 좌석 부품이 지금 피버 중인지
function FeverFx.isOn(typeId: string, seat: number): boolean
	if seat <= 0 then
		return false
	end
	local grid = stateFolder:FindFirstChild("Grid")
	local folder = grid and grid:FindFirstChild(typeId)
	return folder ~= nil and folder:GetAttribute(Fever.attribute(seat)) == true
end

-- 로켓에 꽂힌 부품 중 지금 피버인 비율 (0~1). 비행 중이 아니면 0
function FeverFx.share(): number
	local placed = State.number("FeverParts")
	if State.phase() ~= "Flight" or placed <= 0 then
		return 0
	end
	return math.clamp(State.number("FeverCount") / placed, 0, 1)
end

-- ------------------------------------------------------------ 화면 칸의 반짝임
-- 네 갈래 별빛 하나: 가운데가 밝고 끝으로 갈수록 사라지는 가로·세로 막대. 크기는 UIScale 로 반짝임
local function star(parent: Instance, index: number, spot: Vector2, scale: number): UIScale
	local holder = Ui.frame(parent, "Star" .. index, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(spot.X, spot.Y),
		Size = UDim2.fromScale(scale, scale),
		ZIndex = 3,
	})
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	for _, vertical in ipairs({ false, true }) do
		local bar = Ui.frame(holder, if vertical then "V" else "H", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if vertical then UDim2.fromScale(0.16, 1) else UDim2.fromScale(1, 0.16),
			BackgroundColor3 = SPARK,
			BackgroundTransparency = 0,
			ZIndex = 3,
		})
		Ui.make("UIGradient", {
			Rotation = if vertical then 90 else 0,
			Transparency = fade,
			Color = ColorSequence.new(FeverFx.Gold, SPARK),
			Parent = bar,
		})
	end
	return Ui.make("UIScale", { Scale = 0, Parent = holder })
end

-- parent(칸·패널 한 칸)를 덮는 반짝임을 만듦 (처음엔 꺼짐). count = 별빛 수, scale = 별빛 크기(칸 너비 비율),
-- pad = 금빛 테두리를 칸 밖으로 내미는 픽셀, thickness = 테두리 굵기, free = 한도 없이 늘 움직임
function FeverFx.glints(parent: GuiObject, count: number, scale: number, pad: number, thickness: number, free: boolean?): Glints
	local root = Ui.frame(parent, "Fever", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, pad * 2, 1, pad * 2),
		Visible = false,
		ZIndex = 3,
	})
	Ui.corner(root, 6)
	local halo = Ui.stroke(root, FeverFx.Gold, thickness, 0)
	local stars: { UIScale } = {}
	for i = 1, math.clamp(count, 0, #STAR_SPOTS) do
		stars[i] = star(root, i, STAR_SPOTS[i], scale)
	end
	return { root = root, halo = halo, stars = stars, tweens = {}, free = free == true, on = false }
end

local function stopTweens(g: Glints)
	for _, tween in ipairs(g.tweens) do
		tween:Cancel()
	end
	if not g.free then
		activeTweens = math.max(0, activeTweens - #g.tweens)
	end
	table.clear(g.tweens)
end

local function loop(g: Glints, instance: Instance, seconds: number, delay: number, goals: { [string]: any }): Tween?
	if not g.free and activeTweens >= MAX_TWEENS then
		return nil
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delay)
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	if not g.free then
		activeTweens += 1
	end
	return tween
end

-- 반짝임을 켜고 끔 (바뀔 때만 일함). 켜면 테두리가 깜박이고 별빛이 저마다 다른 박자로 커졌다 작아짐
function FeverFx.show(g: Glints, on: boolean)
	if g.on == on then
		return
	end
	g.on = on
	stopTweens(g)
	g.root.Visible = on
	if not on then
		return
	end
	g.halo.Transparency = 0
	local pulse = loop(g, g.halo, 0.45, 0, { Transparency = 0.65 })
	if pulse then
		table.insert(g.tweens, pulse)
	end
	for _, scale in ipairs(g.stars) do
		scale.Scale = 0.15
		local tween = loop(g, scale, 0.35 + random:NextNumber() * 0.3, random:NextNumber() * 0.5, { Scale = 1 })
		if tween then
			table.insert(g.tweens, tween)
		else
			scale.Scale = 0.8 -- 한도를 넘음: 멈춘 별빛
		end
	end
end

-- 칸을 지우기 전에 부름 (반복 트윈을 멈추고 한도를 돌려받음)
function FeverFx.release(g: Glints)
	stopTweens(g)
	g.on = false
end

-- ------------------------------------------------------------ 로켓 겉면 반짝이
local function buildHull(container: Instance)
	local radius = W.HullRadius + 1
	local height = W.RocketTopY - W.RocketBaseY
	local part = Instance.new("Part")
	part.Name = "FeverShell"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(radius * 2, height, radius * 2)
	part.CFrame = CFrame.new(0, W.RocketBaseY + height / 2, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FeverSparkles" -- 기본 그림이 반짝이(sparkles_main)라 Texture 는 그대로
	emitter.Shape = Enum.ParticleEmitterShape.Cylinder -- 세로(Y) 원기둥 겉면에서 바깥으로
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(3, 8)
	emitter.Acceleration = Vector3.new(0, -24, 0) -- 로켓 뒤(아래)로 흘러감
	emitter.Drag = 1
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, HULL_SIZE),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(SPARK, FeverFx.Gold)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Parent = part
	part.Parent = container
	hull = emitter
end

local function onMissionResult(info: any)
	local emitter = hull
	if emitter == nil or type(info) ~= "table" or State.phase() ~= "Flight" then
		return
	end
	local fevered = if type(info.fever) == "number" then info.fever else 0
	local placed = if type(info.feverParts) == "number" then info.feverParts else 0
	local share = if placed > 0 then math.clamp(fevered / placed, 0, 1) else 0
	local count = math.floor(HULL_BURST * share + 0.5)
	if count > 0 then
		emitter:Emit(count)
	end
end

function FeverFx.init()
	local container = Instance.new("Folder")
	container.Name = "RoflyFever"
	container.Parent = Workspace
	buildHull(container)
	State.on("MissionResult", onMissionResult)
end

function FeverFx.update(_dt: number)
	local emitter = hull
	if emitter == nil then
		return
	end
	local share = FeverFx.share()
	if share ~= hullShare then
		hullShare = share
		emitter.Rate = HULL_RATE * share
	end
end

-- 검사용
FeverFx._internal = {
	activeTweens = function(): number
		return activeTweens
	end,
	limits = function(): (number, number, number)
		return MAX_TWEENS, HULL_RATE, HULL_BURST
	end,
}

return FeverFx
