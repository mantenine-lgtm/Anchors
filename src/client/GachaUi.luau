-- 부품 뽑기 창과 내 장비 창 (Nick 11-28 "부품 뽑기도 추가", "발사 전에 뽑을 수 있게", "장비창과 뽑기창 분리할것").
-- 규칙·수치는 Config.Gacha, 서버는 GachaService. 두 창은 오른쪽 위 버튼 줄(시점·디버그 아래)의 '부품 뽑기'·'내 장비' 버튼으로
-- 엽니다(한 번에 하나만, Nick 11-28 "장비창도 우측에 메뉴"). 탑승 대기·조립·정산 때만 보이고 카운트다운·비행이 되면 닫힘.
-- 뽑기 창: 부품 종류 탭 6개 → 뽑기 하나(확률, 1회·10회 버튼) → 안내 글.
-- 값은 내 최고 기록 km × Config.Gacha.PricePerKm (Nick 11-28 "일반 고급 최고급 넣지 말고 뽑기 일괄").
-- 뽑기 그림은 캡슐 대신 빛이 새는 우주 보급 상자 (Nick 11-28 "뽑기 아이콘은 캡슐 아이콘 말고 적당한 아이콘", Catalog.GachaIcon).
-- 뽑으면 보급 상자가 세 번 점점 세게 흔들리고(나올 레어도 쪽 색으로 빛이 커짐) 빛이 모였다가 터진 뒤 카드가 상자에서 날아 나옴
-- (Nick 11-28 "한번 흔들 하고 뽑히는거 말고 좀 더 효과", 10회는 11장, 누르면 건너뜀). 결과마다 '새 부품!' / '★ 돌파' / '경험치 +N'.
-- 내 장비 창: 종류 탭 6개 → 그 종류 도감 → 안내 글 → 맨 아래 '현재 장착 중' 줄(아이콘·이름·레어도·★·레벨·경험치).
-- 도감은 그 종류 30개(일반 14·희귀 9·영웅 5·전설 2, 모두 180개)를 레어도 버튼으로 나눠 한 번에 14장까지 보여 줌
-- (휴대폰 사양: 아이콘을 한꺼번에 많이 만들지 않음). 모은 것은 그림과 이름, 아직 못 뽑은 것은 그림 없이 물음표와 '???'
-- (Nick 11-28 "도감에서 아직 못뽑은건 못보게 물음표로 표시"). 카드를 누르면 오른쪽에 큰 그림·도감 번호·설명·나올 확률.
-- 지금 부품과 레어도가 같은 모은 부품은 '이 모양으로 바꾸기' 로 바꿔 낌 (능력치는 같음).
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
local EQUIP_TOP = BUTTON_TOP + BUTTON_HEIGHT + 8 -- '내 장비' 버튼은 '부품 뽑기' 바로 아래
local PANEL_WIDTH = 900
local PANEL_HEIGHT = 610 -- 내 장비 창과 뽑기 결과 화면
local PAD = 16
local TAB_TOP = 60
local TAB_HEIGHT = 60
local BODY_TOP = TAB_TOP + TAB_HEIGHT + 8
local BODY_HEIGHT = 312
local FOOT_TOP = BODY_TOP + BODY_HEIGHT + 4
local GACHA_FOOT_HEIGHT = 44
local GACHA_HEIGHT = FOOT_TOP + GACHA_FOOT_HEIGHT + 12 -- 뽑기 창은 안내 글까지 (장비는 내 장비 창으로 나눔)
local INFO_HEIGHT = 92
local INFO_TOP = PANEL_HEIGHT - PAD - INFO_HEIGHT -- 내 장비 창: '현재 장착 중' 줄은 맨 아래
local FOOT_HEIGHT = INFO_TOP - FOOT_TOP - 6 -- 내 장비 창 안내 글은 도감과 맨 아래 줄 사이
local EXP_WIDTH = 210 -- '현재 장착 중' 줄 오른쪽 경험치 막대
local NEWS_TOP = 84 -- 위쪽 가운데 안내 두 줄(0~76) 바로 아래
local PENDING_TIMEOUT = 3 -- 결과가 이만큼(초) 안 오면 버튼을 다시 풂
local REVEAL_GAP = 0.09 -- 10회 뽑기 카드가 하나씩 날아 나오는 간격(초)
-- 뽑기 연출 (Nick 11-28 "한번 흔들 하고 뽑히는거 말고 좀 더 효과 넣어서"): 상자가 튀어나와 세 번 점점 세게 흔들리고(흔들릴 때마다
-- 뒤 빛이 커지며 나올 가장 높은 레어도 쪽 색으로 한 단계씩 바뀜), 빛이 모였다가 번쩍 터지며 고리·반짝이가 퍼지고, 카드가 상자
-- 자리에서 제자리로 날아감. 결과 화면을 누르면 바로 카드로 건너뜀. 폰 사양: 이미지·파티클 없이 Frame 몇십 개와 트윈만, 다 쓰면 지움
local APPEAR_SECONDS = 0.25 -- 상자가 튀어나오는 시간
local SHAKES = 3
local SHAKE_GAP = 0.36 -- 흔들림 한 번
local CHARGE_SECONDS = 0.45 -- 빛이 모이는 시간 (그다음 터짐)
local FLY_SECONDS = 0.32 -- 카드가 상자 자리에서 제자리로 날아가는 시간
local CRATE_CENTER = Vector2.new(PANEL_WIDTH / 2, 290) -- 결과 화면에서 상자 가운데
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
local equipButton: TextButton
local equipIconSlot: Frame
local equipIconId = "" -- '내 장비' 버튼 그림에 쓴 엔진 모양
local equipPanel: Frame
local infoExpText: TextLabel
local infoExpFill: Frame
local pullArea: Frame
local pullOne: TextButton
local pullTen: TextButton
local priceNote: TextLabel
local dexArea: Frame
local resultLayer: Frame
local newsFrame: Frame
local newsText: TextLabel
local newsCount: TextLabel
local newsCheer: TextButton
local newsIconSlot: Frame
local resultCheers: TextLabel? = nil -- 내 전설 결과 화면의 '모두에게 알렸어요 · 축하 N'
local revealDone = false -- 결과 카드가 다 열렸는지 (그 전에는 전설 알림 글자를 숨겨 미리 알려 주지 않음)

