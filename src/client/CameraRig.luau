-- 카메라와 조작: 로켓에 타 있는 동안(승무원·관전자)과 발사장에 있을 때를 나눠 맡습니다.
--  · 선실 시점(기본): Roblox 기본 카메라가 내 캐릭터를 따라갑니다. 승무원은 선실 안을 걸어다니고,
--    관전자는 천장 가까이 떠 있는 자리에서 둘러봅니다. 카메라는 선실 벽 너머로 멀어지지 않게 최대 거리를 줄입니다.
--  · 바깥 시점: 오른쪽 위 '시점' 버튼으로 바꾸는 연출 카메라 (로켓을 밖에서 봄)
--  · 클로즈업: 카운트다운 시작 때 선장, 부스터를 쓴 사람을 잠깐 비춤 (그 사람이 선실 어디에 있든 따라감)
-- 승무원은 내 미션 입력을 받는 동안만 걷기·점프가 잠기고(방향키·스페이스가 미션 입력이 되도록), 관전자는 늘 잠깁니다.
-- 타 있는 동안은 캐릭터 초기화 버튼을 막습니다.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cabin = require(Shared:WaitForChild("Cabin"))
local Config = require(Shared:WaitForChild("Config"))

local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local CameraRig = {}

local W = Config.World
local C = Ui.Colors
local player = Players.LocalPlayer

local FIELD_OF_VIEW = 70
local HANDOVER_LOCK = 4 -- 판이 끝난 뒤 새 캐릭터를 기다리며 조작을 잠가 두는 최대 시간(초)
local HANDOVER_MAX = 20 -- 새 캐릭터를 기다리며 발사장을 비추는 최대 시간(초). 넘으면 기본 카메라로 넘김
local CLOSEUP_DISTANCE = 9 -- 클로즈업 카메라가 그 사람 머리에서 떨어진 거리(스터드)
local OFFSET_SHAKE = 12 -- 선실 시점(기본 카메라)의 흔들림: 연출 카메라의 흔들림 각도(라디안)를 이 거리(스터드)만큼 옮겨 비슷하게 보임
local ROCKET_CENTER = Vector3.new(0, 128, 0) -- 바깥 시점에서 조명 초점을 맞추는 곳 (로켓 가운데쯤)

local view = "Interior" -- "Interior" 선실 | "Exterior" 바깥
local managed = false -- 타 있는 동안 이 모듈이 카메라를 맡고 있음 (내리면 판 끝 넘기기를 거쳐 기본 카메라로 돌려줌)
local shake = 0
local closeupSeat = 0
local closeupUntil = 0
local viewButton: TextButton
local controls: any = nil
local highlight: Highlight? = nil
local revealAt = 0
local handover = false
local handoverFrom: Model? = nil
local handoverStart = 0
local subjectPending = false -- 기다리다 넘긴 뒤, 늦게 나타날 새 캐릭터를 카메라가 따라가게 해야 하는지
local movementLocked = false -- 지금 바라는 조작 잠금 상태
local resetBlocked = false -- 지금 바라는 초기화 버튼 상태 (타 있는 동안 true = 막음)
local resetApplied: boolean? = nil -- 초기화 버튼에 마지막으로 적용한 값 (nil = 아직 적용한 적 없음)
local resetSyncing = false -- 초기화 버튼을 맞추는 반복이 돌고 있는지
local lobbyMaxZoom: number? = nil -- 발사장에서 쓰는 원래 최대 확대 거리
local offsetHumanoid: Humanoid? = nil -- 흔들림을 넣어 둔 Humanoid (CameraOffset 을 되돌릴 대상)

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

-- 캐릭터 초기화 버튼을 지금 바라는 상태(타 있으면 막음)로 맞춤. 클라이언트가 막 시작했을 때는 SetCore 가
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
			local want = not resetBlocked
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

-- 타 있는 동안 캐릭터 초기화를 막음 (선실 밖 발사장으로 리스폰되지 않게). 상태가 바뀔 때만 일합니다.
local function blockReset(blocked: boolean)
	if resetBlocked == blocked then
		return
	end
	resetBlocked = blocked
	syncResetButton()
end

-- 걷기·점프를 잠그거나 풉니다. 상태가 바뀔 때만 일합니다.
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
	-- 기본 터치 조작(이동 스틱·점프 버튼)은 잠긴 동안 숨김 (미션 입력 중에는 그 자리에 미션 버튼이 뜸)
	pcall(function()
		GuiService.TouchControlsEnabled = not locked
	end)
