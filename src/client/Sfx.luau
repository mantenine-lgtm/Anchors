-- 소리. 짧은 효과음(Config.Sounds)과 비행 내내 깔리는 엔진음(Config.EngineSound).
-- 엔진음은 반복 소리 세 겹입니다: 굉음(추력만큼), 웅웅 소리(비행 중에는 늘 조금은 남음), 바람(대기권 안에서 빠를수록).
-- 크기와 높이는 EngineMix 가 비행 구간·터보 엔진·속도로 계산하고, 여기서 매 프레임 부드럽게 따라갑니다.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boosters = require(Shared:WaitForChild("Boosters"))
local Config = require(Shared:WaitForChild("Config"))
local EngineMix = require(Shared:WaitForChild("EngineMix"))

local State = require(script.Parent:WaitForChild("State"))

local Sfx = {}

local E = Config.EngineSound

local sounds: { [string]: Sound } = {}
local lastCountdownSecond = -1
local nextAlarm = 0

-- 엔진음 한 겹
type Loop = {
	sound: Sound,
	baseVolume: number, -- Config 의 크기
	pitchScale: number, -- 대신 쓰는 소리(Fallback)로 바뀌면 낮춤
	volume: number, -- 지금 크기 (목표를 부드럽게 따라감)
	pitch: number,
	on: boolean, -- Play 를 불렀는지 (아직 받는 중인 소리에 Play 를 매 프레임 다시 부르지 않게)
}
local loops: { [string]: Loop } = {}
local LOOP_NAMES = { "Roar", "Hum", "Wind" }

local kick = 0 -- 미션 성공·부스터를 쓴 순간 잠깐 커지는 정도 (0~1, KickSeconds 동안 줄어듦)
local flightEnded = false -- 이번 비행이 끝났는지 (끝나면 엔진음이 줄어듦)
local caught = false -- 충격파에 잡혀 끝났는지 (엔진이 바로 끊김)

-- 엔진에 힘을 더하는 부스터 (쓰는 순간 굉음이 잠깐 커짐)
local KICK_BOOSTERS = { RescueFuel = true, Turbo = true, Slingshot = true, Wormhole = true }