local tabs: { [string]: Tab } = {} -- 뽑기 창 탭
local equipTabs: { [string]: Tab } = {} -- 내 장비 창 탭
local selected = Config.Parts.Types[1].Id
local progress: any = nil -- 서버가 보낸 내 부품 (PartProgress 신호)
local owned: { [string]: { [string]: boolean } } = {}
local isOpen = false
local equipOpen = false -- 내 장비 창 (뽑기 창 isOpen 과 한 번에 하나만)
local seq = 0 -- 결과 연출 차례: 건너뛰거나 다시 뽑으면 늘어서 남은 단계가 멈춤
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

local function refreshTabs(store: { [string]: Tab })
	for _, info in ipairs(Config.Parts.Types) do
		local tab = store[info.Id]
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
	-- 경험치 막대: 지금 레벨에서 쌓인 양 / 다음 레벨까지 (한도·만렙이면 가득)
	local exp = number(progress and progress.exp, selected, 0)
	local need = Leveling.need(level, rarity)
	if level >= Leveling.MaxLevel then
		infoExpText.Text = "만렙"
		infoExpFill.Size = UDim2.fromScale(1, 1)
	elseif level >= cap then
		infoExpText.Text = "한도 · 돌파하면 다시 올라요"
		infoExpFill.Size = UDim2.fromScale(1, 1)
	else
		infoExpText.Text = "경험치 " .. shortExp(math.floor(exp)) .. " / " .. shortExp(need)
		infoExpFill.Size = UDim2.fromScale(math.clamp(exp / math.max(need, 1), 0, 1), 1)
	end
end

-- '내 장비' 버튼 그림: 내 엔진 모양 (바뀌면 다시 그림)
local function refreshEquipIcon()
	local _, _, _, _, variant = partOf(Config.Parts.Types[1].Id)
	if variant.Id ~= equipIconId then
		equipIconId = variant.Id
		clear(equipIconSlot)
		PartIcon.make(equipIconSlot, variant, 34)
	end
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

-- 뽑기 그림: 빛이 새는 우주 보급 상자 (Nick 11-28 "뽑기 아이콘은 캡슐 아이콘 말고 적당한 아이콘 알아서 생각해서 생성").
-- Catalog.GachaIcon 에 올린 그림 Id 가 있으면 그 그림, 없으면 Frame 몇 개로 뚜껑이 들린 금색 상자와 새는 빛을 그림.
-- glow 를 주면 상자 뒤에 그 색 빛 (결과 연출: 가장 높은 레어도 색)
local function crateIcon(parent: Instance, name: string, px: number, glow: Color3?): Frame
	local holder = Ui.frame(parent, name, { Size = UDim2.fromOffset(px, px) })
	if glow then
		local halo = Ui.frame(holder, "Glow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.1, 1.1),
			BackgroundColor3 = glow,
			BackgroundTransparency = 0.45,
		})
		Ui.corner(halo, px)
	end
	if Catalog.GachaIcon ~= "" then
		Ui.make("ImageLabel", {
			Name = "Art",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Catalog.GachaIcon,
			Parent = holder,
		})
		return holder
	end
	local light = Ui.frame(holder, "Light", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundColor3 = Color3.fromRGB(255, 250, 220),
		BackgroundTransparency = 0.35,
	})
	Ui.corner(light, px)
	local box = Ui.frame(holder, "Box", {
		Position = UDim2.fromScale(0.1, 0.44),
		Size = UDim2.fromScale(0.8, 0.5),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
	})
	Ui.corner(box, math.max(2, math.floor(px * 0.08)))
	Ui.frame(box, "Band", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.42),
		Size = UDim2.fromScale(1, 0.16),
		BackgroundColor3 = Color3.fromRGB(205, 110, 30),
		BackgroundTransparency = 0,
	})
	local lid = Ui.frame(holder, "Lid", {
		Position = UDim2.fromScale(0.05, 0.27),
		Size = UDim2.fromScale(0.82, 0.15),
		Rotation = -12,
		BackgroundColor3 = Color3.fromRGB(255, 226, 120),
		BackgroundTransparency = 0,
	})
	Ui.corner(lid, math.max(2, math.floor(px * 0.06)))
	return holder
end

