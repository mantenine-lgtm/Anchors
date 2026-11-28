-- 희귀도 구 연출 (Nick 11-28: 희귀도가 높을수록 화려하게, 테두리 말고 빛나게). 서버(RarityHalo)가 캐릭터·봇 머리 뒤에 띄운
-- 작은 구에 내 화면에서만 붙입니다.
--  · 빛 번짐 (희귀 이상): 구 자리에 늘 카메라를 보는 둥근 판(BillboardGui) 여러 장을 겹쳐, 가운데가 진하고 바깥으로 옅어지는
--    빛처럼 보이게 함. 크기·진하기는 Config.Halo.Looks[].Glow·GlowTransparency, 판 크기는 GlowSteps. 머리에 가리면 뒤에 숨음
--  · 맥박 (영웅·전설): 빛이 숨쉬듯 커졌다 돌아옴 (주기 Looks[].Pulse, 전설이 더 빠름)
--  · 반짝 별 (전설): 빛 가운데 반짝이는 별이 천천히 돎 · 반짝이 (전설): 구 둘레에서 반짝이 파티클이 튀어 나옴
-- 관전자(유령)의 구에는 아무것도 붙이지 않습니다.
-- 폰 사양 (프로젝트 규칙): 빛 번짐은 GlowRange 스터드 안의 카메라에서 가까운 구 MaxGlows 개까지(나머지는 작은 구만),
-- 맥박·별 돌기는 그 빛에만 붙는 반복 트윈(엔진이 돌림, 매 프레임 스크립트 없음). 반짝이는 SparkleRange 스터드 안의
-- 가까운 전설 구 MaxSparkles 개까지, 구 하나에 초당 SparkleRate 개. 0.5초마다 구를 훑어 새로 붙이고 멀어진 것은 치웁니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HaloFx = {}

local H = Config.Halo
local FOLDER = "RarityHalo" -- 서버 RarityHalo.FolderName
local GLOW = "HaloGlow"
local SPARKLE = "HaloSparkle"
local GLINT_IMAGE = "rbxasset://textures/particles/sparkles_main.dds" -- 엔진 기본 반짝이 그림 (이미지 에셋 없음)
local SCAN = 0.5 -- 구를 다시 훑는 간격(초)
local WHITE = Color3.new(1, 1, 1)

type Candidate = { part: BasePart, distance: number, rarity: number }
type Glow = { gui: BillboardGui, tweens: { Tween } }

local glows: { [BasePart]: Glow } = {}
local sparkles: { [BasePart]: ParticleEmitter } = {}
local random = Random.new()
local untilScan = 0