end

-- 선실 안에서는 카메라가 캐릭터에서 멀리 빠지지 않게 최대 거리를 줄이고, 내리면 원래대로 되돌림
local function setCabinZoom(aboard: boolean)
	if lobbyMaxZoom == nil then
		return
	end
	local want = if aboard then math.min(W.CabinMaxZoom, lobbyMaxZoom :: number) else lobbyMaxZoom :: number
	if player.CameraMaxZoomDistance ~= want then
		pcall(function()
			player.CameraMaxZoomDistance = want
		end)
	end
end

-- 기본 카메라의 흔들림(Humanoid.CameraOffset)을 지움
local function clearOffset()
	local humanoid = offsetHumanoid
	if humanoid then
		offsetHumanoid = nil
		if humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
		end
	end
end

-- ------------------------------------------------------------ 카메라 위치
local function exteriorCFrame(): CFrame
	-- 조금 멀리서 로켓 전체와 그 아래로 길게 흐르는 추진운이 함께 보이게 (자리와 바라보는 높이는 Config.World.OutsideCamera)
	local at = W.OutsideCamera
	return CFrame.lookAt(Vector3.new(at[1], at[2], at[3]), Vector3.new(0, at[4], 0))
end

-- 발사장 리스폰 지점을 뒤에서 비추는 자리 (새 캐릭터가 나타났을 때 기본 카메라가 잡는 구도와 비슷하게)
local function padCFrame(): CFrame
	return CFrame.lookAt(Vector3.new(0, 9, W.SpawnDistance + 12), Vector3.new(0, 5, W.SpawnDistance))
end

-- 승무원 번호 seat 인 사람(봇)을 앞에서 비추는 자리와 그 사람 머리 위치. 그 사람이 벽을 보고 있으면 선실 가운데 쪽에서 비춤.
local function closeupCFrame(seat: number): (CFrame?, Vector3)
	local head = State.memberPart(seat)
	if not head then
		return nil, Vector3.zero
	end
	local at = head.Position
	local look = head.CFrame.LookVector
	local directions: { Vector3 } = {}
	local front = Vector3.new(look.X, 0, look.Z)
	if front.Magnitude > 0.01 then
		table.insert(directions, front.Unit)
	end
	local inward = Vector3.new(-at.X, 0, -at.Z)
	if inward.Magnitude > 0.01 then
		table.insert(directions, inward.Unit)
	end
	for _, direction in ipairs(directions) do
		local eye = at + direction * CLOSEUP_DISTANCE + Vector3.new(0, 2, 0)
		if Cabin.contains(eye, -2) then -- 벽에서 2 스터드 넘게 안쪽만
			return CFrame.lookAt(eye, at - Vector3.new(0, 0.5, 0)), at
		end
	end
	-- 선실 가운데 가까이 서 있으면(방향을 못 정함) 위에서 비스듬히
	return CFrame.lookAt(at + Vector3.new(0, 6, CLOSEUP_DISTANCE * 0.6), at), at
end

-- 연출 카메라로 바꿨을 때 1인칭 근처까지 다가가 있던 기본 카메라가 내 캐릭터를 투명하게 만든 채 멈추므로, 다시 보이게 함
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

-- 내 캐릭터에 테두리를 둘러 여러 사람 사이에서도 내가 어디 있는지 보이게 함
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
	lobbyMaxZoom = player.CameraMaxZoomDistance
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

-- 흔들림: 발사·미션 성공·위기 때 크게, 비행 중에는 엔진 떨림만 약하게, 대기권에서는 마찰 열만큼.
-- 돌려줌: 연출 카메라에 곱할 회전·이동, 기본 카메라에 줄 이동(Humanoid.CameraOffset)
local function shakeAmount(dt: number, clock: number): (CFrame, Vector3)
	shake = math.max(0, shake - dt * 1.6)
	local rumble = 0
	if State.phase() == "Flight" then
		rumble = if State.flag("Crisis") then 0.3 else 0.1
	end
	local strength = shake * shake + rumble * rumble
	local turn = CFrame.new()
	local offset = Vector3.zero
	if strength > 0.0001 then
		local t = clock * 19
		local pitch = math.noise(t, 1.7) * 0.05 * strength
		local yaw = math.noise(t, 9.2) * 0.05 * strength
		local roll = math.noise(t, 21.4) * 0.03 * strength
		turn = CFrame.Angles(pitch, yaw, roll)
		offset = Vector3.new(yaw, pitch, 0) * OFFSET_SHAKE
	end
	-- 대기권 마찰 흔들림: 뜨거울수록 크게 (선실·바깥 시점 모두). 대기권을 벗어나면 멈춤.
	local heat = State.heat
	if heat > 0.001 then
		local t = clock * 23
		local angle = math.rad(Config.Atmosphere.ShakeDeg) * heat
		local move = Config.Atmosphere.ShakeStuds * heat
		local mx, my = math.noise(t, 31.7) * 2 * move, math.noise(t, 47.3) * 2 * move
		local ax, ay = math.noise(t, 5.3) * 2 * angle, math.noise(t, 13.9) * 2 * angle
		turn = turn * CFrame.new(mx, my, 0) * CFrame.Angles(ax, ay, math.noise(t, 61.1) * angle)
		offset += Vector3.new(mx + ay * OFFSET_SHAKE, my + ax * OFFSET_SHAKE, 0)
	end
	return turn, offset
