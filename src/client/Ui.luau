-- 화면(UI)을 코드로 만들 때 쓰는 도구 모음. 이미지 없이 Frame 과 글자만으로 그립니다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Colors = {
	Text = Color3.fromRGB(240, 244, 255),
	Dim = Color3.fromRGB(168, 176, 196),
	Panel = Color3.fromRGB(14, 17, 26),
	PanelLight = Color3.fromRGB(34, 40, 58),
	Line = Color3.fromRGB(70, 80, 110),
	Cyan = Color3.fromRGB(70, 220, 255),
	Green = Color3.fromRGB(90, 235, 140),
	Yellow = Color3.fromRGB(255, 214, 74),
	Orange = Color3.fromRGB(255, 150, 60),
	Red = Color3.fromRGB(255, 76, 76),
	Pink = Color3.fromRGB(255, 110, 170),
	Purple = Color3.fromRGB(170, 120, 255),
	Black = Color3.fromRGB(0, 0, 0),
	White = Color3.fromRGB(255, 255, 255),
}

Ui.Font = Enum.Font.GothamBold
Ui.FontLight = Enum.Font.GothamMedium

-- 기준 화면 높이. 화면이 이보다 작으면 전체를 같은 비율로 줄입니다.
Ui.RefWidth = 1280
Ui.RefHeight = 720

-- 인스턴스를 만들고 속성을 한 번에 넣음 (Parent 는 맨 마지막에)
function Ui.make(className: string, props: { [string]: any }?): any
	local instance: any = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Ui.corner(parent: Instance, radius: number)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

function Ui.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return Ui.make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.frame(parent: Instance, name: string, props: { [string]: any }?): Frame
	local frame = Ui.make("Frame", {
		Name = name,
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	if props then
		for key, value in pairs(props) do
			(frame :: any)[key] = value
		end
	end
	frame.Parent = parent
	return frame
end

-- 반투명 판 (둥근 모서리)
function Ui.panel(parent: Instance, name: string, props: { [string]: any }?): Frame
	local frame = Ui.frame(parent, name, { BackgroundTransparency = 0.25 })
	Ui.corner(frame, 12)
	if props then
		for key, value in pairs(props) do
			(frame :: any)[key] = value
		end
	end
	return frame
end

function Ui.label(parent: Instance, name: string, text: string, size: number, props: { [string]: any }?): TextLabel
	local label = Ui.make("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Ui.Font,
		Text = text,
		TextSize = size,
		TextColor3 = Ui.Colors.Text,
		TextStrokeColor3 = Ui.Colors.Black,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	if props then
		for key, value in pairs(props) do
			(label :: any)[key] = value
		end
	end
	label.Parent = parent
	return label
end

-- 글자 크기(TextSize)는 100 까지만 되므로, 그보다 큰 글자는 UIScale 로 키웁니다.
-- 위치와 크기는 바깥 틀(이름 + "Holder")이 갖고, 돌려주는 글자는 그 틀을 꽉 채웁니다.
-- Position 은 비율(Scale)로만 주세요.
local HOLDER_PROPS = { AnchorPoint = true, Position = true, Size = true, ZIndex = true }

function Ui.bigLabel(parent: Instance, name: string, text: string, size: number, props: { [string]: any }?): TextLabel
	local factor = math.max(size / 100, 1)
	local holder = Ui.frame(parent, name .. "Holder", {})
	local labelProps: { [string]: any } = {}
	if props then
		for key, value in pairs(props) do
			if HOLDER_PROPS[key] then
				(holder :: any)[key] = value
			else
				labelProps[key] = value
			end
		end
	end
	local full = holder.Size
	holder.Size = UDim2.new(full.X.Scale / factor, full.X.Offset / factor, full.Y.Scale / factor, full.Y.Offset / factor)
	Ui.make("UIScale", { Scale = factor, Parent = holder })
	return Ui.label(holder, name, text, size / factor, labelProps)
end

function Ui.button(parent: Instance, name: string, text: string, size: number, color: Color3, props: { [string]: any }?): TextButton
	local button = Ui.make("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Ui.Font,
		Text = text,
		TextSize = size,
		TextColor3 = Ui.Colors.Text,
		TextStrokeColor3 = Ui.Colors.Black,
		TextStrokeTransparency = 0.6,
	})
	Ui.corner(button, 12)
	if props then
		for key, value in pairs(props) do
			(button :: any)[key] = value
		end
	end
	button.Parent = parent
	return button
end

-- 화면 하나: ScreenGui + 기준 해상도로 맞춘 바탕 Frame.
-- 돌려주는 root 안에서는 1280x720 기준 픽셀로 배치하면 됩니다 (가로로 긴 화면은 더 넓어짐).
function Ui.screen(name: string, displayOrder: number): (ScreenGui, Frame)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Ui.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local root = Ui.frame(gui, "Root", { Size = UDim2.fromScale(1, 1) })
	local scale = Ui.make("UIScale", { Parent = root })
	local function fit()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local s = math.clamp(math.min(size.X / Ui.RefWidth, size.Y / Ui.RefHeight), 0.3, 2)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	gui.Parent = playerGui
	fit()
	return gui, root
end

-- 화살표: 막대 3개로 그림. direction = "Up" | "Down" | "Left" | "Right"
local ARROW_ROTATION = { Up = 0, Right = 90, Down = 180, Left = 270 }

function Ui.arrow(parent: Instance, direction: string, color: Color3): Frame
	local holder = Ui.frame(parent, "Arrow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		Rotation = ARROW_ROTATION[direction] or 0,
	})
	Ui.make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
	local function bar(position: UDim2, size: UDim2, rotation: number)
		local part = Ui.frame(holder, "Bar", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			Rotation = rotation,
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
		})
		Ui.corner(part, 4)
	end
	bar(UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.17, 0.8), 0) -- 기둥
	bar(UDim2.fromScale(0.3, 0.36), UDim2.fromScale(0.17, 0.62), 45) -- 왼쪽 날
	bar(UDim2.fromScale(0.7, 0.36), UDim2.fromScale(0.17, 0.62), -45) -- 오른쪽 날
	return holder
end

-- 화살표·하트의 색을 한 번에 바꿈
function Ui.tint(holder: Instance, color: Color3)
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end
end

-- 하트: 원 2개 + 마름모 1개
function Ui.heart(parent: Instance, sizePx: number, color: Color3): Frame
	local holder = Ui.frame(parent, "Heart", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
	})
	local function piece(position: UDim2, size: UDim2, rotation: number, round: boolean)
		local part = Ui.frame(holder, "Piece", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			Rotation = rotation,
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
		})
		if round then
			Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = part })
		end
	end
	piece(UDim2.fromScale(0.3, 0.34), UDim2.fromScale(0.5, 0.5), 0, true)
	piece(UDim2.fromScale(0.7, 0.34), UDim2.fromScale(0.5, 0.5), 0, true)
	piece(UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.5, 0.5), 45, false)
	return holder
end

function Ui.tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

-- 가로 게이지: 바탕 + 채움. 돌려주는 함수에 0~1 을 넣으면 채움이 바뀜.
function Ui.bar(parent: Instance, name: string, color: Color3, props: { [string]: any }?): (Frame, Frame)
	local back = Ui.frame(parent, name, {
		BackgroundColor3 = Ui.Colors.Black,
		BackgroundTransparency = 0.45,
	})
	Ui.corner(back, 6)
	if props then
		for key, value in pairs(props) do
			(back :: any)[key] = value
		end
	end
	local fill = Ui.frame(back, "Fill", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0, 1),
	})
	Ui.corner(fill, 6)
	return back, fill
end

return Ui