-- 도감 한 쪽 (Nick 11-28 "도감 목록도 너무 성의없어보임"): 위에 레어도 버튼 4개(모은 수와 막대)와 모은 부품 수,
-- 왼쪽에 그 레어도 부품 카드(한 줄 7장, 많아야 14장 = 두 줄, 카드마다 도감 번호·그림·이름. 전설처럼 2장 이하면 큰 카드),
-- 오른쪽에 고른 부품의 큰 그림·번호·이름·설명·뽑기 1회에 나올 확률과 '이 모양으로 바꾸기' 버튼
-- (지금 부품과 레어도가 같고 모은 것만)
local DEX_FILTER_WIDTH = 124
local DEX_FILTER_HEIGHT = 38
local DEX_CELL_WIDTH = 76
local DEX_CELL_HEIGHT = 112
local DEX_BIG_WIDTH = 168 -- 2장 이하인 쪽(전설)의 큰 카드
local DEX_GAP = 6
local DEX_BIG_HEIGHT = 2 * DEX_CELL_HEIGHT + DEX_GAP
local DEX_PER_ROW = 7
local DEX_GRID_TOP = DEX_FILTER_HEIGHT + 10
local DEX_GRID_WIDTH = DEX_PER_ROW * DEX_CELL_WIDTH + (DEX_PER_ROW - 1) * DEX_GAP
local DEX_DETAIL_LEFT = PAD + DEX_GRID_WIDTH + 14
local DEX_DETAIL_WIDTH = PANEL_WIDTH - PAD - DEX_DETAIL_LEFT
local DEX_DETAIL_ICON = 112

-- 그 부품 하나가 뽑기 1회에 나올 확률 (레어도 확률 ÷ 그 레어도 부품 수), 세 자리까지
local function itemChance(rarity: number, pool: number): string
	local value = (G.Odds[rarity] or 0) / math.max(pool, 1) * 100
	local text = string.format(if value >= 1 then "%.1f" elseif value >= 0.1 then "%.2f" else "%.3f", value)
	while string.sub(text, -1) == "0" and string.find(text, ".", 1, true) ~= nil do
		text = string.sub(text, 1, -2)
	end
	if string.sub(text, -1) == "." then
		text = string.sub(text, 1, -2)
	end
	return text .. "%"
end

local function dexNumber(item: Catalog.Variant): string
	return string.format("No.%02d", item.No)
end

-- 아직 못 뽑은 부품 자리: 그림 없이 레어도 색 칸에 물음표 (Nick 11-28 "도감에서 아직 못뽑은건 못보게 물음표로 표시")
local function mystery(parent: Instance, px: number, rarity: number): Frame
	local color = Catalog.RarityColors[rarity]
	local box = Ui.frame(parent, "Mystery", {
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = color:Lerp(DARK, 0.78),
		BackgroundTransparency = 0,
	})
	Ui.corner(box, math.floor(px * 0.18))
	Ui.stroke(box, color, 2, 0.55)
	Ui.label(box, "Mark", "?", math.floor(px * 0.6), {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = rarityText(rarity),
		TextStrokeTransparency = 1,
	})
	return box
end