function Sfx.play(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

local function makeLoop(folder: Instance, name: string, info: any)
	local sound = Instance.new("Sound")
	sound.Name = "Engine" .. name
	sound.SoundId = info.Id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = folder
	loops[name] = { sound = sound, baseVolume = info.Volume, pitchScale = 1, volume = 0, pitch = 1, on = false }
end

-- 소리 파일을 미리 받아 둠 (에셋 ID 소리는 처음 틀 때 받느라 늦게 나거나 안 날 수 있음).
-- 엔진 소리를 못 받으면 기본 내장 소리를 낮게 늘어뜨려 대신 씀 (비행 중에 엔진음이 아예 없지 않게).
local function preload(folder: Instance)
	local ok, message = pcall(function()
		ContentProvider:PreloadAsync(folder:GetChildren(), function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Success then
				return
			end
			local swapped = false
			for name, loop in pairs(loops) do
				if loop.sound.SoundId == contentId and contentId ~= E.Fallback and name ~= "Wind" then
					loop.sound.SoundId = E.Fallback
					loop.pitchScale = E.FallbackPitch
					loop.on = false -- 켜져 있었으면 다음 프레임에 새 소리로 다시 틂
					swapped = true
				end
			end
			warn(string.format("[ROFLY] 소리를 불러오지 못함 (%s): %s%s", tostring(status), contentId,
				if swapped then " - 엔진음은 기본 내장 소리로 대신합니다" else ""))
		end)
	end)
	if not ok then
		warn("[ROFLY] 소리 미리 받기 실패: " .. tostring(message))
	end
end

function Sfx.init()
	local folder = Instance.new("Folder")
	folder.Name = "RoflySounds"
	for name, info in pairs(Config.Sounds) do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = info.Id
		sound.Volume = info.Volume
		sound.Parent = folder
		sounds[name] = sound
	end
	for _, name in ipairs(LOOP_NAMES) do
		makeLoop(folder, name, (E :: any)[name])
	end
	folder.Parent = SoundService
	task.spawn(preload, folder)

	State.on("Sound", function(name: any)
		if type(name) == "string" then
			Sfx.play(name)
		end
	end)
	State.on("Launched", function()
		flightEnded = false
		caught = false
		Sfx.play("Launch")
	end)
	State.on("ItemUsed", function(info: any)
		Sfx.play("ItemUse")
		if type(info) == "table" and KICK_BOOSTERS[info.item] then
			kick = 1
		end
	end)
	State.on("ThanksFx", function()
		Sfx.play("Thanks")
	end)
	State.on("MissionFx", function(rate: any, combo: any)
		if type(rate) == "number" and rate >= Config.Mission.ComboRule then
			local streak = if type(combo) == "number" then combo else 0
			kick = math.max(kick, math.min(1, 0.6 + 0.08 * streak))
		end
	end)
	State.on("FlightEnd", function(info: any)
		flightEnded = true
		if type(info) == "table" and not info.escaped then
			caught = true
			Sfx.play("Caught")
		end
	end)
	State.on("Phase", function(phase: string)
		if phase == "Join" or phase == "Build" or phase == "Countdown" then
			flightEnded = false
			caught = false
			kick = 0
		end
	end)
end

-- 엔진음 한 겹을 목표 크기·높이로 부드럽게 맞추고, 다 줄어들면 멈춤
local function drive(loop: Loop, level: number, pitch: number, dt: number)
	local target = math.max(level, 0) * loop.baseVolume
	local rate = if target > loop.volume then E.Attack elseif caught then E.CaughtRelease else E.Release
	loop.volume += (target - loop.volume) * math.min(1, dt * rate)
	local sound = loop.sound
	if target <= 0 and loop.volume < 0.003 then
		loop.volume = 0
		if loop.on then
			loop.on = false
			sound:Stop()
		end
		return
	end
	if loop.on then
		loop.pitch += (pitch - loop.pitch) * math.min(1, dt * E.PitchRate)
	else
		loop.pitch = pitch -- 조용하다가 새로 켜질 때는 높이를 바로 맞춤
	end
	sound.Volume = loop.volume
	sound.PlaybackSpeed = math.max(loop.pitch * loop.pitchScale, 0.05)
	if not loop.on then
		loop.on = true
		sound:Play()
	end
end

local function updateEngine(dt: number)
	local f = State.flight
	local mix = EngineMix.mix({
		phase = State.phase(),
		countdownLeft = State.number("LaunchAt") - State.now(),
		t = f.t,
		hot = State.number("HotTime"),
		fuel = State.number("FuelTime"),
		sail = State.number("SailTime"),
		rescueUntil = State.number("RescueUntil"),
		turboUntil = State.number(Boosters.untilAttribute("Turbo")),
		speed = f.speed,
		km = f.km,
		kick = kick,
		ended = flightEnded,
	})
	-- 비행 중에는 탄 사람과 관전자(유령) 모두 로켓 안에 있으므로 똑같이 들림
	drive(loops.Roar, mix.roar, mix.roarPitch, dt)
	drive(loops.Hum, mix.hum, mix.humPitch, dt)
	drive(loops.Wind, mix.wind, mix.windPitch, dt)
	kick = math.max(0, kick - dt / E.KickSeconds)
end

function Sfx.update(dt: number)
	local phase = State.phase()
	if phase == "Countdown" then
		-- 마지막 5초는 1초마다 삑
		local left = State.number("LaunchAt") - State.now()
		local second = math.ceil(left)
		if second ~= lastCountdownSecond then
			lastCountdownSecond = second
			if second >= 1 and second <= 5 then
				Sfx.play("Countdown")
			end
		end
	else
		lastCountdownSecond = -1
	end
	if phase == "Flight" and State.flag("Crisis") then
		local clock = os.clock()
		if clock >= nextAlarm then
			nextAlarm = clock + 0.8
			Sfx.play("CrisisAlarm")
		end
	end
	updateEngine(dt)
end

return Sfx
