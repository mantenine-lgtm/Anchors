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
local BOARD_FRAME = 0.6 -- 전광판 테두리가 화면 아래로 더 나온 길이(스터드)
local HANDOVER_LOCK = 4 -- 판이 끝난 뒤 새 캐릭터를 기다리며 조작을 잠가 두는 최대 시간(초)
local HANDOVER_MAX = 20 -- 새 캐릭터를 기다리며 발사장을 비추는 최대 시간(초). 넘으면 기본 카메라로 넘김

local view = "Interior" -- "Interior" 선실 | "Exterior" 바깥
local scripted = false
local wallsHidden = false
local shake = 0
local closeupSeat = 0
local closeupUntil = 0
local viewButton: TextButton
local controls: any = nil
local highlight: Highlight? = nil
local revealAt = 0
local boardPart: BasePart? = nil
local handover = false
local handoverFrom: Model? = nil
local handoverStart = 0
local subjectPending = false -- 기다리다 넘긴 뒤, 늦게 나타날 새 캐릭터를 카메라가 따라가게 해야 하는지
local movementLocked = false -- 지금 바라는 조작 상태 (타 있는 동안 true)
local resetApplied: boolean? = nil -- 초기화 버튼에 마지막으로 적용한 값 (nil = 아직 적용한 적 없음)
local resetSyncing = false -- 초기화 버튼을 맞추는 반복이 돌고 있는지

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

-- 캐릭터 초기화 버튼을 지금 바라는 상태(타 있으면 끔)로 맞춤. 클라이언트가 막 시작했을 때는 SetCore 가
-- 실패하므로 0.5초마다 다시 해 봅니다(8번 실패하면 그만둠). 반복은 하나만 돌고, 돌 때마다 바라는 상태를
-- 새로 읽으므로 그 사이에 여러 번 바뀌어도 마지막 상태로 맞춰집니다.
local function syncResetButton()
	if resetSyncing then
		return
	end
	resetSyncing = true
	task.spawn(function()
		local failures = 0
		while true do
			local want = not movementLocked
			if resetApplied == want then
				break
			end
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", want)
			end)
			if ok then
				resetApplied = want
			else
				failures += 1
				if failures >= 8 then
					break
				end
				task.wait(0.5)
			end
		end
		resetSyncing = false
	end)
end

-- 타 있는 동안 이동·점프·캐릭터 초기화를 잠그고, 내리면 풉니다. 상태가 바뀔 때만 일합니다.
local function lockMovement(locked: boolean)
	if movementLocked == locked then
		return
	end
	movementLocked = locked
	task.spawn(function()
		local c = getControls()
		if c then
			pcall(function()
				-- 조작 모듈을 기다리는 사이에 다시 바뀌었을 수 있으므로 지금 바라는 상태로 맞춤
				if movementLocked then
					c:Disable()
				else
					c:Enable()
				end
			end)
		end
	end)
	-- 기본 터치 조작(이동 스틱·점프 버튼)이 미션 버튼과 겹치지 않게 숨김
	pcall(function()
		GuiService.TouchControlsEnabled = not locked
	end)
	-- 타 있는 동안 캐릭터 초기화를 막음 (자리에서 떨어지지 않게)
	syncResetButton()
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
	-- 조금 멀리서 로켓 전체와 그 아래로 길게 흐르는 추진운이 함께 보이게 (자리와 바라보는 높이는 Config.World.OutsideCamera)
	local at = W.OutsideCamera
	return CFrame.lookAt(Vector3.new(at[1], at[2], at[3]), Vector3.new(0, at[4], 0))
end

-- 발사장 리스폰 지점을 뒤에서 비추는 자리 (새 캐릭터가 나타났을 때 기본 카메라가 잡는 구도와 비슷하게)
local function padCFrame(): CFrame
	return CFrame.lookAt(Vector3.new(0, 9, W.SpawnDistance + 12), Vector3.new(0, 5, W.SpawnDistance))
end

local function findBoard(): BasePart?
	if boardPart and boardPart.Parent then
		return boardPart
	end
	local rofly = Workspace:FindFirstChild("Rofly")
	local rocket = rofly and rofly:FindFirstChild("Rocket")
	local board = rocket and rocket:FindFirstChild("Board")
	if board and board:IsA("BasePart") then
		boardPart = board
		return board
	end
	return nil
end

-- 선실 시점에서 전광판(테두리 포함) 아래 끝이 화면 높이의 어디에 오는지 (0 = 맨 위, 1 = 맨 아래).
-- 카메라의 세로 시야각은 창 모양과 상관없이 같으므로 이 비율은 창이 넓든 좁든 같습니다.
-- (휴대폰은 화면 글자가 안전 영역 안에만 그려져 비율이 조금 다른데, 그 변환은 Hud 가 합니다.)
-- 승무원 수에 따라 카메라 자리가 달라져도 따라갑니다.
local function boardBottom(): number
	local board = findBoard()
	if not board then
		return State.BoardBottomDefault
	end
	local cameraCFrame = interiorCFrame()
	local half = board.Size / 2
	local tangent = math.tan(math.rad(FIELD_OF_VIEW / 2))
	local lowest = 0
	for _, side in ipairs({ -1, 1 }) do
		local corner = board.CFrame * Vector3.new(side * half.X, -half.Y - BOARD_FRAME, -half.Z)
		local point = cameraCFrame:PointToObjectSpace(corner)
		if point.Z > -1 then
			return State.BoardBottomDefault -- 카메라 뒤쪽이면 계산하지 않음
		end
		lowest = math.max(lowest, 0.5 - (point.Y / -point.Z) / (2 * tangent))
	end
	return math.clamp(lowest, 0.1, 0.6)
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

