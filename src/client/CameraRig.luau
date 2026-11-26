-- 카메라: 로켓에 타 있는 동안은 연출 카메라(선실 뒤에서 외창을 보는 화면)를 쓰고,
-- 발사장에 있을 때는 Roblox 기본 카메라로 돌려줍니다.
-- 선실 화면은 좌석 쪽 벽을 내 화면에서만 숨겨서 "잘라 본 단면"처럼 보여 줍니다.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local CameraRig = {}

local W = Config.World
local C = Ui.Colors
local player = Players.LocalPlayer

local FIELD_OF_VIEW = 70
local HIDE_HALF_ANGLE = 48 -- 좌석 쪽(180도)에서 이 각도 안의 벽을 숨김

local view = "Interior" -- "Interior" 선실 | "Exterior" 바깥
local scripted = false
local wallsHidden = false
local shake = 0
local closeupSeat = 0
local closeupUntil = 0
local viewButton: TextButton
local controls: any = nil
local highlight: Highlight? = nil

-- ------------------------------------------------------------ 조작과 기본 UI 켜고 끄기
local function getControls(): any
	if controls == nil then
		controls = false
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 5)
			local module = scripts and scripts:WaitForChild("PlayerModule", 5)
			if module and module:IsA("ModuleScript") then
				return (require :: any)(module):GetControls()
			end
			return nil
		end)
		if ok and result then
			controls = result
		end
	end
	return controls
end

