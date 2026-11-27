-- 부품 조립 (빌드 페이즈). 기획서 '부품 그리드':
-- 부품 종류마다 정사각형 그리드에 승무원 수만큼 칸이 무작위로 열리고, 승무원은 종류마다 부품 1개씩
-- 열린 빈 칸에 꽂습니다 (사람은 조립 화면에서, 봇은 시간을 두고 하나씩). 시간이 끝나면 못 꽂은 부품은
-- 빈 칸에 자동으로 꽂습니다. 데모 1은 인접 시너지가 없어서 어느 칸에 꽂아도 수치는 같습니다.
--
-- 그리드는 RoundState 아래 Grid 폴더의 속성으로 클라이언트에 알립니다 (긴 글자 하나 대신 짧은 속성 여러 개):
--   Grid           Round, Size(한 변 칸 수), Rarity·Level(이번 판 장비), Name<좌석>·Bot<좌석>(승무원)
--   Grid/<종류 Id>  C<칸 번호> = 꽂은 승무원의 좌석 번호 (0 = 열린 빈 칸). 속성이 없는 칸은 닫힌 칸.
--                  Ra<좌석>·Lv<좌석> = 그 승무원의 이 종류 부품 레어도·레벨 ('각자 부품'일 때 사람만. 없으면 Grid 의 Rarity·Level)
--                  F<좌석> = true 면 그 승무원의 이 종류 부품이 피버 중 (비행 중 미션 판정마다 Round 가 정함, 없으면 피버 아님)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fever = require(Shared:WaitForChild("Fever"))
local Grid = require(Shared:WaitForChild("Grid"))
local Net = require(Shared:WaitForChild("Net"))

local Assembly = {}

Assembly.FolderName = "Grid"

-- 승무원 (Round 의 Member 중 여기서 쓰는 것)
type Member = {
	name: string,
	player: Player?,
	isBot: boolean,
	seat: number,
	left: boolean,
	loadout: { [string]: number },
	parts: { [string]: { rarity: number, level: number } }?, -- 자기 부품을 꽂는 사람만 (없으면 이번 판 장비)
}

type BotStep = { at: number, member: Member, typeId: string }

export type Session = {
	size: number,
	crew: { Member },
	rarity: number,
	cells: { [string]: { [number]: any } }, -- 종류 -> 열린 칸 -> 꽂은 승무원 (false = 빈 칸). 닫힌 칸은 없음
	placed: { [Member]: { [string]: number } }, -- 승무원 -> 종류 -> 꽂은 칸
	typeFolders: { [string]: Folder },
	folder: Folder,
	botSteps: { BotStep }, -- 봇이 부품을 꽂을 시각 (빠른 순)
	nextBot: number,
	announced: { [Member]: boolean },
	dirty: boolean, -- 꽂힌 부품이 바뀌어 합계를 다시 계산해야 함
	finished: boolean,
	rng: Random,
}

local function setCell(session: Session, typeId: string, cell: number, member: Member?)
	session.cells[typeId][cell] = member or false
	session.typeFolders[typeId]:SetAttribute("C" .. cell, if member then member.seat else 0)
	session.dirty = true
end

-- 그 종류의 열린 빈 칸 (번호 순)
local function emptyCells(session: Session, typeId: string): { number }
	local out: { number } = {}
	for cell, who in pairs(session.cells[typeId]) do
		if who == false then
			table.insert(out, cell)
		end
	end
	table.sort(out)
	return out
end

-- 부품 하나를 칸에 꽂음. 이미 그 종류를 꽂았으면 새 칸으로 옮김. "ok" 또는 안 된 까닭을 돌려줌.
local function put(session: Session, member: Member, typeId: string, cell: number): string
	local cells = session.cells[typeId]
	local who = cells[cell]
	if who == nil then
		return "closed"
	elseif who == member then
		return "same"
	elseif who ~= false then
		return "taken"
	end
	local mine = session.placed[member]
	local old = mine[typeId]
	if old ~= nil then
		setCell(session, typeId, old, nil)
	end
	mine[typeId] = cell
	setCell(session, typeId, cell, member)
	return "ok"
end

