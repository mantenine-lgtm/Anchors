--!strict
-- 부스터(비행 중에 쓰는 현질 아이템 6종) 목록을 찾아 쓰기 쉽게 감싼 것. 수치는 Config.Boosters 에 있습니다.

local Config = require(script.Parent.Config)

local Boosters = {}

export type Info = {
	Id: string,
	Name: string,
	Cost: number,
	Seconds: number,
	Value: number,
	Desc: string,
}

-- 왼쪽 메뉴에 놓이는 순서
Boosters.List = Config.Boosters.List :: { Info }

local byId: { [string]: Info } = {}
for _, info in ipairs(Boosters.List) do
	byId[info.Id] = info
end

-- 없는 Id 면 nil (클라이언트가 보낸 값은 이것으로 걸러 냄)
function Boosters.get(id: any): Info?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- 효과가 끝나는 시각을 서버가 알려 주는 속성 이름 (비행 시간 기준 초, 없으면 -1)
function Boosters.untilAttribute(id: string): string
	return "Until_" .. id
end

-- 이번 비행에 이미 썼는지 (로켓 전체에서 종류마다 1번)
function Boosters.usedAttribute(id: string): string
	return "Used_" .. id
end

-- 누가 썼는지 (표시 이름)
function Boosters.byAttribute(id: string): string
	return "By_" .. id
end

return Boosters
