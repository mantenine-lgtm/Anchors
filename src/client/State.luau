-- 서버가 알려 주는 판 상태(ReplicatedStorage.RoundState 의 속성)를 읽기 쉽게 감싼 것.
-- 화면 모듈끼리 주고받는 간단한 알림(on / emit)도 여기 있습니다.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local State = {}

local player = Players.LocalPlayer
local folder: Instance = ReplicatedStorage:WaitForChild(Net.StateName)

-- ------------------------------------------------------------ 서버 상태 읽기
function State.number(name: string): number
	local value = folder:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return 0
end

function State.text(name: string): string
	local value = folder:GetAttribute(name)
	if typeof(value) == "string" then
		return value
	end
	return ""
end

function State.flag(name: string): boolean
	return folder:GetAttribute(name) == true
end

function State.phase(): string
	local value = folder:GetAttribute("Phase")
	if typeof(value) == "string" then
		return value
	end
	return "Join"
end

function State.onChange(name: string, callback: () -> ()): RBXScriptConnection
	return folder:GetAttributeChangedSignal(name):Connect(callback)
end

-- 서버 시각 (서버와 클라이언트가 같은 값을 봄)
function State.now(): number
	return Workspace:GetServerTimeNow()
end

-- 지금 페이즈가 끝나기까지 남은 초 (끝이 정해지지 않았으면 0)
function State.phaseLeft(): number
	local endsAt = State.number("PhaseEndsAt")
	if endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - State.now())
end

-- ------------------------------------------------------------ 내 상태
function State.myNumber(name: string): number
	local value = player:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return 0
end

-- "Lobby" 발사장 | "Crew" 승무원 | "Ghost" 관전
function State.role(): string
	local value = player:GetAttribute("Role")
	if typeof(value) == "string" then
		return value
	end
	return "Lobby"
end

function State.isCaptain(): boolean
	return player:GetAttribute("Captain") == true
end

function State.joined(): boolean
	return player:GetAttribute("Joined") == true
end

function State.canDebug(): boolean
	return player:GetAttribute("Debug") == true
end

function State.onMyChange(name: string, callback: () -> ()): RBXScriptConnection
	return player:GetAttributeChangedSignal(name):Connect(callback)
end

-- 로켓 안에 있는 동안(승무원·관전자)은 연출 카메라와 비행 화면을 씀
function State.aboard(): boolean
	local role = State.role()
	if role ~= "Crew" and role ~= "Ghost" then
		return false
	end
	local phase = State.phase()
	return phase == "Build" or phase == "Countdown" or phase == "Flight" or phase == "Results"
end

-- ------------------------------------------------------------ 승무원 명단 (빌드 때 서버가 JSON 으로 보냄)
export type CrewInfo = { name: string, seat: number, bot: boolean, captain: boolean, userId: number }
export type BuildInfo = { crew: { CrewInfo }, totals: { [string]: number }, gear: string }

local buildJson = ""
local buildInfo: BuildInfo? = nil

function State.build(): BuildInfo?
	local json = State.text("BuildJson")
	if json ~= buildJson then
		buildJson = json
		buildInfo = nil
		if json ~= "" then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(json)
			end)
			if ok and type(decoded) == "table" and type(decoded.crew) == "table" and type(decoded.totals) == "table" then
				buildInfo = decoded
			end
		end
	end
	return buildInfo
end

function State.crewBySeat(seat: number): CrewInfo?
	local info = State.build()
	if info then
		for _, member in ipairs(info.crew) do
			if member.seat == seat then
				return member
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------ 부드러운 비행 값
-- 서버는 0.1초마다 값을 보내므로, 화면에는 그 사이를 이어서 보여 줍니다.
State.flight = {
	km = 0,
	speed = 0, -- km/s
	waveKm = 0,
	t = 0,
}

function State.update(dt: number)
	local f = State.flight
	if State.phase() ~= "Flight" then
		f.km = State.number("Km")
		f.speed = State.number("Speed")
		f.waveKm = State.number("WaveKm")
		f.t = State.number("T")
		return
	end
	local serverKm = State.number("Km")
	local serverWave = State.number("WaveKm")
	local serverT = State.number("T")
	f.speed += (State.number("Speed") - f.speed) * math.min(1, dt * 8)
	f.km += f.speed * dt
	f.waveKm += State.number("WaveSpeed") * dt
	f.t += dt
	-- 서버 값에서 크게 벗어나면(디버그 건너뛰기 등) 바로 맞추고, 아니면 천천히 당김
	local pull = math.min(1, dt * 4)
	if math.abs(serverT - f.t) > 1 then
		f.km = serverKm
		f.waveKm = serverWave
		f.t = serverT
		f.speed = State.number("Speed")
	else
		f.km += (serverKm - f.km) * pull
		f.waveKm += (serverWave - f.waveKm) * pull
		f.t += (serverT - f.t) * pull
	end
end

-- ------------------------------------------------------------ 화면 모듈끼리의 알림
local listeners: { [string]: { (...any) -> () } } = {}

function State.on(name: string, callback: (...any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, callback)
end

function State.emit(name: string, ...: any)
	local list = listeners[name]
	if not list then
		return
	end
	for _, callback in ipairs(list) do
		task.spawn(callback, ...)
	end
end

-- 서버가 보내는 신호를 화면 모듈들에게 그대로 전달
function State.init()
	for _, name in ipairs({ "Launched", "MissionStart", "MissionResult", "ItemUsed", "ThanksFx", "FlightEnd", "Results", "Announce" }) do
		Net.event(name).OnClientEvent:Connect(function(...)
			State.emit(name, ...)
		end)
	end
	folder:GetAttributeChangedSignal("Phase"):Connect(function()
		State.emit("Phase", State.phase())
	end)
	folder:GetAttributeChangedSignal("Crisis"):Connect(function()
		State.emit("Crisis", State.flag("Crisis"))
	end)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		State.emit("Role", State.role())
	end)
end

State.Config = Config

return State