-- 오른쪽 설명 칸: 고른 부품 (모은 것은 그림·이름·설명, 못 뽑은 것은 물음표와 확률만)
local function dexDetail(item: Catalog.Variant, have: boolean, wearing: boolean, rarity: number)
	local pool = #Catalog.ofRarity(item.Type, item.Rarity)
	local color = Catalog.RarityColors[item.Rarity]
	local detail = Ui.frame(dexArea, "DexDetail", {
		Position = UDim2.fromOffset(DEX_DETAIL_LEFT, DEX_GRID_TOP),
		Size = UDim2.fromOffset(DEX_DETAIL_WIDTH, BODY_HEIGHT - DEX_GRID_TOP - 6),
		BackgroundColor3 = color:Lerp(DARK, 0.86),
		BackgroundTransparency = 0,
	})
	detail:SetAttribute("Variant", item.Id)
	Ui.corner(detail, 12)
	Ui.stroke(detail, color, 2, 0.35)
	local slot = Ui.frame(detail, "DetailIcon", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(DEX_DETAIL_ICON, DEX_DETAIL_ICON),
	})
	if have then
		PartIcon.make(slot, item, DEX_DETAIL_ICON)
	else
		mystery(slot, DEX_DETAIL_ICON, item.Rarity)
	end
	local textLeft = 12 + DEX_DETAIL_ICON + 12
	local textWidth = DEX_DETAIL_WIDTH - textLeft - 10
	Ui.label(detail, "DetailNo", dexNumber(item) .. " · " .. RARITY_NAMES[item.Rarity], 15, {
		Position = UDim2.fromOffset(textLeft, 14),
		Size = UDim2.fromOffset(textWidth, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rarityText(item.Rarity),
		Font = Ui.FontLight,
	})
	Ui.label(detail, "DetailName", if have then item.Name else "???", 22, {
		Position = UDim2.fromOffset(textLeft, 36),
		Size = UDim2.fromOffset(textWidth, 56),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextColor3 = if have then C.Text else C.Dim,
	})
	Ui.label(detail, "DetailChance", "1회에 " .. itemChance(item.Rarity, pool), 14, {
		Position = UDim2.fromOffset(textLeft, 96),
		Size = UDim2.fromOffset(textWidth, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
	})
	Ui.label(detail, "DetailDesc", if have then item.Desc else "아직 못 뽑은 부품이에요. 부품 뽑기에서 나와요.", 16, {
		Position = UDim2.fromOffset(14, 12 + DEX_DETAIL_ICON + 10),
		Size = UDim2.fromOffset(DEX_DETAIL_WIDTH - 28, 62),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextColor3 = if have then C.Text else C.Dim,
		Font = Ui.FontLight,
	})
	local bottom = BODY_HEIGHT - DEX_GRID_TOP - 6 - 50
	if have and wearing then
		Ui.label(detail, "DetailState", "장착 중", 18, {
			Position = UDim2.fromOffset(14, bottom),
			Size = UDim2.fromOffset(DEX_DETAIL_WIDTH - 28, 40),
			TextColor3 = BuildUi.MineColor,
		})
	elseif have and item.Rarity == rarity then
		local wear = Ui.button(detail, "DexWear", "이 모양으로 바꾸기", 18, C.Purple, {
			Position = UDim2.fromOffset(14, bottom),
			Size = UDim2.fromOffset(DEX_DETAIL_WIDTH - 28, 40),
		})
		wear.Activated:Connect(function()
			State.emit("Sound", "Press")
			Net.event("GachaLook"):FireServer(selected, item.Id)
		end)
	else
		Ui.label(detail, "DetailState", if have
			then "지금 부품이 " .. RARITY_NAMES[rarity] .. "이라 바꿔 낄 수 없어요"
			else "같은 레어도를 모으면 모양을 골라 낄 수 있어요", 14, {
			Position = UDim2.fromOffset(14, bottom),
			Size = UDim2.fromOffset(DEX_DETAIL_WIDTH - 28, 40),
			TextWrapped = true,
			TextColor3 = C.Dim,
			Font = Ui.FontLight,
		})
	end
end

local function refreshDex()
	clear(dexArea)
	local rarity, _, _, _, current = partOf(selected)
	local mine = owned[selected] or {}
	for r = 1, #RARITY_NAMES do
		local on = r == dexRarity
		local total = #Catalog.ofRarity(selected, r)
		local have = ownedCount(selected, r)
		local filter = Ui.button(dexArea, "DexRarity_" .. r, string.format("%s %d/%d", RARITY_NAMES[r], have, total), 16,
			if on then C.PanelLight else C.Panel, {
				Position = UDim2.fromOffset(PAD + (r - 1) * (DEX_FILTER_WIDTH + 8), 0),
				Size = UDim2.fromOffset(DEX_FILTER_WIDTH, DEX_FILTER_HEIGHT),
				BackgroundTransparency = if on then 0 else 0.3,
				TextColor3 = rarityText(r),
			})
		Ui.stroke(filter, Catalog.RarityColors[r], if on then 3 else 1, if on then 0 else 0.5)
		local _, fill = Ui.bar(filter, "Got", Catalog.RarityColors[r], {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -20, 0, 4),
		})
		fill.Size = UDim2.fromScale(if total > 0 then have / total else 0, 1)
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
		Size = UDim2.fromOffset(200, DEX_FILTER_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
	})
	local list = Catalog.ofRarity(selected, dexRarity)
	-- 고른 부품: 누른 것 → 이 쪽의 지금 부품 → 이 쪽에서 처음 모은 것 → 첫 칸
	local pick: Catalog.Variant? = nil
	local picked = if dexPick then Catalog.get(dexPick) else nil
	if picked and picked.Type == selected and picked.Rarity == dexRarity then
		pick = picked
	elseif current.Rarity == dexRarity then
		pick = current
	else
		for _, item in ipairs(list) do
			if mine[item.Id] then
				pick = item
				break
			end
		end
		pick = pick or list[1]
	end
	local big = #list <= 2
	local cellWidth = if big then DEX_BIG_WIDTH else DEX_CELL_WIDTH
	local cellHeight = if big then DEX_BIG_HEIGHT else DEX_CELL_HEIGHT
	local iconSize = if big then 128 else 60
	local iconTop = if big then 26 else 17
	for index, item in ipairs(list) do
		local row = math.floor((index - 1) / DEX_PER_ROW)
		local col = (index - 1) % DEX_PER_ROW
		local have = mine[item.Id] == true
		local wearing = item.Id == current.Id
		local chosen = pick ~= nil and item.Id == pick.Id
		local cell = Ui.button(dexArea, "Dex_" .. item.Id, "", 14, if chosen then C.PanelLight else C.Panel, {
			Position = UDim2.fromOffset(PAD + col * (cellWidth + DEX_GAP), DEX_GRID_TOP + row * (cellHeight + DEX_GAP)),
			Size = UDim2.fromOffset(cellWidth, cellHeight),
			BackgroundTransparency = if chosen then 0 else 0.25,
		})
		local edge = if wearing then BuildUi.MineColor elseif chosen then C.Text else C.Line
		local stroke = Ui.stroke(cell, edge, if wearing or chosen then 3 else 1, if wearing or chosen then 0 else 0.4)
		stroke.Name = "Edge"
		local icon = if have then PartIcon.make(cell, item, iconSize) else mystery(cell, iconSize, item.Rarity)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, iconTop)
		Ui.label(cell, "No", string.format("%02d", item.No), if big then 14 else 11, {
			Position = UDim2.fromOffset(6, 2),
			Size = UDim2.fromOffset(24, if big then 20 else 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Dim,
			Font = Ui.FontLight,
			ZIndex = 3,
		})
		Ui.label(cell, "Name", if have then item.Name else "???", if big then 18 else 13, {
			Position = UDim2.new(0, 3, 0, iconTop + iconSize + 2),
			Size = UDim2.new(1, -6, 0, if big then 50 else 30),
			TextColor3 = if have then rarityText(item.Rarity) else C.Dim,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local tag = Ui.label(cell, "Tag", if wearing then "장착 중" else "", if big then 13 else 10, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 2),
			Size = UDim2.fromOffset(if big then 56 else 42, if big then 20 else 14),
			BackgroundColor3 = BuildUi.MineColor,
			BackgroundTransparency = if wearing then 0 else 1,
			TextColor3 = DARK,
			TextStrokeTransparency = 1,
			Visible = wearing,
			ZIndex = 3,
		})
		Ui.corner(tag, 8)
		cell.Activated:Connect(function()
			if dexPick ~= item.Id then
				dexPick = item.Id
				State.emit("Sound", "Press")
				refresh()
			end
		end)
	end
	if pick then
		dexDetail(pick, mine[pick.Id] == true, pick.Id == current.Id, rarity)
	end
end

function refresh()
	refreshEquipIcon()
	if isOpen then
		coinLabel.Text = "보유 코인 " .. Fmt.comma(coins())
		refreshTabs(tabs)
		refreshPull()
		if os.clock() >= footUntil then
			footLabel.Text = defaultFoot()
			footLabel.TextColor3 = if canPull() then C.Dim else C.Red
		end
	end
	if equipOpen then
		refreshTabs(equipTabs)
		refreshInfo()
		refreshDex()
	end
end

local function askProgress()
	if progress == nil or progress.owned == nil then
		Net.event("PartProgress"):FireServer()
	end
end

-- 뽑기 창 (열면 내 장비 창은 닫힘)
local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if not open then
		seq += 1
		resultLayer.Visible = false
		showingResult = false
	else
		equipOpen = false
		equipPanel.Visible = false
		askProgress()
		refresh()
	end
end

-- 내 장비 창 (열면 뽑기 창은 닫힘). 도감은 지금 부품의 레어도 쪽부터
local function setEquipOpen(open: boolean)
	if open and isOpen then
		setOpen(false)
	end
	equipOpen = open
	equipPanel.Visible = open
	if open then
		dexPick = nil
		dexRarity = partOf(selected)
		askProgress()
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

-- 연출 조각은 다 쓰면 지움
local function dispose(obj: Instance, seconds: number)
	task.delay(seconds, function()
		if obj.Parent then
			obj:Destroy()
		end
	end)
end

-- 반짝이 하나: (x, y) 에서 angle 쪽으로 dist 만큼 날아가며 돌고 작아지다 사라짐
local function spark(parent: Instance, color: Color3, x: number, y: number, angle: number, dist: number, size: number, life: number)
	local dot = Ui.frame(parent, "Spark", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = 6,
	})
	local small = math.max(2, math.floor(size * 0.3))
	Ui.tween(dot, life, {
		Position = UDim2.fromOffset(x + math.cos(angle) * dist, y + math.sin(angle) * dist),
		Size = UDim2.fromOffset(small, small),
		Rotation = 225,
		BackgroundTransparency = 1,
	})
	dispose(dot, life + 0.05)
