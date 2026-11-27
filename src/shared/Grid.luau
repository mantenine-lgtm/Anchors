--!strict
-- 부품 그리드 규칙 (순수 계산). 기획서 '부품 그리드':
-- 부품 종류마다 정사각형 그리드가 따로 있고, 판마다 그리드마다 승무원 수만큼 칸이 무작위로 열립니다.
-- 칸 번호는 1부터, 윗줄 왼쪽부터 가로로 셉니다 (4×4 면 1~4 가 윗줄).

local Config = require(script.Parent.Config)

local Grid = {}

-- 그리드 한 변의 칸 수: 칸 수가 승무원 × CellsPerCrew 이상인 가장 작은 정사각형 (MinSize 보다 작지 않게).
-- 6명까지 3×3, 10명까지 4×4, 16명까지 5×5, 24명까지 6×6, 32명까지 7×7, 42명까지 8×8, 54명까지 9×9, 100명이면 13×13.
function Grid.size(crew: number): number
	local need = math.max(crew, 1) * Config.Build.CellsPerCrew
	return math.max(Config.Build.MinSize, math.ceil(math.sqrt(need) - 1e-9))
end

-- 열린 칸 count 개를 무작위로 고름 (작은 번호부터 정렬해서 돌려줌). pick(n) 은 1..n 중 하나를 돌려주는 함수.
function Grid.openCells(size: number, count: number, pick: (number) -> number): { number }
	local total = size * size
	local cells: { number } = {}
	for i = 1, total do
		cells[i] = i
	end
	local want = math.clamp(math.floor(count), 0, total)
	for i = 1, want do
		local j = i - 1 + pick(total - i + 1)
		cells[i], cells[j] = cells[j], cells[i]
	end
	local chosen: { number } = {}
	for i = 1, want do
		chosen[i] = cells[i]
	end
	table.sort(chosen)
	return chosen
end

-- 부품 종류 정보 (Config.Parts.Types 의 한 줄). 없는 종류면 nil.
function Grid.typeInfo(typeId: any): { Id: string, Name: string }?
	if type(typeId) ~= "string" then
		return nil
	end
	for _, info in ipairs(Config.Parts.Types) do
		if info.Id == typeId then
			return info
		end
	end
	return nil
end

-- 칸 번호가 이 그리드의 칸인지 (클라이언트가 보낸 값이라 모양부터 확인)
function Grid.isCell(size: number, cell: any): boolean
	return type(cell) == "number" and cell == cell and cell % 1 == 0 and cell >= 1 and cell <= size * size
end

return Grid
