-- 희귀도 구 연출 (Nick 11-28: 희귀도가 높을수록 화려하게). 서버(RarityHalo)가 캐릭터·봇 머리 위에 띄운 구 가운데
--  · 영웅·전설 구의 글로우가 숨쉬듯 옅어졌다 돌아옴(맥박). 주기는 Config.Halo.Looks[].Pulse (전설이 더 빠름)
--  · 전설 구 둘레에 반짝이가 피어남 (파티클 기본 별 그림, 이미지 에셋 없음)
-- 모두 내 화면에서만 만들고, 관전자(유령)의 구는 움직이지 않습니다.
-- 폰 사양 (프로젝트 규칙): 맥박은 반복 트윈(엔진이 돌림, 매 프레임 스크립트 없음)이고 카메라에서 가까운 것부터
-- Config.Halo.MaxPulses 개까지(나머지는 멈춘 글로우). 반짝이는 SparkleRange 스터드 안의 가까운 전설 구 MaxSparkles 개까지,
-- 구 하나에 초당 SparkleRate 개. 0.5초마다 구를 훑어 새로 생긴 구에 붙이고 없어지거나 멀어진 구의 것은 치웁니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HaloFx = {}

local H = Config.Halo
local FOLDER = "RarityHalo" -- 서버 RarityHalo.FolderName
local GLOW = "Glow" -- 서버 RarityHalo.GlowName
local SPARKLE = "HaloSparkle"
local SCAN = 0.5 -- 구를 다시 훑는 간격(초)

type Candidate = { part: BasePart, distance: number, rarity: number }

local pulses: { [BasePart]: Tween } = {}
local sparkles: { [BasePart]: ParticleEmitter } = {}
local random = Random.new()
local untilScan = 0

local function look(rarity: number): any
	return H.Looks[math.clamp(math.floor(rarity), 1, #H.Looks)]
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

local function startPulse(glow: BasePart, period: number)
	local base = glow:GetAttribute("BaseTransparency")
	local from = if type(base) == "number" then base else glow.Transparency
	glow.Transparency = from
	local tween = TweenService:Create(glow, TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = math.min(from + H.PulseDepth, 1) })
	pulses[glow] = tween
	-- 구마다 박자를 어긋나게 (한꺼번에 깜박이면 기계 같음)
	task.delay(random:NextNumber(0, period / 2), function()
		if pulses[glow] == tween then
			tween:Play()
		end
	end)
end

local function stopPulse(glow: BasePart)
	local tween = pulses[glow]
	if tween then
		pulses[glow] = nil
		tween:Cancel()
		local base = glow:GetAttribute("BaseTransparency")
		if type(base) == "number" and glow.Parent then
			glow.Transparency = base
		end
	end
end

local function startSparkle(orb: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = SPARKLE
	local size = orb.Size.X
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Brightness = 3 -- 밝은 글로우·하늘 앞에서도 또렷하게 (Studio 화면으로 맞춤)
	emitter.ZOffset = 1 -- 글로우·고리 껍질에 가려지지 않게 카메라 쪽으로 당겨 그림
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 1.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(size * 5, size * 10) -- 고리 밖까지 튀어 나감
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

-- 한 번 훑기: 맥박·반짝이를 붙일 구를 카메라에서 가까운 순서로 한도까지 고르고, 나머지는 치움
function HaloFx.scan()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local pulseWant: { Candidate } = {}
	local sparkleWant: { Candidate } = {}
	for _, folder in ipairs(haloFolders()) do
		for _, orb in ipairs(folder:GetChildren()) do
			local rarity = orb:GetAttribute("Rarity")
			if orb:IsA("BasePart") and type(rarity) == "number" and orb:GetAttribute("Ghost") ~= true then
				local l = look(rarity)
				local distance = (orb.Position - eye).Magnitude
				local glow = orb:FindFirstChild(GLOW)
				if l.Pulse and glow and glow:IsA("BasePart") then
					table.insert(pulseWant, { part = glow, distance = distance, rarity = rarity })
				end
				if l.Sparkle and distance <= H.SparkleRange then
					table.insert(sparkleWant, { part = orb, distance = distance, rarity = rarity })
				end
			end
		end
	end
	table.sort(pulseWant, byDistance)
	table.sort(sparkleWant, byDistance)

	local keepPulse: { [BasePart]: boolean } = {}
	for i = 1, math.min(#pulseWant, H.MaxPulses) do
		local c = pulseWant[i]
		keepPulse[c.part] = true
		if not pulses[c.part] then
			startPulse(c.part, look(c.rarity).Pulse)
		end
	end
	for glow in pairs(pulses) do
		if not keepPulse[glow] then
			stopPulse(glow)
		end
	end

	local keepSparkle: { [BasePart]: boolean } = {}
	for i = 1, math.min(#sparkleWant, H.MaxSparkles) do
		local c = sparkleWant[i]
		keepSparkle[c.part] = true
		if not sparkles[c.part] or sparkles[c.part].Parent ~= c.part then
			stopSparkle(c.part)
			local rgb = Config.Parts.RarityColors[math.clamp(math.floor(c.rarity), 1, #Config.Parts.RarityColors)]
			startSparkle(c.part, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
		end
	end
	for orb in pairs(sparkles) do
		if not keepSparkle[orb] then
			stopSparkle(orb)
		end
	end
end

-- 지금 움직이는 맥박·반짝이 수 (검사·디버그용)
function HaloFx.counts(): (number, number)
	local p, s = 0, 0
	for _ in pairs(pulses) do
		p += 1
	end
	for _ in pairs(sparkles) do
		s += 1
	end
	return p, s
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
