-- 소리. 지금은 Roblox 기본 내장 소리를 임시로 씁니다 (Config.Sounds 에서 바꿀 수 있음).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local State = require(script.Parent:WaitForChild("State"))

local Sfx = {}

local sounds: { [string]: Sound } = {}
local lastCountdownSecond = -1
local nextAlarm = 0

function Sfx.play(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
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
	folder.Parent = SoundService

	State.on("Sound", function(name: any)
		if type(name) == "string" then
			Sfx.play(name)
		end
	end)
	State.on("Launched", function()
		Sfx.play("Launch")
	end)
	State.on("ItemUsed", function()
		Sfx.play("ItemUse")
	end)
	State.on("ThanksFx", function()
		Sfx.play("Thanks")
	end)
	State.on("FlightEnd", function(info: any)
		if type(info) == "table" and not info.escaped then
			Sfx.play("Caught")
		end
	end)
end

function Sfx.update(_dt: number)
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
end

return Sfx