end

function CameraRig.update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local aboard = State.aboard()
	viewButton.Visible = aboard
	updateHighlight(aboard)
	setCabinZoom(aboard)

	if not aboard then
		clearOffset()
		if managed then
			-- 판이 끝나면 서버가 캐릭터를 새로 만들어 발사장에 놓습니다. 새 캐릭터가 나타나기 전에 기본 카메라로
			-- 넘기면 따라갈 대상이 없어 빈 선실이나 선체 벽이 잠깐 보이므로, 나타날 때까지 발사장을 비춥니다.
			local clock = os.clock()
			if not handover then
				handover = true
				handoverFrom = player.Character
				handoverStart = clock
				lockMovement(true)
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			-- 새 캐릭터인지: 판 중의 캐릭터와 다르거나, 선실 밖(발사장)에 있으면 새 캐릭터로 봄
			local fresh = character ~= handoverFrom or (rootPart ~= nil and rootPart:IsA("BasePart") and not Cabin.contains(rootPart.Position, 2))
			local arrived = character ~= nil and humanoid ~= nil and fresh and character:IsDescendantOf(Workspace)
			local waited = clock - handoverStart
			if not arrived and waited < HANDOVER_MAX then
				-- 아바타를 불러오는 데 오래 걸려도 조작 잠금은 길게 끌지 않음
				if waited >= HANDOVER_LOCK then
					lockMovement(false)
					blockReset(false)
				end
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Scriptable
				end
				camera.CFrame = padCFrame()
				camera.Focus = CFrame.new(0, 5, W.SpawnDistance)
				camera.FieldOfView = FIELD_OF_VIEW
				return
			end
			managed = false
			handover = false
			handoverFrom = nil
			lockMovement(false)
			blockReset(false)
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
	managed = true
	blockReset(true)
	-- 관전자는 늘, 승무원은 내 미션 입력을 받는 동안만 걷기·점프를 잠금 (넘기는 중에 풀렸다가 다음 판이 시작돼도 다시 맞춰짐)
	lockMovement(State.role() ~= "Crew" or State.missionInput)

	local clock = os.clock()
	local turn, offset = shakeAmount(dt, clock)
	local target: CFrame? = nil
	local focus = ROCKET_CENTER
	if clock < closeupUntil then
		target, focus = closeupCFrame(closeupSeat)
	end
	if target == nil and view == "Exterior" then
		target = exteriorCFrame()
		focus = ROCKET_CENTER
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if target == nil then
		-- 선실 시점: 기본 카메라가 내 캐릭터를 따라감. 캐릭터가 새로 생기면 따라갈 대상을 다시 맞춤
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if humanoid and camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
		camera.FieldOfView = FIELD_OF_VIEW
		-- 기본 카메라는 매 프레임 자기 방향을 다시 읽으므로 회전을 더하면 쌓임. 그래서 이동(CameraOffset)으로만 흔듦
		if humanoid then
			if offsetHumanoid ~= humanoid then
				clearOffset()
				offsetHumanoid = humanoid
			end
			humanoid.CameraOffset = offset
		end
		return
	end

	-- 연출 카메라 (바깥 시점·클로즈업)
	clearOffset()
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if clock >= revealAt then
		revealAt = clock + 0.25
		revealCharacter()
	end
	camera.CFrame = (target :: CFrame) * turn
	-- 연출 카메라에서는 엔진이 초점(Focus)을 옮겨 주지 않음. 조명이 제대로 그려지게 비추는 곳(그 사람·로켓)으로 맞춤.
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = FIELD_OF_VIEW
end

return CameraRig