end

-- 퍼지는 빛 고리 하나
local function ring(parent: Instance, color: Color3, x: number, y: number, from: number, to: number, life: number, thickness: number)
	local circle = Ui.frame(parent, "Ring", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(from, from),
		ZIndex = 6,
	})
	Ui.corner(circle, to)
	local stroke = Ui.stroke(circle, color, thickness, 0)
	Ui.tween(circle, life, { Size = UDim2.fromOffset(to, to) })
	Ui.tween(stroke, life, { Transparency = 1 })
	dispose(circle, life + 0.05)
end

-- 흔들림 단계마다 상자 뒤 빛 색: 1단계 금빛, 2단계는 희귀 이상이 있으면 파랑, 3단계부터 나올 가장 높은 레어도 색
local function stageColor(stage: number, best: number): Color3
	if stage <= 1 or best <= 1 then
		return GOLD
	elseif stage == 2 then
		return Catalog.RarityColors[2]
	end
	return Catalog.RarityColors[best]
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

local function resultCard(parent: Instance, result: any, x: number, y: number, w: number, h: number, big: boolean, from: Vector2?): Frame
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
	local cx, cy = x + w / 2, y + h / 2
	local land = if from then FLY_SECONDS else 0
	if rarity >= 3 then
		-- 영웅 이상: 내려앉으면 뒤에 빛살과 빛 고리 (전설은 반짝이도)
		task.delay(land, function()
			if card.Parent then
				rays(parent, if rarity >= 4 then GOLD else color, cx, cy, math.floor(math.max(w, h) * 1.35))
				ring(parent, if rarity >= 4 then GOLD else color, cx, cy, math.floor(w * 0.6), math.floor(math.max(w, h) * 1.7), 0.45, 4)
				if rarity >= 4 then
					for i = 1, 8 do
						spark(parent, if i % 2 == 0 then GOLD else C.White, cx, cy, i / 8 * math.pi * 2, math.max(w, h) * 0.9, 10, 0.6)
					end
				end
			end
		end)
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
	-- 상자 자리에서 작게 날아와 제자리에서 튀어나옴 (from 이 없으면 제자리에서 튀어나옴)
	local pop = Ui.make("UIScale", { Scale = if from then 0.15 else 0.3, Parent = card })
	if from then
		card.Position = UDim2.fromOffset(from.X, from.Y)
		Ui.tween(card, FLY_SECONDS, { Position = UDim2.fromOffset(cx, cy) })
		Ui.tween(pop, FLY_SECONDS + 0.05, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		Ui.tween(pop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	return card
end

local function showResults(data: any)
	seq += 1
	local token = seq
	local skipped = false
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
	-- 제목 색과 레어도별 개수는 카드가 열릴 때 보임 (미리 알려 주지 않음)
	local title = Ui.label(resultLayer, "ResultTitle", string.format("%s 뽑기 %s", Gacha.typeName(data.typeId),
		if data.ten then "10회" else "1회"), 26, {
		Position = UDim2.fromOffset(PAD, 10),
		Size = UDim2.new(1, -2 * PAD, 0, 34),
		ZIndex = 2,
	})
	local parts = {}
	for r = 4, 1, -1 do
		if counts[r] > 0 then
			table.insert(parts, string.format("%s %d", RARITY_NAMES[r], counts[r]))
		end
	end
	local countLabel = Ui.label(resultLayer, "ResultCounts", table.concat(parts, " · "), 18, {
		Position = UDim2.fromOffset(PAD, 44),
		Size = UDim2.new(1, -2 * PAD, 0, 24),
		TextColor3 = C.Dim,
		ZIndex = 2,
		Visible = false,
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
		seq += 1
		resultLayer.Visible = false
		showingResult = false
		clear(resultLayer)
		refresh()
	end)

	-- delay 뒤에 fn (그사이 다시 뽑거나 닫았으면 안 함. intro 는 건너뛰었어도 안 함)
	local function at(delay: number, fn: () -> (), intro: boolean?)
		task.delay(delay, function()
			if token == seq and showingResult and not (intro and skipped) then
				fn()
			end
		end)
	end
	local cx, cy = CRATE_CENTER.X, CRATE_CENTER.Y
	local burstColor = if best >= 2 then Catalog.RarityColors[best] else GOLD

	-- 카드: 상자 자리에서 하나씩 날아 나옴 (fast 면 한꺼번에 제자리에). 다 열리면 확인 버튼
	local function reveal(fast: boolean)
		title.TextColor3 = rarityText(best)
		countLabel.Visible = true
		local count = #list
		local from = if fast then nil else CRATE_CENTER
		if count <= 1 then
			if list[1] then
				resultCard(resultLayer, list[1], PANEL_WIDTH / 2 - 150, 80, 300, 330, true, from)
			end
		else
			local perRow = 6
			local w, h = 128, 150
			local gap = 12
			for index, result in ipairs(list) do
				local row = math.floor((index - 1) / perRow)
				local col = (index - 1) % perRow
				local inRow = math.min(perRow, count - row * perRow)
				local left = (PANEL_WIDTH - (inRow * w + (inRow - 1) * gap)) / 2
				local function place()
					resultCard(resultLayer, result, left + col * (w + gap), 84 + row * (h + gap), w, h, false, from)
				end
				if fast then
					place()
				else
					at((index - 1) * REVEAL_GAP, place)
				end
			end
		end
		local done = if fast then 0.3 else math.max(count - 1, 0) * REVEAL_GAP + FLY_SECONDS + 0.15
		at(done, function()
			after.Visible = true
			okButton.Visible = true
			revealDone = true
			if resultCheers then
				(resultCheers :: TextLabel).Visible = true
			end
			if best >= 3 then
				State.emit("Sound", "Combo")
			end
		end)
	end

	-- 연출 (건너뛰면 통째로 지움)
	local intro = Ui.frame(resultLayer, "Intro", { Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	local glow = Ui.frame(intro, "Glow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.7,
		ZIndex = 2,
	})
	Ui.corner(glow, 400)
	local shell = crateIcon(intro, "Crate", 150)
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromOffset(cx, cy)
	shell.ZIndex = 3
	local grow = Ui.make("UIScale", { Scale = 0.4, Parent = shell })
	Ui.tween(grow, APPEAR_SECONDS, { Scale = 1 }, Enum.EasingStyle.Back)
	Ui.label(intro, "SkipHint", "누르면 바로 열어요", 15, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(300, 22),
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
		ZIndex = 3,
	})
	local skip = Ui.make("TextButton", {
		Name = "SkipTap",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = resultLayer,
	})
	skip.Activated:Connect(function()
		if skipped or token ~= seq or not showingResult then
			return
		end
		skipped = true
		intro:Destroy()
		skip:Destroy()
		reveal(true)
	end)

	-- 1) 세 번 점점 세게 흔들림: 흔들릴 때마다 살짝 뛰고, 뒤 빛이 커지며 색이 한 단계, 반짝이 네 개
	for k = 1, SHAKES do
		at(APPEAR_SECONDS + (k - 1) * SHAKE_GAP, function()
			local amp = 6 + 5 * k
			local color = stageColor(k, best)
			Ui.tween(shell, 0.06, { Rotation = amp, Position = UDim2.fromOffset(cx, cy - 4 * k) }, Enum.EasingStyle.Sine)
			for _, step in ipairs({ { 0.06, -amp, 0.09 }, { 0.15, amp * 0.4, 0.07 }, { 0.22, 0, 0.08 } }) do
				task.delay(step[1], function()
					if shell.Parent then
						Ui.tween(shell, step[3], { Rotation = step[2], Position = UDim2.fromOffset(cx, cy) }, Enum.EasingStyle.Sine)
					end
				end)
			end
			local size = 170 + 45 * k
			Ui.tween(glow, 0.2, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, BackgroundTransparency = 0.7 - 0.12 * k })
			for i = 1, 4 do
				local angle = (i / 4 + k * 0.13) * math.pi * 2
				spark(intro, if i % 2 == 0 then color else GOLD, cx, cy, angle, 90 + 25 * k, 8 + 2 * k, 0.45)
			end
			State.emit("Sound", "Press")
		end, true)
	end

	-- 2) 빛이 모임: 빛이 커지고 진해지며 상자가 부풀고, 바깥 반짝이가 가운데로 빨려 듦 (희귀 이상은 빛살)
	local chargeAt = APPEAR_SECONDS + SHAKES * SHAKE_GAP
	at(chargeAt, function()
		Ui.tween(glow, CHARGE_SECONDS, { Size = UDim2.fromOffset(420, 420), BackgroundColor3 = burstColor, BackgroundTransparency = 0.2 })
		Ui.tween(grow, CHARGE_SECONDS, { Scale = 1.18 })
		if best >= 2 then
			rays(intro, burstColor, cx, cy, 520).Name = "ChargeRays"
		end
		if best >= 4 then
			local more = rays(intro, GOLD, cx, cy, 600)
			more.Name = "ChargeRays"
			more.Rotation = 22.5
		end
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			spark(intro, burstColor, cx + math.cos(angle) * 260, cy + math.sin(angle) * 260, angle + math.pi, 220, 12, CHARGE_SECONDS)
		end
		State.emit("Sound", "ItemUse")
	end, true)

	-- 3) 터짐: 번쩍 + 빛 고리 + 반짝이(레어도가 높을수록 많이) 뒤 카드가 날아 나옴
	at(chargeAt + CHARGE_SECONDS, function()
		intro:Destroy()
		skip:Destroy()
		local flash = Ui.frame(resultLayer, "Flash", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.15,
			ZIndex = 6,
		})
		Ui.corner(flash, 12)
		Ui.tween(flash, 0.4, { BackgroundTransparency = 1 })
		dispose(flash, 0.45)
		ring(resultLayer, burstColor, cx, cy, 120, 760, 0.5, 6)
		if best >= 3 then
			ring(resultLayer, GOLD, cx, cy, 80, 560, 0.6, 4)
		end
		local sparks = ({ 12, 14, 20, 28 })[best]
		for i = 1, sparks do
			local color = if i % 3 == 0 then GOLD elseif i % 3 == 1 then burstColor else C.White
			spark(resultLayer, color, cx, cy, math.random() * math.pi * 2, 180 + math.random() * 220, 10 + math.random() * 8, 0.6 + math.random() * 0.3)
		end
		State.emit("Sound", "MissionSuccess")
		reveal(false)
	end, true)
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
-- 오른쪽 메뉴 버튼 (부품 뽑기·내 장비): 왼쪽에 작은 그림, 글자는 그림 오른쪽 칸의 가운데
-- (Nick 11-28 "우측에 폰트 정렬 이상": 전에는 글자가 버튼 오른쪽 끝에 붙어 있었음)
local function menuButton(name: string, text: string, top: number, color: Color3, edge: Color3): TextButton
	local button = Ui.button(root, name, "", 20, color, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, top),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		Visible = false,
	})
	Ui.stroke(button, edge, 2, 0.2)
	Ui.label(button, "Label", text, 20, {
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -52, 1, 0),
	})
	return button
