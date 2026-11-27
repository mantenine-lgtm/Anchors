--!strict
-- 숫자를 화면 글자로 바꿈

local Fmt = {}

-- 1234567 -> "1,234,567"
function Fmt.comma(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, #s - 2) .. out
		s = string.sub(s, 1, #s - 3)
	end
	out = s .. out
	if n < 0 then
		out = "-" .. out
	end
	return out
end

-- 거리: 850 m / 7.52 km / 432.1 km / 5,230 km / 23.9만 km
function Fmt.km(km: number): string
	if km < 1 then
		return string.format("%d m", math.floor(km * 1000))
	elseif km < 100 then
		return string.format("%.2f km", km)
	elseif km < 1000 then
		return string.format("%.1f km", km)
	elseif km < 10000 then
		return Fmt.comma(km) .. " km"
	end
	return string.format("%.1f만 km", km / 10000)
end

-- 속도: 320 m/s / 1.25 km/s / 1,200 km/s
function Fmt.speed(kmPerSec: number): string
	local ms = kmPerSec * 1000
	if ms < 1000 then
		return string.format("%d m/s", math.floor(ms + 0.5))
	elseif kmPerSec < 100 then
		return string.format("%.2f km/s", kmPerSec)
	end
	return Fmt.comma(kmPerSec) .. " km/s"
end

-- 남은 시간: 0:07
function Fmt.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- 0.85 -> "85%"
function Fmt.percent(ratio: number): string
	return string.format("%d%%", math.floor(ratio * 100 + 0.5))
end

-- 낱말 뒤에 붙는 조사: Fmt.josa("터보 엔진", "을", "를") -> "터보 엔진을", Fmt.josa("구원 연료", "을", "를") -> "구원 연료를".
-- withFinal 은 마지막 글자에 받침이 있을 때, withoutFinal 은 없을 때. "으로/로" 는 받침이 ㄹ 이어도 "로".
-- 한글로 끝나지 않으면(영문·숫자) 받침 없음으로 봅니다.
function Fmt.josa(word: string, withFinal: string, withoutFinal: string): string
	local last: number? = nil
	for _, code in utf8.codes(word) do
		last = code
	end
	local final = 0
	if last ~= nil and last >= 0xAC00 and last <= 0xD7A3 then
		final = (last - 0xAC00) % 28
	end
	local hasFinal = final ~= 0
	if withFinal == "으로" and final == 8 then
		hasFinal = false -- ㄹ 받침: "웜홀로"
	end
	return word .. (if hasFinal then withFinal else withoutFinal)
end

return Fmt
