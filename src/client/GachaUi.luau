-- 부품 뽑기 화면 (Nick 11-28 "부품 뽑기도 추가", "발사 전에 뽑을 수 있게"). 규칙·수치는 Config.Gacha, 서버는 GachaService.
-- 오른쪽 위 버튼 줄(시점·디버그 아래)의 '부품 뽑기' 버튼으로 엽니다. 탑승 대기·조립·정산 때만 보이고 카운트다운·비행이 되면 닫힘.
-- 화면: 부품 종류 탭 6개 → 지금 그 종류 부품(아이콘·이름·레어도·★·레벨) → 뽑기 하나(확률, 1회·10회 버튼).
-- 값은 내 최고 기록 km × Config.Gacha.PricePerKm (Nick 11-28 "일반 고급 최고급 넣지 말고 뽑기 일괄").
-- 뽑으면 캡슐이 흔들린 뒤 결과 카드가 하나씩 열림 (10회는 11장). 결과마다 '새 부품!' / '★ 돌파' / '경험치 +N'.
-- '도감' 은 그 종류 50개(일반 15·희귀 15·영웅 12·전설 8, 모두 300개)를 레어도 버튼으로 나눠 한 번에 15칸까지 보여 줌
-- (휴대폰 사양: 아이콘을 한꺼번에 많이 만들지 않음). 모은 것은 그림과 이름, 못 모은 것은 그림자와 '?'.
-- 지금 부품과 레어도가 같은 모은 부품을 누르면 그 모양으로 바꿔 낌 (능력치는 같음).
-- 누가 전설을 뽑으면 모두의 화면 위쪽에 알림이 뜨고, 다른 사람은 '축하' 를 누를 수 있음 (누른 사람 코인 +50).
-- 뽑은 사람은 결과 화면에 '모두에게 알렸어요 · 축하 N' 이 뜸 (위쪽 알림이 결과 제목을 가리지 않게).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Fmt = require(Shared:WaitForChild("Fmt"))
local Gacha = require(Shared:WaitForChild("Gacha"))
local Leveling = require(Shared:WaitForChild("Leveling"))
local Net = require(Shared:WaitForChild("Net"))

