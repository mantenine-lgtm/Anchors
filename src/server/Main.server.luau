-- 서버 시작점 (ServerScriptService > Server > Main)
-- ROFLY 데모 1: 월드를 코드로 만들고 판 진행을 시작합니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

-- 신호(RemoteEvent)를 먼저 만들어야 다른 모듈이 연결할 수 있음
Net.setupServer()

local World = require(script.Parent.World)
local Round = require(script.Parent.Round)
local Lift = require(script.Parent.Lift)
local DebugCommands = require(script.Parent.DebugCommands)
local GachaService = require(script.Parent.GachaService)
local RarityHalo = require(script.Parent.RarityHalo)

World.build()
Round.start()
Lift.start() -- 발사탑 엘리베이터 (발사장에 있으면)
DebugCommands.init()
GachaService.init()
RarityHalo.start() -- 머리 뒤 희귀도 구

print("[ROFLY] 데모 1 서버 시작")
