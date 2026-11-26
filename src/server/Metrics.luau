-- 자동 지표 (데모 판단용): 판 수, 티켓 사용, 감사 누름, 미션 성공률.
-- 저장하지 않고 서버가 켜져 있는 동안만 셉니다. 판이 끝날 때마다 Output 에 한 줄씩 찍습니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fmt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fmt"))

local Metrics = {}

export type RoundInfo = {
	round: number,
	km: number,
	seconds: number,
	humans: number,
	bots: number,
	escaped: boolean,
	missions: number,
	teamRate: number, -- 팀 평균 성공률
	humanAttempts: number,
	humanSuccesses: number,
	ticketsUsed: number,
	thanks: number,
	launch: string,
}

local totals = {
	rounds = 0,
	ticketsUsed = 0,
	thanks = 0,
	humanAttempts = 0,
	humanSuccesses = 0,
	bestKm = 0,
	seconds = 0,
}

local function rate(successes: number, attempts: number): string
	if attempts <= 0 then
		return "-"
	end
	return Fmt.percent(successes / attempts)
end

function Metrics.endRound(info: RoundInfo)
	totals.rounds += 1
	totals.ticketsUsed += info.ticketsUsed
	totals.thanks += info.thanks
	totals.humanAttempts += info.humanAttempts
	totals.humanSuccesses += info.humanSuccesses
	totals.seconds += info.seconds
	totals.bestKm = math.max(totals.bestKm, info.km)
	print(string.format(
		"[지표] %d판 | 거리 %s | %d초 | 사람 %d + 봇 %d | 미션 %d회, 팀 성공률 %s, 사람 성공률 %s | 티켓 사용 %d | 감사 %d | 발사 %s%s",
		info.round,
		Fmt.km(info.km),
		math.floor(info.seconds + 0.5),
		info.humans,
		info.bots,
		info.missions,
		Fmt.percent(info.teamRate),
		rate(info.humanSuccesses, info.humanAttempts),
		info.ticketsUsed,
		info.thanks,
		info.launch,
		if info.escaped then " | 탈출 성공" else ""
	))
end

function Metrics.summary(): string
	return string.format(
		"[지표 합계] 판 수 %d | 최고 %s | 평균 비행 %d초 | 사람 미션 성공률 %s | 티켓 사용 %d | 감사 누름 %d",
		totals.rounds,
		Fmt.km(totals.bestKm),
		if totals.rounds > 0 then math.floor(totals.seconds / totals.rounds + 0.5) else 0,
		rate(totals.humanSuccesses, totals.humanAttempts),
		totals.ticketsUsed,
		totals.thanks
	)
end

function Metrics.print()
	print(Metrics.summary())
end

return Metrics