local BuildUi = require(script.Parent:WaitForChild("BuildUi"))
local PartIcon = require(script.Parent:WaitForChild("PartIcon"))
local State = require(script.Parent:WaitForChild("State"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local GachaUi = {}

local C = Ui.Colors
local G = Config.Gacha
local RARITY_NAMES = Config.Parts.RarityNames
local GOLD = Color3.fromRGB(255, 200, 60)
local DARK = Color3.fromRGB(10, 12, 20)

-- 배치 (1280x720 기준 픽셀)
local BUTTON_TOP = 152 -- 오른쪽 위 버튼 줄: 시점(60) · 디버그(108) 아래
local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 48
local PANEL_WIDTH = 900
local PANEL_HEIGHT = 610
local PAD = 16
local TAB_TOP = 60
local TAB_HEIGHT = 60
local INFO_TOP = TAB_TOP + TAB_HEIGHT + 8
local INFO_HEIGHT = 92
local BODY_TOP = INFO_TOP + INFO_HEIGHT + 10
local BODY_HEIGHT = 312
local FOOT_TOP = BODY_TOP + BODY_HEIGHT + 8
local NEWS_TOP = 84 -- 위쪽 가운데 안내 두 줄(0~76) 바로 아래
local PENDING_TIMEOUT = 3 -- 결과가 이만큼(초) 안 오면 버튼을 다시 풂
local REVEAL_GAP = 0.09 -- 10회 뽑기 카드가 하나씩 열리는 간격(초)
local SHAKE_SECONDS = 0.45 -- 결과 카드가 열리기 전 캡슐이 흔들리는 시간
local RETRY = 4 -- 내 부품 값을 못 받았으면 이 간격(초)으로 다시 요청

type Tab = { button: TextButton, sub: TextLabel, stroke: UIStroke }

local player = Players.LocalPlayer
local root: Frame
local openButton: TextButton
local panel: Frame
local coinLabel: TextLabel
local footLabel: TextLabel
local infoIconSlot: Frame
local infoName: TextLabel
local infoLine: TextLabel
local infoHint: TextLabel
local dexButton: TextButton
local pullArea: Frame
local pullOne: TextButton
local pullTen: TextButton
local priceNote: TextLabel
local dexArea: Frame
local dexDesc: TextLabel
local resultLayer: Frame
local newsFrame: Frame
local newsText: TextLabel
local newsCount: TextLabel
local newsCheer: TextButton
local newsIconSlot: Frame
local resultCheers: TextLabel? = nil -- 내 전설 결과 화면의 '모두에게 알렸어요 · 축하 N'
local revealDone = false -- 결과 카드가 다 열렸는지 (그 전에는 전설 알림 글자를 숨겨 미리 알려 주지 않음)

local tabs: { [string]: Tab } = {}
local selected = Config.Parts.Types[1].Id
local progress: any = nil -- 서버가 보낸 내 부품 (PartProgress 신호)
local owned: { [string]: { [string]: boolean } } = {}
local isOpen = false
local dexOpen = false
local pending = false
local pendingAt = 0
local showingResult = false
local resultsAt = -math.huge -- 정산이 시작된 시각 (os.clock)
local footUntil = 0
local nextRequest = 0
local newsId = 0
local newsUntil = 0
local dexPick: string? = nil
local dexRarity = 1 -- 도감에서 보고 있는 레어도

-- ------------------------------------------------------------ 값
local function number(map: any, key: string, default: number): number
	local value = if type(map) == "table" then map[key] else nil
	return if type(value) == "number" and value == value then value else default
end

local function partOf(typeId: string): (number, number, number, number, Catalog.Variant)
	local rarity = math.clamp(math.floor(number(progress and progress.rarity, typeId, 1)), 1, #RARITY_NAMES)
	local star = math.clamp(math.floor(number(progress and progress.star, typeId, 1)), 1, Leveling.MaxStars)
	local level = math.floor(number(progress and progress.lv, typeId, 1))
	local cap = math.floor(number(progress and progress.cap, typeId, Leveling.cap(star)))
	local lookId = if progress and type(progress.look) == "table" then progress.look[typeId] else nil
	local variant = Catalog.get(lookId)
	if variant == nil or variant.Rarity ~= rarity then
		variant = Catalog.ofRarity(typeId, rarity)[1] or Catalog.starter(typeId)
	end
	return rarity, star, level, cap, variant :: Catalog.Variant
end

local function rarityText(rarity: number): Color3
	return Catalog.rarityText(rarity)
end

-- 모은 부품 수 (typeId 가 없으면 모든 종류, rarity 가 없으면 모든 레어도)
local function ownedCount(typeId: string?, rarity: number?): number
	local count = 0
	for _, info in ipairs(Config.Parts.Types) do
		if typeId == nil or info.Id == typeId then
			local mine = owned[info.Id] or {}
			for _, item in ipairs(Catalog.ofType(info.Id)) do
				if mine[item.Id] and (rarity == nil or item.Rarity == rarity) then
					count += 1
				end
			end
		end
	end
	return count
end

local function stars(star: number): string
	return string.rep("★", star) .. string.rep("☆", Leveling.MaxStars - star)
end

local function coins(): number
	return State.myNumber("Coins")
end

local function canPull(): boolean
	return Gacha.open(State.phase())
end

local function shortExp(n: number): string
	if n >= 10000 then
		local man = n / 10000
		return (if man == math.floor(man) then string.format("%d", man) else string.format("%.1f", man)) .. "만"
	end
	return Fmt.comma(n)
end

local function foot(text: string, color: Color3?, seconds: number?)
	footLabel.Text = text
	footLabel.TextColor3 = color or C.Dim
	footUntil = os.clock() + (seconds or 4)
end

local function defaultFoot(): string
	if not canPull() then
		return "카운트다운·비행 중에는 뽑을 수 없어요"
	elseif State.phase() == "Build" then
		return "지금 뽑은 부품은 다음 판 조립부터 로켓에 들어가요"
	end
	return "같은 레어도를 또 뽑으면 ★ 돌파 (만렙 한도 +" .. Fmt.comma(Config.Progress.LevelsPerStar) .. "), 낮은 레어도는 경험치로"
end

-- ------------------------------------------------------------ 그리기
local function clear(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function refreshTabs()
	for _, info in ipairs(Config.Parts.Types) do
		local tab = tabs[info.Id]
		if tab then
			local rarity, star = partOf(info.Id)
			local on = info.Id == selected
			tab.button.BackgroundColor3 = if on then C.PanelLight else C.Panel
			tab.button.BackgroundTransparency = if on then 0 else 0.25
			tab.stroke.Transparency = if on then 0 else 0.7
			tab.sub.Text = RARITY_NAMES[rarity] .. " ★" .. star
			tab.sub.TextColor3 = rarityText(rarity)
		end
	end
end

local function refreshInfo()
	local rarity, star, level, cap, variant = partOf(selected)
	clear(infoIconSlot)
	local icon = PartIcon.make(infoIconSlot, variant, 76)
	icon.Name = "CurrentIcon"
	infoName.Text = variant.Name
	infoName.TextColor3 = rarityText(rarity)
	local levelText = if level >= Leveling.MaxLevel then "MAX" else "Lv " .. Fmt.comma(level) .. " / " .. Fmt.comma(cap)
	infoLine.Text = string.format("%s %s · %s", RARITY_NAMES[rarity], stars(star), levelText)
	if level >= cap and cap < Leveling.MaxLevel then
		infoHint.Text = "만렙 한도! 같은 " .. RARITY_NAMES[rarity] .. " 부품을 뽑으면 돌파해서 더 올라가요"
		infoHint.TextColor3 = GOLD
	else
		infoHint.Text = variant.Desc
		infoHint.TextColor3 = C.Dim
	end
	dexButton.Text = if dexOpen
		then "뽑기로 돌아가기"
		else string.format("도감 %d/%d", ownedCount(selected), #Catalog.ofType(selected))
end

local function bestKm(): number
	return State.myNumber("BestKm")
end

local function refreshPull()
	local wallet = coins()
	local open = canPull() and not pending and not showingResult
	local best = bestKm()
	local one = Gacha.price(best, false)
	local ten = Gacha.price(best, true)
	pullOne.Text = "1회 · " .. Fmt.comma(one)
	pullTen.Text = string.format("10회 · %s (+%d)", Fmt.comma(ten), G.TenCount - 10)
	local okOne = open and wallet >= one
	local okTen = open and wallet >= ten
	pullOne.BackgroundColor3 = if okOne then C.Purple else C.PanelLight
	pullTen.BackgroundColor3 = if okTen then GOLD:Lerp(C.Orange, 0.4) else C.PanelLight
	pullOne.TextColor3 = if okOne then C.Text else C.Dim
	pullTen.TextColor3 = if okTen then C.Text else C.Dim
	pullOne.AutoButtonColor = okOne
	pullTen.AutoButtonColor = okTen
	priceNote.Text = if Gacha.unitPrice(best) > G.BasePrice
		then string.format("1회 값 = 내 최고 기록 %s × %d (기록이 늘면 값도 올라요)", Fmt.km(best), G.PricePerKm)
		else string.format("1회 값 = 내 최고 기록 km × %d (처음엔 %s)", G.PricePerKm, Fmt.comma(G.BasePrice))
end

local refresh: () -> () -- 아래에서 정의 (도감 버튼이 씀)

-- 도감 한 쪽: 위에 레어도 버튼 4개와 모은 수, 아래에 그 레어도 부품 칸 (한 줄 8칸, 15칸이면 두 줄)
local DEX_FILTER_HEIGHT = 34
local DEX_CELL_WIDTH = 100
local DEX_CELL_HEIGHT = 116
local DEX_GAP = 9
local DEX_PER_ROW = 8

local function refreshDex()
	clear(dexArea)
	local rarity, _, _, _, current = partOf(selected)
	local mine = owned[selected] or {}
	local filterWidth = 140
	for r = 1, #RARITY_NAMES do
		local on = r == dexRarity
		local total = #Catalog.ofRarity(selected, r)
		local filter = Ui.button(dexArea, "DexRarity_" .. r, string.format("%s %d/%d", RARITY_NAMES[r], ownedCount(selected, r), total), 16,
			if on then C.PanelLight else C.Panel, {
				Position = UDim2.fromOffset(PAD + (r - 1) * (filterWidth + 8), 0),
				Size = UDim2.fromOffset(filterWidth, DEX_FILTER_HEIGHT),
				BackgroundTransparency = if on then 0 else 0.3,
				TextColor3 = rarityText(r),
			})
		Ui.stroke(filter, Catalog.RarityColors[r], if on then 3 else 1, if on then 0 else 0.5)
		filter.Activated:Connect(function()
			if dexRarity ~= r then
				dexRarity = r
				dexPick = nil
				State.emit("Sound", "Press")
				refresh()
			end
		end)
	end
	Ui.label(dexArea, "DexTotal", string.format("모은 부품 %d / %d", ownedCount(nil, nil), Catalog.count()), 16, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 0),
		Size = UDim2.fromOffset(230, DEX_FILTER_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
	})
	local list = Catalog.ofRarity(selected, dexRarity)
	local rowWidth = DEX_PER_ROW * DEX_CELL_WIDTH + (DEX_PER_ROW - 1) * DEX_GAP
	local left = (PANEL_WIDTH - rowWidth) / 2
	local top = DEX_FILTER_HEIGHT + 8
	for index, item in ipairs(list) do
		local row = math.floor((index - 1) / DEX_PER_ROW)
		local col = (index - 1) % DEX_PER_ROW
		local have = mine[item.Id] == true
		local wearing = item.Id == current.Id
		local cell = Ui.button(dexArea, "Dex_" .. item.Id, "", 14, C.Panel, {
			Position = UDim2.fromOffset(left + col * (DEX_CELL_WIDTH + DEX_GAP), top + row * (DEX_CELL_HEIGHT + 8)),
			Size = UDim2.fromOffset(DEX_CELL_WIDTH, DEX_CELL_HEIGHT),
			BackgroundTransparency = 0.2,
			AutoButtonColor = have,
		})
		local stroke = Ui.stroke(cell, if wearing then BuildUi.MineColor else C.Line, if wearing then 3 else 1, 0)
		stroke.Name = "Edge"
		local icon = PartIcon.make(cell, item, 60, not have)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		Ui.label(cell, "Name", if have then item.Name else "???", 13, {
			Position = UDim2.new(0, 3, 0, 68),
			Size = UDim2.new(1, -6, 0, 30),
			TextColor3 = if have then rarityText(item.Rarity) else C.Dim,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local tag = if wearing then "장착 중" elseif have and item.Rarity == rarity then "눌러서 바꾸기" else ""
		Ui.label(cell, "Tag", tag, 12, {
			Position = UDim2.new(0, 3, 0, 98),
			Size = UDim2.new(1, -6, 0, 14),
			TextColor3 = if wearing then BuildUi.MineColor else C.Dim,
			Font = Ui.FontLight,
		})
		cell.Activated:Connect(function()
			dexPick = item.Id
			if not have then
				dexDesc.Text = RARITY_NAMES[item.Rarity] .. " · 아직 못 모은 부품"
				return
			end
			dexDesc.Text = item.Name .. " · " .. item.Desc
			if item.Rarity == rarity and not wearing then
				State.emit("Sound", "Press")
				Net.event("GachaLook"):FireServer(selected, item.Id)
			end
		end)
	end
	dexDesc = Ui.label(dexArea, "DexDesc", "모은 부품을 누르면 설명이 나와요. 지금 부품과 레어도가 같으면 그 모양으로 바꿔 껴요", 16, {
		Position = UDim2.new(0, PAD, 1, -28),
		Size = UDim2.new(1, -2 * PAD, 0, 24),
		TextColor3 = C.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if dexPick then
		local item = Catalog.get(dexPick)
		if item and mine[item.Id] then
			dexDesc.Text = item.Name .. " · " .. item.Desc
		end
	end
end

function refresh()
	if not isOpen then
		return
	end
	coinLabel.Text = "보유 코인 " .. Fmt.comma(coins())
	refreshTabs()
	refreshInfo()
	pullArea.Visible = not dexOpen
	dexArea.Visible = dexOpen
	if dexOpen then
		refreshDex()
	else
		refreshPull()
	end
	if os.clock() >= footUntil then
		footLabel.Text = defaultFoot()
		footLabel.TextColor3 = if canPull() then C.Dim else C.Red
	end
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if not open then
		resultLayer.Visible = false
		showingResult = false
		dexOpen = false
	else
		if progress == nil or progress.owned == nil then
			Net.event("PartProgress"):FireServer()
		end
		refresh()
	end
end

-- ------------------------------------------------------------ 결과 연출
local OUTCOME_COLOR = { new = GOLD, star = C.Cyan, exp = C.Dim }

local function outcomeText(result: any): string
	if result.kind == "new" then
		return "새 부품! 바꿔 꼈어요"
	elseif result.kind == "star" then
		return string.format("★%d 돌파! 한도 Lv %s", result.star, Fmt.comma(Leveling.cap(result.star)))
	end
	return "경험치 +" .. shortExp(number(result, "exp", 0))
end

local function shortOutcome(result: any): string
	if result.kind == "new" then
		return "새 부품!"
	elseif result.kind == "star" then
		return "★" .. tostring(result.star) .. " 돌파"
	end
	return "+" .. shortExp(number(result, "exp", 0)) .. " 경험치"
end

-- 레어도가 높은 카드 뒤에 도는 빛살 (카드와 같은 층의 뒤쪽 형제라서 카드 글자를 가리지 않음)
local function rays(parent: Instance, color: Color3, x: number, y: number, size: number)
	local holder = Ui.frame(parent, "Rays", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 1,
	})
	for i = 0, 3 do
		Ui.frame(holder, "Ray", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, math.floor(size * 0.12), 1, 0),
			Rotation = i * 45,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
		})
	end
	Ui.tween(holder, 6, { Rotation = 180 }, Enum.EasingStyle.Linear)
	return holder
end

local function resultCard(parent: Instance, result: any, x: number, y: number, w: number, h: number, big: boolean): Frame
	local variant = Catalog.get(result.id)
	local rarity = math.clamp(math.floor(number(result, "rarity", 1)), 1, #RARITY_NAMES)
	local color = Catalog.RarityColors[rarity]
	local card = Ui.frame(parent, "ResultCard", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color:Lerp(DARK, 0.8),
		BackgroundTransparency = 0,
		ZIndex = 2,
	})
	card:SetAttribute("Rarity", rarity)
	card:SetAttribute("Kind", result.kind)
	card:SetAttribute("Variant", result.id)
	Ui.corner(card, 12)
	Ui.stroke(card, color, if rarity >= 3 then 3 else 2, 0)
	if rarity >= 3 then
		rays(parent, if rarity >= 4 then GOLD else color, x + w / 2, y + h / 2, math.floor(math.max(w, h) * 1.35))
	end
	local iconSize = if big then 150 else 72
	if variant then
		local icon = PartIcon.make(card, variant, iconSize)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, if big then 18 else 8)
		icon.ZIndex = 3
	end
	local textTop = (if big then 18 else 8) + iconSize + 4
	Ui.label(card, "Rarity", RARITY_NAMES[rarity], if big then 20 else 13, {
		Position = UDim2.new(0, 4, 0, textTop),
		Size = UDim2.new(1, -8, 0, if big then 24 else 16),
		TextColor3 = rarityText(rarity),
		ZIndex = 3,
	})
	Ui.label(card, "Name", if variant then variant.Name else tostring(result.id), if big then 26 else 14, {
		Position = UDim2.new(0, 4, 0, textTop + (if big then 24 else 15)),
		Size = UDim2.new(1, -8, 0, if big then 32 else 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	Ui.label(card, "Outcome", if big then outcomeText(result) else shortOutcome(result), if big then 20 else 13, {
		Position = UDim2.new(0, 4, 0, textTop + (if big then 58 else 33)),
		Size = UDim2.new(1, -8, 0, if big then 26 else 16),
		TextColor3 = OUTCOME_COLOR[result.kind] or C.Dim,
		ZIndex = 3,
	})
	if result.isNew then
		local tag = Ui.label(card, "NewTag", "도감 NEW", if big then 16 else 11, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(if big then 86 else 58, if big then 24 else 16),
			BackgroundColor3 = BuildUi.MineColor,
			BackgroundTransparency = 0,
			TextStrokeTransparency = 1,
			ZIndex = 4,
		})
		Ui.corner(tag, 6)
	end
	-- 열리는 순간 작게 시작해 튀어나옴
	local pop = Ui.make("UIScale", { Scale = 0.3, Parent = card })
	Ui.tween(pop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	return card
end

local function showResults(data: any)
	clear(resultLayer)
	resultLayer.Visible = true
	showingResult = true
	resultCheers = nil
	revealDone = false
	local list = if type(data.results) == "table" then data.results else {}
	local best = 1
	local counts = { 0, 0, 0, 0 }
	for _, result in ipairs(list) do
		local r = math.clamp(math.floor(number(result, "rarity", 1)), 1, 4)
		counts[r] += 1
		best = math.max(best, r)
	end
	local title = Ui.label(resultLayer, "ResultTitle", string.format("%s 뽑기 %s", Gacha.typeName(data.typeId),
		if data.ten then "10회" else "1회"), 26, {
		Position = UDim2.fromOffset(PAD, 10),
		Size = UDim2.new(1, -2 * PAD, 0, 34),
		ZIndex = 2,
	})
	title.TextColor3 = rarityText(best)
	local parts = {}
	for r = 4, 1, -1 do
		if counts[r] > 0 then
			table.insert(parts, string.format("%s %d", RARITY_NAMES[r], counts[r]))
		end
	end
	Ui.label(resultLayer, "ResultCounts", table.concat(parts, " · "), 18, {
		Position = UDim2.fromOffset(PAD, 44),
		Size = UDim2.new(1, -2 * PAD, 0, 24),
		TextColor3 = C.Dim,
		ZIndex = 2,
	})
	local rarity, star, level = partOf(data.typeId)
	rarity = math.clamp(math.floor(number(data, "rarity", rarity)), 1, 4)
	star = math.floor(number(data, "star", star))
	level = math.floor(number(data, "level", level))
	local afterText = string.format("지금 %s: %s %s · Lv %s / %s", Gacha.typeName(data.typeId), RARITY_NAMES[rarity], stars(star),
		Fmt.comma(level), Fmt.comma(Leveling.cap(star)))
	local after = Ui.label(resultLayer, "ResultAfter", afterText, 18, {
		Position = UDim2.new(0, PAD, 1, -96),
		Size = UDim2.new(1, -2 * PAD, 0, 24),
		TextColor3 = rarityText(rarity),
		ZIndex = 2,
	})
	after.Visible = false
	local okButton = Ui.button(resultLayer, "ResultOk", "확인", 22, C.PanelLight, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(220, 52),
		ZIndex = 3,
		Visible = false,
	})
	Ui.stroke(okButton, C.White, 2, 0.4)
	okButton.Activated:Connect(function()
		resultLayer.Visible = false
		showingResult = false
		clear(resultLayer)
		refresh()
	end)
	-- 캡슐이 흔들린 뒤 카드가 열림
	local shell = Ui.frame(resultLayer, "Capsule", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Catalog.RarityColors[best],
		BackgroundTransparency = 0,
		ZIndex = 4,
	})
	Ui.corner(shell, 60)
	local shellLid = Ui.frame(shell, "Lid", {
		Size = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.1,
	})
	Ui.corner(shellLid, 60)
	Ui.tween(shell, SHAKE_SECONDS / 3, { Rotation = 14 }, Enum.EasingStyle.Sine)
	task.delay(SHAKE_SECONDS / 3, function()
		if shell.Parent then
			Ui.tween(shell, SHAKE_SECONDS / 3, { Rotation = -14 }, Enum.EasingStyle.Sine)
		end
	end)
	State.emit("Sound", "ItemUse")
	task.delay(SHAKE_SECONDS, function()
		if not showingResult or shell.Parent == nil then
			return
		end
		shell:Destroy()
		local count = #list
		local width = PANEL_WIDTH
		if count <= 1 then
			if list[1] then
				resultCard(resultLayer, list[1], width / 2 - 150, 80, 300, 330, true)
			end
		else
			local perRow = 6
			local w, h = 128, 150
			local gap = 12
			for index, result in ipairs(list) do
				local row = math.floor((index - 1) / perRow)
				local col = (index - 1) % perRow
				local inRow = math.min(perRow, count - row * perRow)
				local left = (width - (inRow * w + (inRow - 1) * gap)) / 2
				task.delay((index - 1) * REVEAL_GAP, function()
					if showingResult then
						resultCard(resultLayer, result, left + col * (w + gap), 84 + row * (h + gap), w, h, false)
					end
				end)
			end
		end
		task.delay(math.max(count - 1, 0) * REVEAL_GAP + 0.3, function()
			if not showingResult then
				return
			end
			after.Visible = true
			okButton.Visible = true
			revealDone = true
			if resultCheers then
				(resultCheers :: TextLabel).Visible = true
			end
			State.emit("Sound", if best >= 3 then "Combo" else "MissionSuccess")
		end)
	end)
end

-- ------------------------------------------------------------ 전설 알림
local function showNews(data: any)
	if type(data) ~= "table" or type(data.id) ~= "number" then
		return
	end
	local variant = Catalog.get(data.variantId)
	if variant == nil then
		return
	end
	newsId = data.id
	newsUntil = os.clock() + number(data, "seconds", G.CheerSeconds)
	local mine = data.userId == player.UserId
	if mine and isOpen and showingResult then
		-- 내가 뽑은 전설: 결과 화면이 이미 축하하므로 위쪽 알림 대신 결과 화면에 축하 수를 띄움
		local label = Ui.label(resultLayer, "ResultCheers", "모두에게 알렸어요 · 축하 0", 18, {
			Position = UDim2.new(0, PAD, 1, -124),
			Size = UDim2.new(1, -2 * PAD, 0, 24),
			TextColor3 = C.Pink,
			ZIndex = 2,
			Visible = revealDone,
		})
		resultCheers = label
		newsFrame.Visible = false
		return
	end
	clear(newsIconSlot)
	PartIcon.make(newsIconSlot, variant, 48)
	local who = if mine then "내가" else tostring(data.name) .. " 님이"
	local particle = string.sub(Fmt.josa(variant.Name, "을", "를"), #variant.Name + 1)
	newsText.Text = string.format("%s %s '%s'%s 뽑았어요!", who, RARITY_NAMES[variant.Rarity], variant.Name, particle)
	newsText.TextColor3 = rarityText(variant.Rarity)
	newsCount.Text = "축하 0"
	newsCheer.Visible = not mine
	newsCheer.Text = "축하 +" .. Fmt.comma(G.CheerCoins)
	newsCheer.AutoButtonColor = true
	newsCheer.BackgroundColor3 = GOLD:Lerp(C.Orange, 0.3)
	newsFrame.Visible = true
	newsFrame.Size = UDim2.fromOffset(if mine then 560 else 700, 64)
	local pop = newsFrame:FindFirstChildOfClass("UIScale")
	if pop then
		pop.Scale = 0.6
		Ui.tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	State.emit("Sound", "Combo")
end

-- ------------------------------------------------------------ 만들기
local function buildButton()
	openButton = Ui.button(root, "GachaButton", "부품 뽑기", 20, C.Purple, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, BUTTON_TOP),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		Visible = false,
	})
	Ui.stroke(openButton, GOLD, 2, 0.2)
	openButton.TextXAlignment = Enum.TextXAlignment.Right
	Ui.make("UIPadding", { PaddingRight = UDim.new(0, 14), Parent = openButton })
	-- 왼쪽에 작은 캡슐
	local capsule = Ui.frame(openButton, "CapsuleIcon", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
	})
	Ui.corner(capsule, 13)
	local lid = Ui.frame(capsule, "Lid", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = C.White, BackgroundTransparency = 0 })
	Ui.corner(lid, 13)
	openButton.Activated:Connect(function()
		State.emit("Sound", "Press")
		setOpen(not isOpen)
	end)
end

local function buildPanel()
	panel = Ui.panel(root, "GachaPanel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundTransparency = 0,
		Visible = false,
	})
	Ui.stroke(panel, GOLD, 2, 0.3)
	Ui.label(panel, "Title", "부품 뽑기", 26, {
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.fromOffset(200, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
	})
	coinLabel = Ui.label(panel, "Coins", "", 20, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 10),
		Size = UDim2.fromOffset(360, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Yellow,
	})
	local close = Ui.button(panel, "GachaClose", "닫기", 20, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 6),
		Size = UDim2.fromOffset(120, 44),
		Modal = true, -- 열려 있는 동안은 마우스가 풀려 있음
	})
	Ui.stroke(close, C.Line, 2, 0)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	-- 부품 종류 탭
	local types = Config.Parts.Types
	local tabWidth = (PANEL_WIDTH - 2 * PAD - (#types - 1) * 8) / #types
	for index, info in ipairs(types) do
		local style = BuildUi.TypeStyle[info.Id] or { Color = C.Cyan }
		local button = Ui.button(panel, "GachaTab_" .. info.Id, "", 18, C.Panel, {
			Position = UDim2.fromOffset(PAD + (index - 1) * (tabWidth + 8), TAB_TOP),
			Size = UDim2.fromOffset(tabWidth, TAB_HEIGHT),
		})
		local stroke = Ui.stroke(button, style.Color, 2, 0.7)
		Ui.label(button, "TypeName", info.Name, 19, {
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = style.Color,
		})
		local sub = Ui.label(button, "Part", "", 15, {
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 20),
			Font = Ui.FontLight,
		})
		button.Activated:Connect(function()
			if selected ~= info.Id then
				selected = info.Id
				dexPick = nil
				dexRarity = partOf(selected)
				State.emit("Sound", "Press")
				refresh()
			end
		end)
		tabs[info.Id] = { button = button, sub = sub, stroke = stroke }
	end

	-- 지금 부품
	local info = Ui.frame(panel, "Current", {
		Position = UDim2.fromOffset(PAD, INFO_TOP),
		Size = UDim2.new(1, -2 * PAD, 0, INFO_HEIGHT),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
	})
	Ui.corner(info, 10)
	infoIconSlot = Ui.frame(info, "IconSlot", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(76, 76),
	})
	infoName = Ui.label(info, "PartName", "", 24, {
		Position = UDim2.fromOffset(98, 6),
		Size = UDim2.new(1, -300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	infoLine = Ui.label(info, "PartLine", "", 18, {
		Position = UDim2.fromOffset(98, 36),
		Size = UDim2.new(1, -300, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	infoHint = Ui.label(info, "PartHint", "", 15, {
		Position = UDim2.fromOffset(98, 62),
		Size = UDim2.new(1, -110, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Ui.FontLight,
	})
	dexButton = Ui.button(info, "DexButton", "도감", 18, C.Panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(180, 44),
	})
	Ui.stroke(dexButton, BuildUi.MineColor, 2, 0.2)
	dexButton.Activated:Connect(function()
		dexOpen = not dexOpen
		dexPick = nil
		dexRarity = partOf(selected)
		State.emit("Sound", "Press")
		refresh()
	end)

	-- 뽑기 (하나): 왼쪽 캡슐과 확률, 오른쪽 1회·10회 버튼과 값 설명
	pullArea = Ui.frame(panel, "PullArea", {
		Position = UDim2.fromOffset(0, BODY_TOP),
		Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
	})
	local oddsBox = Ui.frame(pullArea, "OddsBox", {
		Position = UDim2.fromOffset(PAD, 0),
		Size = UDim2.fromOffset(420, BODY_HEIGHT),
		BackgroundColor3 = Catalog.RarityColors[4]:Lerp(DARK, 0.85),
		BackgroundTransparency = 0,
	})
	Ui.corner(oddsBox, 12)
	Ui.stroke(oddsBox, GOLD, 2, 0.5)
	local ball = Ui.frame(oddsBox, "Ball", {
		Position = UDim2.fromOffset(22, 18),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
	})
	Ui.corner(ball, 42)
	local lid = Ui.frame(ball, "Lid", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = C.White, BackgroundTransparency = 0.05 })
	Ui.corner(lid, 42)
	Ui.frame(ball, "Band", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0,
	})
	Ui.label(oddsBox, "CapsuleName", "부품 캡슐", 26, {
		Position = UDim2.fromOffset(124, 24),
		Size = UDim2.fromOffset(280, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
	})
	Ui.label(oddsBox, "CapsuleSub", "고른 종류의 부품이 나와요", 16, {
		Position = UDim2.fromOffset(124, 60),
		Size = UDim2.fromOffset(280, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
	})
	for line, r in ipairs({ 4, 3, 2, 1 }) do
		local y = 116 + (line - 1) * 46
		local row = Ui.frame(oddsBox, "Odds_" .. r, {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.fromOffset(388, 40),
			BackgroundColor3 = Catalog.RarityColors[r]:Lerp(DARK, 0.7),
			BackgroundTransparency = 0.2,
		})
		Ui.corner(row, 8)
		Ui.label(row, "Name", RARITY_NAMES[r], 20, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.5, -14, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityText(r),
		})
		Ui.label(row, "Percent", Gacha.percent(Gacha.Odds[r]), 20, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.5, -14, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = rarityText(r),
		})
	end
	local buttons = Ui.frame(pullArea, "Buttons", {
		Position = UDim2.fromOffset(PAD + 420 + 16, 0),
		Size = UDim2.fromOffset(PANEL_WIDTH - 2 * PAD - 420 - 16, BODY_HEIGHT),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
	})
	Ui.corner(buttons, 12)
	pullOne = Ui.button(buttons, "PullOne", "", 22, C.Purple, {
		Position = UDim2.fromOffset(16, 24),
		Size = UDim2.new(1, -32, 0, 66),
	})
	pullTen = Ui.button(buttons, "PullTen", "", 22, GOLD, {
		Position = UDim2.fromOffset(16, 108),
		Size = UDim2.new(1, -32, 0, 66),
	})
	Ui.label(buttons, "TenNote", string.format("10회는 %d개 (%d개 덤)", G.TenCount, G.TenCount - 10), 16, {
		Position = UDim2.fromOffset(16, 180),
		Size = UDim2.new(1, -32, 0, 24),
		TextColor3 = C.Yellow,
		Font = Ui.FontLight,
	})
	priceNote = Ui.label(buttons, "PriceNote", "", 16, {
		Position = UDim2.fromOffset(16, 214),
		Size = UDim2.new(1, -32, 0, 80),
		TextColor3 = C.Dim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Ui.FontLight,
	})
	local function press(isTen: boolean)
		if pending or showingResult then
			return
		end
		if not canPull() then
			foot("카운트다운·비행 중에는 뽑을 수 없어요", C.Red)
			return
		end
		local price = Gacha.price(bestKm(), isTen)
		if coins() < price then
			foot(string.format("코인이 모자라요 (%s 코인 더 필요)", Fmt.comma(price - coins())), C.Red)
			return
		end
		pending = true
		pendingAt = os.clock()
		State.emit("Sound", "Press")
		foot("뽑는 중...", C.Yellow, PENDING_TIMEOUT)
		Net.event("GachaPull"):FireServer(selected, isTen)
		refresh()
	end
	pullOne.Activated:Connect(function()
		press(false)
	end)
	pullTen.Activated:Connect(function()
		press(true)
	end)

	-- 도감
	dexArea = Ui.frame(panel, "Dex", {
		Position = UDim2.fromOffset(0, BODY_TOP),
		Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
		Visible = false,
	})

	footLabel = Ui.label(panel, "Foot", "", 16, {
		Position = UDim2.fromOffset(PAD, FOOT_TOP),
		Size = UDim2.new(1, -2 * PAD, 0, PANEL_HEIGHT - FOOT_TOP - 10),
		TextColor3 = C.Dim,
		TextWrapped = true,
	})

	-- 결과 (판 전체를 덮음)
	resultLayer = Ui.frame(panel, "GachaResult", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.04,
		ZIndex = 5,
		Visible = false,
	})
	Ui.corner(resultLayer, 12)
end

local function buildNews()
	newsFrame = Ui.panel(root, "GachaNews", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, NEWS_TOP),
		Size = UDim2.fromOffset(700, 64),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Ui.stroke(newsFrame, GOLD, 3, 0)
	Ui.make("UIScale", { Parent = newsFrame })
	newsIconSlot = Ui.frame(newsFrame, "IconSlot", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(48, 48),
	})
	newsText = Ui.label(newsFrame, "NewsText", "", 20, {
		Position = UDim2.fromOffset(64, 6),
		Size = UDim2.new(1, -64 - 150, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	newsCount = Ui.label(newsFrame, "NewsCount", "", 16, {
		Position = UDim2.fromOffset(64, 36),
		Size = UDim2.new(1, -64 - 150, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Pink,
	})
	newsCheer = Ui.button(newsFrame, "CheerButton", "", 18, GOLD, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(132, 46),
	})
	newsCheer.Activated:Connect(function()
		if newsId > 0 and newsCheer.AutoButtonColor then
			newsCheer.AutoButtonColor = false
			newsCheer.BackgroundColor3 = C.PanelLight
			newsCheer.Text = "축하했어요"
			State.emit("Sound", "Thanks")
			Net.event("GachaCheer"):FireServer(newsId)
		end
	end)
end

-- ------------------------------------------------------------ 신호
local function onProgress(payload: any)
	if type(payload) ~= "table" then
		return
	end
	progress = payload
	if type(payload.owned) == "table" then
		for typeId, ids in pairs(payload.owned) do
			if type(ids) == "table" then
				local set = {}
				for _, id in ipairs(ids) do
					set[id] = true
				end
				owned[typeId] = set
			end
		end
	end
	refresh()
end

local function onResult(data: any)
	pending = false
	if type(data) ~= "table" then
		return
	end
	if data.ok ~= true then
		foot(tostring(data.reason or "뽑지 못했어요"), C.Red)
		refresh()
		return
	end
	foot(defaultFoot(), C.Dim, 0)
	if isOpen then
		showResults(data)
	end
	refresh()
end

function GachaUi.init()
	local _, base = Ui.screen("RoflyGacha", 16)
	root = base
	buildButton()
	buildPanel()
	buildNews()
	Net.event("PartProgress").OnClientEvent:Connect(onProgress)
	Net.event("GachaResult").OnClientEvent:Connect(onResult)
	Net.event("GachaNews").OnClientEvent:Connect(showNews)
	Net.event("GachaCheered").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and data.id == newsId then
			local count = Fmt.comma(number(data, "count", 0))
			newsCount.Text = "축하 " .. count
			if resultCheers and (resultCheers :: TextLabel).Parent then
				(resultCheers :: TextLabel).Text = "모두에게 알렸어요 · 축하 " .. count
			end
		end
	end)
	State.on("Phase", function(phase: any)
		if phase == "Results" then
			resultsAt = os.clock()
		end
		if not Gacha.open(tostring(phase)) and isOpen then
			setOpen(false)
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(refresh)
	player:GetAttributeChangedSignal("BestKm"):Connect(refresh) -- 값이 최고 기록을 따라감
	nextRequest = os.clock() + RETRY
end

function GachaUi.update(_dt: number)
	local phase = State.phase()
	local show = Gacha.open(phase) and (phase ~= "Results" or os.clock() - resultsAt >= G.ResultsDelay)
	openButton.Visible = show
	if isOpen and not Gacha.open(phase) then
		setOpen(false)
	end
	if pending and os.clock() - pendingAt > PENDING_TIMEOUT then
		pending = false
		foot("응답이 없어요. 다시 눌러 주세요", C.Red)
		refresh()
	end
	if progress == nil and os.clock() >= nextRequest then
		nextRequest = os.clock() + RETRY
		Net.event("PartProgress"):FireServer()
	end
	if isOpen and footUntil > 0 and os.clock() >= footUntil then
		footUntil = 0
		refresh()
	end
	if newsFrame.Visible and os.clock() >= newsUntil then
		newsFrame.Visible = false
	end
end

return GachaUi