end

local function buildButtons()
	openButton = menuButton("GachaButton", "부품 뽑기", BUTTON_TOP, C.Purple, GOLD)
	-- 왼쪽에 작은 보급 상자
	local icon = crateIcon(openButton, "GachaIcon", 34)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	openButton.Activated:Connect(function()
		State.emit("Sound", "Press")
		setOpen(not isOpen)
	end)
	-- 내 장비 (Nick 11-28 "장비창도 우측에 메뉴 만들어줘"): 그림은 내 엔진 모양
	equipButton = menuButton("EquipButton", "내 장비", EQUIP_TOP, BuildUi.MineColor:Lerp(DARK, 0.55), BuildUi.MineColor)
	equipIconSlot = Ui.frame(equipButton, "EquipIcon", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
	})
	equipButton.Activated:Connect(function()
		State.emit("Sound", "Press")
		setEquipOpen(not equipOpen)
	end)
end

-- 창 제목과 닫기 버튼
local function titleBar(parent: Frame, title: string, color: Color3, closeName: string, onClose: () -> ())
	Ui.label(parent, "Title", title, 26, {
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.fromOffset(200, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
	})
	local close = Ui.button(parent, closeName, "닫기", 20, C.PanelLight, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 6),
		Size = UDim2.fromOffset(120, 44),
		Modal = true, -- 열려 있는 동안은 마우스가 풀려 있음
	})
	Ui.stroke(close, C.Line, 2, 0)
	close.Activated:Connect(onClose)
