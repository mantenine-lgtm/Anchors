--!strict
-- 서버와 클라이언트가 주고받는 신호(RemoteEvent) 이름.
-- 계속 바뀌는 값(페이즈, 거리, 속도 등)은 ReplicatedStorage.RoundState 의 속성으로 보냅니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.FolderName = "Remotes"
Net.StateName = "RoundState"

Net.Events = {
	"Join", -- 클라 -> 서버: 탑승 버튼 (true/false)
	"Launch", -- 클라 -> 서버: 선장 발사 버튼 (누른 시각)
	"Launched", -- 서버 -> 클라: 발사됨 (타이밍 결과)
	"MissionStart", -- 서버 -> 클라: 미션 시작 (입력 순서, 제한 시간)
	"MissionInput", -- 클라 -> 서버: 미션 입력 (첫 입력 / 완료)
	"MissionResult", -- 서버 -> 클라: 미션 판정 (팀 성공률, 콤보, 내 결과)
	"UseItem", -- 클라 -> 서버: 아이템 사용
	"ItemUsed", -- 서버 -> 클라: 누가 아이템을 썼음 (클로즈업, 감사 버튼)
	"Thanks", -- 클라 -> 서버: 감사 버튼
	"ThanksFx", -- 서버 -> 클라: 하트 연출
	"FlightEnd", -- 서버 -> 클라: 비행 끝 (탈출/따라잡힘)
	"Results", -- 서버 -> 클라: 정산 내용
	"Announce", -- 서버 -> 클라: 한 줄 안내
	"Debug", -- 클라 -> 서버: 디버그 명령
	"PlacePart", -- 클라 -> 서버: 조립 화면에서 부품 꽂기 (종류 Id, 칸 번호). 이미 꽂은 종류면 그 칸으로 옮김
	"AutoPlace", -- 클라 -> 서버: 조립 화면의 '남은 부품 자동으로 꽂기'
	"PartProgress", -- 서버 -> 그 사람: 내 부품 6개의 레벨·경험치(비행 중 계속, 레벨업 포함) / 클라 -> 서버: 지금 값 다시 보내 달라
	"GachaPull", -- 클라 -> 서버: 부품 뽑기 (종류 Id, 10회 뽑기인지). 값은 서버가 그 사람의 최고 기록으로 정함
	"GachaResult", -- 서버 -> 그 사람: 뽑기 결과 (안 되면 까닭)
	"GachaLook", -- 클라 -> 서버: 도감에서 모양 바꾸기 (종류 Id, 부품 Id)
	"GachaNews", -- 서버 -> 모두: 누가 전설을 뽑았음 (축하 버튼)
	"GachaCheer", -- 클라 -> 서버: 축하 버튼 (알림 번호)
	"GachaCheered", -- 서버 -> 모두: 축하 수가 늘었음
}

local cache: { [string]: RemoteEvent } = {}

-- 서버가 시작할 때 한 번 호출
function Net.setupServer()
	local folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	for _, name in ipairs(Net.Events) do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Net.event(name: string): RemoteEvent
	local found = cache[name]
	if found then
		return found
	end
	local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
	local event = folder:WaitForChild(name) :: RemoteEvent
	cache[name] = event
	return event
end

return Net