local function look(rarity: number): any
	return H.Looks[math.clamp(math.floor(rarity), 1, #H.Looks)]
end

local function rarityColor(rarity: number): Color3
	local colors = Config.Parts.RarityColors
	local rgb = colors[math.clamp(math.floor(rarity), 1, #colors)]
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- 지금 화면의 모든 구 폴더 (사람 캐릭터 + 봇)
local function haloFolders(): { Instance }
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local folder = if character then character:FindFirstChild(FOLDER) else nil
		if folder then
			table.insert(out, folder)
		end
	end
	local rofly = Workspace:FindFirstChild("Rofly")
	local rocket = if rofly then rofly:FindFirstChild("Rocket") else nil
	local bots = if rocket then rocket:FindFirstChild("Bots") else nil
	if bots then
		for _, bot in ipairs(bots:GetChildren()) do
			local folder = bot:FindFirstChild(FOLDER)
			if folder then
				table.insert(out, folder)
			end
		end
	end
	return out
end

local function byDistance(a: Candidate, b: Candidate): boolean
	return a.distance < b.distance
end

local function forever(seconds: number, style: Enum.EasingStyle, reverses: boolean): TweenInfo
	return TweenInfo.new(seconds, style, Enum.EasingDirection.InOut, -1, reverses)
end

-- 빛 번짐: 겹친 둥근 판 + (전설) 반짝 별. 맥박·별 돌기 트윈은 이 빛과 함께 치움
local function startGlow(orb: BasePart, rarity: number)
	local l = look(rarity)
	local color = rarityColor(rarity)
	local diameter = orb.Size.X * l.Glow
	local gui = Instance.new("BillboardGui")
	gui.Name = GLOW
	gui.Size = UDim2.new(diameter, 0, diameter, 0) -- 스터드
	gui.LightInfluence = 0
	gui.Brightness = H.GlowBrightness
	gui.MaxDistance = H.GlowRange
	for index, step in ipairs(H.GlowSteps) do
		local disc = Instance.new("Frame")
		disc.Name = "Glow" .. index
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(step, step)
		disc.BackgroundColor3 = color
		disc.BackgroundTransparency = l.GlowTransparency
		disc.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		disc.Parent = gui
	end
	local tweens: { Tween } = {}
	if l.Glint then
		local glint = Instance.new("ImageLabel")
		glint.Name = "Glint"
		glint.BackgroundTransparency = 1
		glint.AnchorPoint = Vector2.new(0.5, 0.5)
		glint.Position = UDim2.fromScale(0.5, 0.5)
		glint.Size = UDim2.fromScale(l.Glint / l.Glow, l.Glint / l.Glow)
		glint.Image = GLINT_IMAGE
		glint.ImageColor3 = WHITE:Lerp(color, 0.25)
		glint.Rotation = random:NextNumber(0, 90)
		glint.ZIndex = 2
		glint.Parent = gui
		table.insert(tweens, TweenService:Create(glint, forever(H.GlintSpin, Enum.EasingStyle.Linear, false),
			{ Rotation = glint.Rotation + 360 }))
	end
	if l.Pulse then
		local big = diameter * (1 + H.PulseScale)
		table.insert(tweens, TweenService:Create(gui, forever(l.Pulse / 2, Enum.EasingStyle.Sine, true), { Size = UDim2.new(big, 0, big, 0) }))
	end
	gui.Parent = orb
	local glow: Glow = { gui = gui, tweens = tweens }
	glows[orb] = glow
	-- 구마다 박자를 어긋나게 (한꺼번에 깜박이면 기계 같음)
	if #tweens > 0 then
		task.delay(random:NextNumber(0, (l.Pulse or 1) / 2), function()
			if glows[orb] == glow then
				for _, tween in ipairs(tweens) do
					tween:Play()
				end
			end
		end)
	end
end

local function stopGlow(orb: BasePart)
	local glow = glows[orb]
	if glow then
		glows[orb] = nil
		for _, tween in ipairs(glow.tweens) do
			tween:Cancel()
		end
		glow.gui:Destroy()
	end
end

local function startSparkle(orb: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = SPARKLE
	local size = orb.Size.X
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Brightness = 3 -- 밝은 빛·하늘 앞에서도 또렷하게 (Studio 화면으로 맞춤)
	emitter.ZOffset = 1 -- 빛 번짐 판에 가려지지 않게 카메라 쪽으로 당겨 그림
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 1.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(size * 5, size * 10) -- 빛 밖까지 튀어 나감
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Drag = 3
	emitter.Rate = H.SparkleRate
	emitter.Parent = orb
	sparkles[orb] = emitter
end

local function stopSparkle(orb: BasePart)
	local emitter = sparkles[orb]
	if emitter then
		sparkles[orb] = nil
		emitter:Destroy()
	end
end

-- 한 번 훑기: 빛·반짝이를 붙일 구를 카메라에서 가까운 순서로 한도까지 고르고, 나머지는 치움
function HaloFx.scan()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local glowWant: { Candidate } = {}
	local sparkleWant: { Candidate } = {}
	for _, folder in ipairs(haloFolders()) do
		for _, orb in ipairs(folder:GetChildren()) do
			local rarity = orb:GetAttribute("Rarity")
			if orb:IsA("BasePart") and type(rarity) == "number" and orb:GetAttribute("Ghost") ~= true then
				local l = look(rarity)
				local distance = (orb.Position - eye).Magnitude
				if l.Glow and distance <= H.GlowRange then
					table.insert(glowWant, { part = orb, distance = distance, rarity = rarity })
				end
				if l.Sparkle and distance <= H.SparkleRange then
					table.insert(sparkleWant, { part = orb, distance = distance, rarity = rarity })
				end
			end
		end
	end
	table.sort(glowWant, byDistance)
	table.sort(sparkleWant, byDistance)

	local keepGlow: { [BasePart]: boolean } = {}
	for i = 1, math.min(#glowWant, H.MaxGlows) do
		local c = glowWant[i]
		keepGlow[c.part] = true
		local glow = glows[c.part]
		if not glow or glow.gui.Parent ~= c.part then
			stopGlow(c.part)
			startGlow(c.part, c.rarity)
		end
	end
	for orb in pairs(glows) do
		if not keepGlow[orb] then
			stopGlow(orb)
		end
	end

	local keepSparkle: { [BasePart]: boolean } = {}
	for i = 1, math.min(#sparkleWant, H.MaxSparkles) do
		local c = sparkleWant[i]
		keepSparkle[c.part] = true
		if not sparkles[c.part] or sparkles[c.part].Parent ~= c.part then
			stopSparkle(c.part)
			startSparkle(c.part, rarityColor(c.rarity))
		end
	end
	for orb in pairs(sparkles) do
		if not keepSparkle[orb] then
			stopSparkle(orb)
		end
	end
end

-- 지금 붙은 빛·움직이는 트윈·반짝이 수 (검사·디버그용)
function HaloFx.counts(): (number, number, number)
	local g, t, s = 0, 0, 0
	for _, glow in pairs(glows) do
		g += 1
		t += #glow.tweens
	end
	for _ in pairs(sparkles) do
		s += 1
	end
	return g, t, s
end

function HaloFx.init() end

function HaloFx.update(dt: number)
	untilScan -= dt
	if untilScan > 0 then
		return
	end
	untilScan = SCAN
	HaloFx.scan()
end

return HaloFx