end

-- 부품 종류 탭 6개 (두 창이 고른 종류를 같이 씀). 탭 아래 줄은 그 종류 지금 부품의 레어도·★
local function buildTabs(parent: Frame, prefix: string, store: { [string]: Tab })
	local types = Config.Parts.Types
	local tabWidth = (PANEL_WIDTH - 2 * PAD - (#types - 1) * 8) / #types
	for index, info in ipairs(types) do
		local style = BuildUi.TypeStyle[info.Id] or { Color = C.Cyan }
		local button = Ui.button(parent, prefix .. info.Id, "", 18, C.Panel, {
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
		store[info.Id] = { button = button, sub = sub, stroke = stroke }
	end
end

-- 뽑기 창: 종류 탭 → 뽑기 하나 → 안내 글 (장비·도감은 내 장비 창)
local function buildPanel()
	panel = Ui.panel(root, "GachaPanel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, GACHA_HEIGHT),
		BackgroundTransparency = 0,
		Visible = false,
	})
	Ui.stroke(panel, GOLD, 2, 0.3)
	titleBar(panel, "부품 뽑기", GOLD, "GachaClose", function()
		setOpen(false)
	end)
	coinLabel = Ui.label(panel, "Coins", "", 20, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 10),
		Size = UDim2.fromOffset(360, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Yellow,
	})
	buildTabs(panel, "GachaTab_", tabs)

	-- 뽑기 (하나): 왼쪽 보급 상자와 확률, 오른쪽 1회·10회 버튼과 값 설명
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
	local crate = crateIcon(oddsBox, "Crate", 92)
	crate.Position = UDim2.fromOffset(18, 12)
	Ui.label(oddsBox, "CrateName", "부품 보급 상자", 26, {
		Position = UDim2.fromOffset(124, 24),
		Size = UDim2.fromOffset(280, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
	})
	Ui.label(oddsBox, "CrateSub", "고른 종류의 부품이 나와요", 16, {
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

	footLabel = Ui.label(panel, "Foot", "", 16, {
		Position = UDim2.fromOffset(PAD, FOOT_TOP),
		Size = UDim2.new(1, -2 * PAD, 0, GACHA_FOOT_HEIGHT),
		TextColor3 = C.Dim,
		TextWrapped = true,
	})
end

-- 내 장비 창: 종류 탭 → 그 종류 도감 → 안내 글 → 맨 아래 현재 장착 중
local function buildEquipPanel()
	equipPanel = Ui.panel(root, "EquipPanel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundTransparency = 0,
		Visible = false,
	})
	Ui.stroke(equipPanel, BuildUi.MineColor, 2, 0.3)
	titleBar(equipPanel, "내 장비", BuildUi.MineColor, "EquipClose", function()
		setEquipOpen(false)
	end)
	buildTabs(equipPanel, "EquipTab_", equipTabs)
	dexArea = Ui.frame(equipPanel, "Dex", {
		Position = UDim2.fromOffset(0, BODY_TOP),
		Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
	})
	Ui.label(equipPanel, "EquipFoot",
		"같은 레어도로 모은 부품은 '이 모양으로 바꾸기'로 모양만 바꿔 낄 수 있어요 (능력치는 같아요)", 16, {
			Position = UDim2.fromOffset(PAD, FOOT_TOP),
			Size = UDim2.new(1, -2 * PAD, 0, FOOT_HEIGHT),
			TextColor3 = C.Dim,
			TextWrapped = true,
		})

	-- 현재 장착 중 (맨 아래): 아이콘·이름·레어도·★·레벨·설명, 오른쪽에 경험치 막대
	local info = Ui.frame(equipPanel, "Current", {
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
	local equipped = Ui.label(info, "EquippedTag", "현재 장착 중", 15, {
		Position = UDim2.fromOffset(98, 9),
		Size = UDim2.fromOffset(104, 24),
		BackgroundColor3 = BuildUi.MineColor,
		BackgroundTransparency = 0,
		TextColor3 = DARK,
		TextStrokeTransparency = 1,
	})
	Ui.corner(equipped, 8)
	infoName = Ui.label(info, "PartName", "", 24, {
		Position = UDim2.fromOffset(212, 6),
		Size = UDim2.new(1, -(212 + EXP_WIDTH + 24), 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	infoLine = Ui.label(info, "PartLine", "", 18, {
		Position = UDim2.fromOffset(98, 36),
		Size = UDim2.new(1, -(98 + EXP_WIDTH + 24), 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	infoHint = Ui.label(info, "PartHint", "", 15, {
		Position = UDim2.fromOffset(98, 62),
		Size = UDim2.new(1, -110, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Ui.FontLight,
	})
	infoExpText = Ui.label(info, "ExpText", "", 15, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(EXP_WIDTH, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Dim,
		Font = Ui.FontLight,
	})
	local _, fill = Ui.bar(info, "ExpBar", BuildUi.MineColor, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 40),
		Size = UDim2.fromOffset(EXP_WIDTH, 10),
	})
	infoExpFill = fill
end

-- 뽑기 결과 화면: 뽑기 창 위를 덮는 따로 된 판 (뽑기 창보다 커서 연출과 카드 11장이 넉넉히 들어감)
local function buildResultLayer()
	resultLayer = Ui.frame(root, "GachaResult", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.04,
		ZIndex = 5,
		Visible = false,
	})
	Ui.corner(resultLayer, 12)
	Ui.stroke(resultLayer, GOLD, 2, 0.3)
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
	buildButtons()
	buildPanel()
	buildEquipPanel()
	buildResultLayer()
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
		if not Gacha.open(tostring(phase)) then
			if isOpen then
				setOpen(false)
			end
			if equipOpen then
				setEquipOpen(false)
			end
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
	equipButton.Visible = show
	if not Gacha.open(phase) then
		if isOpen then
			setOpen(false)
		end
		if equipOpen then
			setEquipOpen(false)
		end
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
