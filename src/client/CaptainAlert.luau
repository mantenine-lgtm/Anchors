-- 선장 '발사 임박' 알림. 카운트다운이 Config.Captain.AlertSeconds 초 남으면 선장 화면에만 금색 테두리가
-- 깜박이고, 발사 버튼 바로 위에 '발사 임박!' 글자가 뜨고, 경보음이 세 번 울립니다. 발사되면 사라집니다.
-- (조립이 끝나 가는 때의 미리 알림은 조립 화면 BuildUi 에 있습니다.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local CaptainAlert = {}

local C = Ui.Colors
local EDGE = 14 -- 테두리 두께 (기준 1280x720 단위)
local BEEPS = 3
local BEEP_GAP = 0.18 -- 경보음 사이 간격(초)
local PULSE = 2.5 -- 1초에 깜박이는 횟수
-- 글자 자리: 선장 발사 패널(화면 아래 가운데, 아래 여백 36 + 높이 190) 바로 위
local LAUNCH_PANEL_TOP = 36 + 190

local holder: Frame
local edges: { Frame } = {}
local titleLabel: TextLabel
local subLabel: TextLabel
local alerted = false -- 이번 카운트다운에 경보음을 울렸는지
local launched = false

local function beep()
	for i = 0, BEEPS - 1 do
		task.delay(i * BEEP_GAP, function()
			State.emit("Sound", "LaunchAlert")
		end)
	end
end

local function edge(name: string, anchor: Vector2, position: UDim2, size: UDim2)
	local frame = Ui.frame(holder, name, {
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundColor3 = C.Yellow,
		BackgroundTransparency = 0.3,
	})
	table.insert(edges, frame)
end

function CaptainAlert.init()
	local _, root = Ui.screen("RoflyCaptainAlert", 12)
	holder = Ui.frame(root, "LaunchAlert", {
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	})
	edge("Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, EDGE))
	edge("Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, EDGE))
	edge("Left", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, EDGE, 1, 0))
	edge("Right", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, EDGE, 1, 0))
	titleLabel = Ui.label(holder, "Title", "발사 임박!", 48, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(LAUNCH_PANEL_TOP + 36)),
		Size = UDim2.fromOffset(700, 56),
		TextColor3 = C.Yellow,
		TextStrokeTransparency = 0.1,
	})
	subLabel = Ui.label(holder, "Sub", "선장님, 카운트다운이 0이 되는 순간 발사 버튼 (스페이스)", 22, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(LAUNCH_PANEL_TOP + 6)),
		Size = UDim2.fromOffset(700, 28),
		TextStrokeTransparency = 0.3,
	})

	State.on("Phase", function(phase: string)
		if phase == "Countdown" then
			alerted = false
			launched = false
		end
	end)
	State.on("Launched", function()
		launched = true
	end)
end

function CaptainAlert.update(_dt: number)
	local launchAt = State.number("LaunchAt")
	local left = launchAt - State.now()
	-- 지난 판의 LaunchAt 이 남아 있을 때(아주 오래전 값) 잘못 울리지 않게 아래쪽도 막음
	local show = State.phase() == "Countdown"
		and State.role() == "Crew"
		and State.isCaptain()
		and not launched
		and launchAt > 0
		and left <= Config.Captain.AlertSeconds
		and left > -(Config.Captain.AutoDelay + 1)
	holder.Visible = show
	if not show then
		return
	end
	if not alerted then
		alerted = true
		beep()
	end
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * math.pi * 2 * PULSE)
	for _, frame in ipairs(edges) do
		frame.BackgroundTransparency = 0.1 + 0.55 * pulse
	end
	titleLabel.TextTransparency = 0.3 * pulse
	titleLabel.TextColor3 = if left <= Config.Captain.EarlyLimit then C.Orange else C.Yellow
	subLabel.Text = if left <= Config.Captain.EarlyLimit
		then "지금! 발사 버튼 (스페이스)"
		else "선장님, 카운트다운이 0이 되는 순간 발사 버튼 (스페이스)"
end

return CaptainAlert
