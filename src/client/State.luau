-- 서버가 알려 주는 판 상태(ReplicatedStorage.RoundState 의 속성)를 읽기 쉽게 감싼 것.
-- 화면 모듈끼리 주고받는 간단한 알림(on / emit)도 여기 있습니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Route = require(Shared:WaitForChild("Route"))

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

-- ------------------------------------------------------------ 빌드 정보 (서버가 짧은 속성으로 보냄)
-- 종류별 파워 합계 (typeId: Config.Parts.Types 의 Id)
function State.buildTotal(typeId: string): number
	return State.number("Total_" .. typeId)
end

-- 이번 판 장비 묶음 이름
function State.gearName(): string
	return State.text("GearName")
end

-- ------------------------------------------------------------ 입력
-- 글자를 치는 중인지. 기본 채팅 입력창은 GetFocusedTextBox 로는 보이지 않아서 따로 확인합니다.
function State.typing(): boolean
	if UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	local ok, focused = pcall(function()
		local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		return bar ~= nil and bar.IsFocused
	end)
	return ok and focused == true
end

-- ------------------------------------------------------------ 화면 배치 (서버 값이 아니라 클라이언트가 계산)
-- 선실 시점에서 전광판 아래 끝이 화면 높이의 어디에 오는지 (0 = 맨 위, 1 = 맨 아래).
-- CameraRig 가 계산해 넣고, Hud 가 한 줄 안내를 그 바로 아래에 두는 데 씁니다.
State.BoardBottomDefault = 0.313 -- 승무원 10명(기본) 배치일 때의 값
State.boardBottom = State.BoardBottomDefault

-- ------------------------------------------------------------ 부드러운 비행 값
-- 서버는 0.1초마다 값을 보내므로, 화면에는 그 사이를 이어서 보여 줍니다.
State.flight = {
	km = 0,
	speed = 0, -- km/s
	waveKm = 0,
	t = 0,
}

local function updateFlight(dt: number)
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

-- 대기권 마찰 열(0~1). 화면 흔들림(CameraRig)과 선체가 달아오르는 연출(Backdrop)이 같이 씁니다.
-- 비행이 아니면 식습니다.
State.heat = 0

function State.update(dt: number)
	updateFlight(dt)
	local f = State.flight
	local target = if State.phase() == "Flight" then Route.heat(f.km, f.speed) else 0
	State.heat += (target - State.heat) * math.min(1, dt * 1.5)
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
