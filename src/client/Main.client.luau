-- 클라이언트 시작점 (StarterPlayerScripts > Client > Main)
-- ROFLY 데모 1: 화면 모듈들을 차례로 켜고, 매 프레임 갱신합니다.
-- 모듈 하나가 오류를 내도 나머지는 계속 돌도록 각각 따로 감쌉니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

-- 서버가 만든 신호 폴더와 상태 폴더가 올 때까지 기다림
ReplicatedStorage:WaitForChild(Net.FolderName)
ReplicatedStorage:WaitForChild(Net.StateName)

local State = require(script.Parent:WaitForChild("State"))

local MODULE_NAMES = { "Sfx", "Hud", "BuildUi", "CaptainAlert", "MissionUi", "BoosterMenu", "Board", "CameraRig", "Backdrop", "DebugPanel" }

type Entry = { name: string, module: any, warned: boolean }
local entries: { Entry } = {}

State.init()
for _, name in ipairs(MODULE_NAMES) do
	local ok, result = pcall(function()
		local module = (require :: any)(script.Parent:WaitForChild(name))
		module.init()
		return module
	end)
	if ok then
		table.insert(entries, { name = name, module = result, warned = false })
	else
		warn(string.format("[ROFLY] 화면 모듈 %s 시작 실패: %s", name, tostring(result)))
	end
end

-- 휴대폰은 가로 화면으로 (세로로 들면 화면 요소가 아주 작아짐)
task.spawn(function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	pcall(function()
		(playerGui :: PlayerGui).ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end)
end)

-- 내 화면 오른쪽 위와 겹치는 기본 UI(플레이어 목록 등)를 끔. 채팅은 그대로 둠.
task.spawn(function()
	local hidden = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }
	for _, coreType in ipairs(hidden) do
		for _ = 1, 6 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(coreType, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	State.update(dt)
	for _, entry in ipairs(entries) do
		local update = entry.module.update
		if update then
			local ok, message = pcall(update, dt)
			if not ok and not entry.warned then
				entry.warned = true
				warn(string.format("[ROFLY] 화면 모듈 %s 오류: %s", entry.name, tostring(message)))
			end
		end
	end
end)

print("[ROFLY] 데모 1 클라이언트 시작")