-- 1인칭까지 확대한 채로 타면 기본 카메라가 내 캐릭터를 투명하게 만든 채 멈추므로, 다시 보이게 함
local function revealCharacter()
	local character = player.Character
	if not character then
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 0
		end
	end
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
	-- 발사장에서 1인칭까지 확대하면 마우스가 화면 가운데에 묶여 탑승 버튼을 누를 수 없으므로 막음
	pcall(function()
		player.CameraMinZoomDistance = 6
	end)
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
		elseif phase == "Build" or phase == "Join" then
			-- 새 판: 선실 시점으로 되돌리고, 지난 판의 클로즈업이 남아 있으면 지움
			view = "Interior"
			viewButton.Text = "시점: 선실"
			closeupUntil = 0
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
		State.boardBottom = State.BoardBottomDefault
		if scripted then
			-- 판이 끝나면 서버가 캐릭터를 새로 만들어 발사장에 놓습니다. 새 캐릭터가 나타나기 전에 기본 카메라로
			-- 넘기면 따라갈 대상이 없어 빈 선실이나 선체 벽이 잠깐 보이므로, 나타날 때까지 발사장을 비춥니다.
			local clock = os.clock()
			if not handover then
				handover = true
				handoverFrom = player.Character
				handoverStart = clock
				setWallsHidden(false)
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			-- 새 캐릭터인지: 판 중의 캐릭터와 다르거나, 좌석에 고정돼 있지 않으면 새 캐릭터로 봄
			local fresh = character ~= handoverFrom or (rootPart ~= nil and rootPart:IsA("BasePart") and not rootPart.Anchored)
			local arrived = character ~= nil and humanoid ~= nil and fresh and character:IsDescendantOf(Workspace)
			local waited = clock - handoverStart
			if not arrived and waited < HANDOVER_MAX then
				-- 아바타를 불러오는 데 오래 걸려도 조작 잠금은 길게 끌지 않음
				if waited >= HANDOVER_LOCK then
					lockMovement(false)
				end
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Scriptable
				end
				camera.CFrame = padCFrame()
				camera.Focus = CFrame.new(0, 5, W.SpawnDistance)
				camera.FieldOfView = FIELD_OF_VIEW
				return
			end
			scripted = false
			handover = false
			handoverFrom = nil
			lockMovement(false)
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = FIELD_OF_VIEW
			if arrived and humanoid then
				camera.CameraSubject = humanoid
			end
			-- 끝내 나타나지 않아 그냥 넘겼으면, 나중에 나타났을 때 카메라가 따라가게 표시해 둠
			subjectPending = not arrived
		elseif subjectPending then
			-- 엔진이 새 캐릭터로 카메라를 알아서 돌려 주는지는 문서에 없어서, 따라갈 대상이 비었거나 사라진 것이면 직접 맞춤
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid and character:IsDescendantOf(Workspace) then
				subjectPending = false
				local subject = camera.CameraSubject
				if subject == nil or not subject:IsDescendantOf(Workspace) then
					camera.CameraSubject = humanoid
				end
			end
		end
		return
	end
	subjectPending = false
	handover = false
	handoverFrom = nil
	State.boardBottom = boardBottom()

	if not scripted then
		scripted = true
		shake = 0
		revealAt = 0
	end
	lockMovement(true) -- 넘기는 중에 풀렸다가 바로 다음 판이 시작된 경우에도 다시 잠김
	-- 캐릭터가 새로 생기면 엔진이 카메라를 기본으로 되돌리므로 매번 다시 맞춤
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local clock = os.clock()
	if clock >= revealAt then
		revealAt = clock + 0.25
		revealCharacter()
	end
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
	-- 대기권 마찰 흔들림: 뜨거울수록 크게 (선실·바깥 시점 모두). 대기권을 벗어나면 멈춤.
	local heat = State.heat
	if heat > 0.001 then
		local t = clock * 23
		local angle = math.rad(Config.Atmosphere.ShakeDeg) * heat
		local move = Config.Atmosphere.ShakeStuds * heat
		cframe = cframe
			* CFrame.new(math.noise(t, 31.7) * 2 * move, math.noise(t, 47.3) * 2 * move, 0)
			* CFrame.Angles(math.noise(t, 5.3) * 2 * angle, math.noise(t, 13.9) * 2 * angle, math.noise(t, 61.1) * angle)
	end
	camera.CFrame = cframe
	-- 연출 카메라에서는 엔진이 초점(Focus)을 옮겨 주지 않음. 선실 조명이 제대로 그려지게 선실로 맞춤.
	camera.Focus = CFrame.new(0, W.CabinFloorY + 11, 0)
	camera.FieldOfView = FIELD_OF_VIEW
end

return CameraRig