-- 아직 안 꽂은 종류를 빈 칸에 무작위로 꽂음. 꽂은 종류들을 돌려줌.
local function fill(session: Session, member: Member): { string }
	local placed: { string } = {}
	local mine = session.placed[member]
	for _, info in ipairs(Config.Parts.Types) do
		if mine[info.Id] == nil then
			local empty = emptyCells(session, info.Id)
			if #empty > 0 then
				put(session, member, info.Id, empty[session.rng:NextInteger(1, #empty)])
				table.insert(placed, info.Id)
			end
		end
	end
	return placed
end

-- 그 승무원의 그 종류 부품 레어도 (자기 부품이 없으면 이번 판 장비)
local function rarityOf(session: Session, member: Member, typeId: string): number
	local part = member.parts and member.parts[typeId]
	return if part then part.rarity else session.rarity
end

-- 기획서 '장착 연출': 영웅·전설 부품을 꽂으면 전원에게 알림. 한 판에 사람마다 처음 한 번만 (같은 장비라 매번 알리면 시끄러움).
local function announceRare(session: Session, member: Member, typeId: string)
	local rarity = rarityOf(session, member, typeId)
	if member.isBot or session.announced[member] or rarity < Config.Build.AnnounceRarity then
		return
	end
	session.announced[member] = true
	local info = Grid.typeInfo(typeId)
	local rarityName = Config.Parts.RarityNames[rarity] or ""
	Net.event("Announce"):FireAllClients(string.format("%s 님, %s %s 장착!", member.name, rarityName, if info then info.Name else typeId))
end

-- 지난 판의 그리드를 치움
function Assembly.clear(state: Instance)
	local old = state:FindFirstChild(Assembly.FolderName)
	if old then
		old:Destroy()
	end
end

-- 조립 시작: 종류마다 그리드를 만들고 승무원 수만큼 칸을 엶. 좌석이 정해진 뒤에 부릅니다.
-- rarity·level: 이번 판 장비 (데모 1은 전원 같은 장비). startAt: 조립이 시작하는 서버 시각 (봇이 꽂을 시각의 기준).
function Assembly.begin(state: Instance, roundNumber: number, crew: { Member }, rarity: number, level: number, rng: Random, startAt: number): Session
	Assembly.clear(state)
	local size = Grid.size(#crew)
	local folder = Instance.new("Folder")
	folder.Name = Assembly.FolderName
	folder:SetAttribute("Round", roundNumber)
	folder:SetAttribute("Size", size)
	folder:SetAttribute("Rarity", rarity)
	folder:SetAttribute("Level", level)
	for _, member in ipairs(crew) do
		folder:SetAttribute("Name" .. member.seat, member.name)
		folder:SetAttribute("Bot" .. member.seat, member.isBot)
	end

	local session: Session = {
		size = size,
		crew = crew,
		rarity = rarity,
		cells = {},
		placed = {},
		typeFolders = {},
		folder = folder,
		botSteps = {},
		nextBot = 1,
		announced = {},
		dirty = true,
		finished = false,
		rng = rng,
	}
	local function pick(n: number): number
		return rng:NextInteger(1, n)
	end
	for _, info in ipairs(Config.Parts.Types) do
		local typeFolder = Instance.new("Folder")
		typeFolder.Name = info.Id
		local cells: { [number]: any } = {}
		for _, cell in ipairs(Grid.openCells(size, #crew, pick)) do
			cells[cell] = false
			typeFolder:SetAttribute("C" .. cell, 0)
		end
		for _, member in ipairs(crew) do
			local part = member.parts and member.parts[info.Id]
			if part then
				typeFolder:SetAttribute("Ra" .. member.seat, part.rarity)
				typeFolder:SetAttribute("Lv" .. member.seat, part.level)
			end
		end
		session.cells[info.Id] = cells
		session.typeFolders[info.Id] = typeFolder
		typeFolder.Parent = folder
	end
	for _, member in ipairs(crew) do
		session.placed[member] = {}
		if member.isBot then
			for _, info in ipairs(Config.Parts.Types) do
				table.insert(session.botSteps, {
					at = startAt + rng:NextNumber(Config.Build.BotPlaceFrom, Config.Build.BotPlaceTo),
					member = member,
					typeId = info.Id,
				})
			end
		end
	end
	table.sort(session.botSteps, function(a: BotStep, b: BotStep): boolean
		return a.at < b.at
	end)
	-- 다 만든 뒤에 한 번에 붙여서, 클라이언트가 반쯤 만든 그리드를 보지 않게 함
	folder.Parent = state
	return session
end

-- 조립 화면에서 칸을 누름. typeId·cell 은 클라이언트가 보낸 값이라 모양부터 확인합니다.
-- "ok" | "same"(이미 그 칸) | "taken"(다른 사람 칸) | "closed"(닫힌 칸) | "type" | "cell" | "left" | "finished"
function Assembly.place(session: Session, member: Member, typeId: any, cell: any): string
	if session.finished then
		return "finished"
	elseif member.left or session.placed[member] == nil then
		return "left"
	elseif Grid.typeInfo(typeId) == nil or session.cells[typeId] == nil then
		return "type"
	elseif not Grid.isCell(session.size, cell) then
		return "cell"
	end
	local result = put(session, member, typeId, cell)
	if result == "ok" then
		announceRare(session, member, typeId)
	end
	return result
end

-- 조립 화면의 '남은 부품 자동으로 꽂기'. 꽂은 개수를 돌려줌.
function Assembly.autoPlace(session: Session, member: Member): number
	if session.finished or member.left or session.placed[member] == nil then
		return 0
	end
	local placed = fill(session, member)
	-- 한 번에 여러 개를 꽂으면 가장 귀한 부품으로 알림
	local best: string? = nil
	for _, typeId in ipairs(placed) do
		if best == nil or rarityOf(session, member, typeId) > rarityOf(session, member, best) then
			best = typeId
		end
	end
	if best then
		announceRare(session, member, best)
	end
	return #placed
end

-- 꽂을 시각이 된 봇 부품을 빈 칸에 꽂음
function Assembly.runBots(session: Session, now: number)
	local steps = session.botSteps
	while session.nextBot <= #steps and steps[session.nextBot].at <= now do
		local step = steps[session.nextBot]
		session.nextBot += 1
		local member = step.member
		if not session.finished and session.placed[member][step.typeId] == nil then
			local empty = emptyCells(session, step.typeId)
			if #empty > 0 then
				put(session, member, step.typeId, empty[session.rng:NextInteger(1, #empty)])
			end
		end
	end
end

-- 사람이 모두 꽂아 조립이 줄어들면, 아직 안 꽂은 봇 부품을 deadline 전까지 서둘러 꽂게 시각을 당김
function Assembly.hurryBots(session: Session, now: number, deadline: number)
	local steps = session.botSteps
	local window = math.max(0, deadline - now)
	local rest: { BotStep } = {}
	for i = session.nextBot, #steps do
		local step = steps[i]
		if step.at > deadline then
			step.at = now + session.rng:NextNumber() * window
		end
		table.insert(rest, step)
	end
	table.sort(rest, function(a: BotStep, b: BotStep): boolean
		return a.at < b.at
	end)
	for i, step in ipairs(rest) do
		steps[session.nextBot + i - 1] = step
	end
end

-- 판에 남아 있는 사람이 모두 종류마다 부품을 꽂았는지
function Assembly.allHumansDone(session: Session): boolean
	for _, member in ipairs(session.crew) do
		if not member.isBot and not member.left then
			local mine = session.placed[member]
			for _, info in ipairs(Config.Parts.Types) do
				if mine[info.Id] == nil then
					return false
				end
			end
		end
	end
	return true
end

-- 조립 시간이 끝남: 판에 남아 있는 승무원의 못 꽂은 부품을 빈 칸에 자동으로 꽂고, 더는 꽂지 못하게 닫음.
-- 승무원마다 자동으로 꽂은 개수를 돌려줌 (하나도 없으면 빠짐).
function Assembly.finish(session: Session): { [Member]: number }
	local filled: { [Member]: number } = {}
	for _, member in ipairs(session.crew) do
		if not member.left then
			local count = #fill(session, member)
			if count > 0 then
				filled[member] = count
			end
		end
	end
	session.finished = true
	return filled
end

-- 그 승무원이 그 종류 부품을 로켓에 꽂았는지 (판 도중에 나간 사람이 꽂아 둔 부품도 로켓에 남음)
function Assembly.hasPart(session: Session, member: Member, typeId: string): boolean
	local mine = session.placed[member]
	return mine ~= nil and mine[typeId] ~= nil
end

-- 부품 피버 표시: 그 승무원의 그 종류 부품이 피버 중인지 Grid/<종류>의 F<좌석> 속성에 씀 (바뀔 때만. 꺼지면 속성을 지움)
function Assembly.setFever(session: Session, member: Member, typeId: string, on: boolean)
	local folder = session.typeFolders[typeId]
	if folder == nil then
		return
	end
	local name = Fever.attribute(member.seat)
	if (folder:GetAttribute(name) == true) ~= on then
		folder:SetAttribute(name, if on then true else nil)
	end
end

-- 피버 표시를 모두 끔
function Assembly.clearFever(session: Session)
	for _, member in ipairs(session.crew) do
		for _, info in ipairs(Config.Parts.Types) do
			Assembly.setFever(session, member, info.Id, false)
		end
	end
end

-- 꽂힌 부품만 담은 승무원별 부품 (종류별 합계 계산용). 판 도중에 나간 사람이 꽂아 둔 부품도 로켓에 남습니다.
function Assembly.loadouts(session: Session): { { [string]: number } }
	local out: { { [string]: number } } = {}
	for _, member in ipairs(session.crew) do
		local loadout: { [string]: number } = {}
		for typeId in pairs(session.placed[member]) do
			loadout[typeId] = member.loadout[typeId] or 0
		end
		table.insert(out, loadout)
	end
	return out
end

return Assembly
