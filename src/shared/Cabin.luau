--!strict
-- 선실 배치 (순수 계산). 서버(World·Seating·Bots)와 클라이언트(CameraRig)가 같이 씁니다.
-- 선실은 승무원이 걸어다니는 둥근 방이고 4면으로 나뉩니다:
--   +Z·-Z: 외창 (둥근 벽)   +X: 진행도 전광판   -X: 부품 장착판
-- 전광판 두 개는 둥근 벽 앞에 세운 평평한 벽(x = ±PanelWallX)에 붙어 있어서, 방 바닥은 양옆이 잘린 원입니다.

local Config = require(script.Parent.Config)

local W = Config.World

local Cabin = {}

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5)) -- 해바라기 씨 배치 각도 (약 137.5도)

-- 승무원 count 명 중 index 번의 탑승 자리 (바닥 위 한 점). 1번은 방 가운데(선장)이고 번호가 클수록 바깥쪽.
-- 해바라기 씨처럼 퍼뜨려서 인원이 많아도 고르게 떨어져 섭니다 (10명이면 약 14 스터드, 100명이면 약 4.6 스터드 간격).
function Cabin.spotPosition(index: number, count: number): Vector3
	local n = math.max(count, 1)
	local i = math.clamp(index, 1, n)
	local radius = W.SpotRadius * math.sqrt((i - 1) / n)
	local theta = (i - 1) * GOLDEN_ANGLE
	return Vector3.new(math.sin(theta) * radius, W.CabinFloorY, math.cos(theta) * radius)
end

-- 탑승 자리의 방향: 가까운 외창을 바라봄 (z 가 0 이상이면 +Z 외창, 아니면 -Z 외창)
function Cabin.spotCFrame(index: number, count: number): CFrame
	local position = Cabin.spotPosition(index, count)
	local facing = if position.Z >= 0 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
	return CFrame.lookAt(position, position + facing)
end

-- 점이 선실 안인지. margin 만큼 넉넉하게 봄 (음수면 그만큼 벽에서 떨어진 안쪽만).
function Cabin.contains(position: Vector3, margin: number?): boolean
	local m = margin or 0
	if position.Y < W.CabinFloorY - 1 - m or position.Y > W.CabinCeilY + m then
		return false
	end
	local flat = math.sqrt(position.X * position.X + position.Z * position.Z)
	return flat <= W.CabinRadius + m and math.abs(position.X) <= W.PanelWallX + m
end

return Cabin