local function setMovement(enabled: boolean)
	task.spawn(function()
		local c = getControls()
		if c then
			pcall(function()
				if enabled then
					c:Enable()
				else
					c:Disable()
				end
			end)
		end
	end)
	-- 기본 터치 조작(이동 스틱·점프 버튼)이 미션 버튼과 겹치지 않게 숨김
	pcall(function()
		GuiService.TouchControlsEnabled = enabled
	end)
	-- 타 있는 동안 캐릭터 초기화를 막음 (자리에서 떨어지지 않게)
	task.spawn(function()
		for _ = 1, 8 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", enabled)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
end

-- ------------------------------------------------------------ 벽 숨기기
local function setWallsHidden(hidden: boolean)
	if wallsHidden == hidden then
		return
	end
	local rofly = Workspace:FindFirstChild("Rofly")
	local rocket = rofly and rofly:FindFirstChild("Rocket")
	local walls = rocket and rocket:FindFirstChild("Walls")
	if not walls then
		return
	end
	wallsHidden = hidden
	for _, panel in ipairs(walls:GetChildren()) do
		if panel:IsA("BasePart") then
			local angle = panel:GetAttribute("AngleDeg")
			if typeof(angle) == "number" and math.abs(angle - 180) <= HIDE_HALF_ANGLE then
				panel.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

-- ------------------------------------------------------------ 카메라 위치
local function seatRows(): number
	local count = math.max(State.number("CrewCount"), 1)
	local perRow = math.min(W.SeatsPerRowMax, math.ceil(math.sqrt(count * 2.5)))
	return math.ceil(count / perRow)
end

local function interiorCFrame(): CFrame
	local extra = math.max(0, seatRows() - 2)
	local position = Vector3.new(0, W.CabinFloorY + 17.5 + extra * 3.5, -(W.HullRadius + 10 + extra * 6))
	local target = Vector3.new(0, W.CabinFloorY + 11 + extra * 3, W.CabinRadius)
	return CFrame.lookAt(position, target)
end

local function exteriorCFrame(): CFrame
	return CFrame.lookAt(Vector3.new(130, 90, 205), Vector3.new(0, 128, 0))
end

local function seatPosition(seat: number): Vector3?
	local rofly = Workspace:FindFirstChild("Rofly")
	local rocket = rofly and rofly:FindFirstChild("Rocket")
	local seats = rocket and rocket:FindFirstChild("Seats")
	local model = seats and seats:FindFirstChild("Seat" .. tostring(seat))
	local pad = model and model:FindFirstChild("Pad")
	if pad and pad:IsA("BasePart") then
		return pad.Position
	end
	return nil
end

local function closeupCFrame(seat: number): CFrame?
	local position = seatPosition(seat)
	if not position then
		return nil
	end
	local flat = Vector3.new(-position.X, 0, -position.Z)
	if flat.Magnitude < 0.01 then
		return nil
	end
	local inward = flat.Unit
	local eye = position + inward * 10 + Vector3.new(0, 5.5, 0)
	return CFrame.lookAt(eye, position + Vector3.new(0, 3, 0))
end

-- 내 캐릭터에 테두리를 둘러 어디 앉았는지 보이게 함
local function updateHighlight(aboard: boolean)
	local character = player.Character
	if aboard and character and State.role() == "Crew" then
		if not highlight or highlight.Parent ~= character then
			if highlight then
				highlight:Destroy()
			end
			local created = Instance.new("Highlight")
			created.Name = "RoflyMe"
			created.FillTransparency = 1
			created.OutlineColor = C.Cyan
			created.OutlineTransparency = 0.1
			created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			created.Parent = character
			highlight = created
		end
	elseif highlight then
		highlight:Destroy()
		highlight = nil
	end
end

function CameraRig.addShake(amount: number)
	shake = math.min(1.5, math.max(shake, amount))
end

function CameraRig.closeup(seat: number, seconds: number)
	if seat > 0 then
		closeupSeat = seat
		closeupUntil = os.clock() + seconds
	end
end

function CameraRig.view(): string
	return view
end

function CameraRig.init()
	local _, root = Ui.screen("RoflyCamera", 11)
	viewButton = Ui.button(root, "ViewButton", "시점: 선실", 18, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(150, 40),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	Ui.stroke(viewButton, C.Line, 2, 0)
	viewButton.Activated:Connect(function()
		view = if view == "Interior" then "Exterior" else "Interior"
		viewButton.Text = if view == "Interior" then "시점: 선실" else "시점: 바깥"
		closeupUntil = 0
		State.emit("Sound", "Press")
	end)

	State.on("Phase", function(phase: string)
		if phase == "Countdown" then
			-- 카운트다운 시작: 선장 클로즈업
			CameraRig.closeup(State.number("CaptainSeat"), Config.Captain.CloseupSeconds)
		elseif phase == "Build" then
			view = "Interior"
			viewButton.Text = "시점: 선실"
		end
	end)
	State.on("Launched", function()
		CameraRig.addShake(1.2)
	end)
	State.on("ItemUsed", function(info: any)
		if type(info) == "table" and type(info.seat) == "number" then
			CameraRig.closeup(info.seat, Config.Rescue.CloseupSeconds)
			CameraRig.addShake(0.8)
		end
	end)
	State.on("MissionFx", function(rate: number)
		if rate >= Config.Mission.ComboRule then
			CameraRig.addShake(0.35)
		end
	end)
	State.on("FlightEnd", function(info: any)
		if type(info) == "table" and not info.escaped then
			CameraRig.addShake(1.5)
		end
	end)
end

function CameraRig.update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local aboard = State.aboard()
	viewButton.Visible = aboard
	updateHighlight(aboard)

	if not aboard then
		if scripted then
			scripted = false
			setWallsHidden(false)
			setMovement(true)
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = FIELD_OF_VIEW
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		return
	end

	if not scripted then
		scripted = true
		setMovement(false)
		shake = 0
	end
	-- 캐릭터가 새로 생기면 엔진이 카메라를 기본으로 되돌리므로 매번 다시 맞춤
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local clock = os.clock()
	local target: CFrame? = nil
	local inCloseup = clock < closeupUntil
	if inCloseup then
		target = closeupCFrame(closeupSeat)
	end
	if target == nil then
		inCloseup = false
		target = if view == "Interior" then interiorCFrame() else exteriorCFrame()
	end
	setWallsHidden(view == "Interior" and not inCloseup)

	-- 흔들림: 발사·미션 성공·위기 때 크게, 비행 중에는 엔진 떨림만 약하게
	shake = math.max(0, shake - dt * 1.6)
	local rumble = 0
	if State.phase() == "Flight" then
		rumble = if State.flag("Crisis") then 0.3 else 0.1
	end
	local strength = shake * shake + rumble * rumble
	local cframe = target :: CFrame
	if strength > 0.0001 then
		local t = clock * 19
		local pitch = math.noise(t, 1.7) * 0.05 * strength
		local yaw = math.noise(t, 9.2) * 0.05 * strength
		local roll = math.noise(t, 21.4) * 0.03 * strength
		cframe = cframe * CFrame.Angles(pitch, yaw, roll)
	end
	camera.CFrame = cframe
	camera.FieldOfView = FIELD_OF_VIEW
end

return CameraRig
