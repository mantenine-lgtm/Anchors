# 고블린 스프라이트 v1 (2026-11-04)

16방향, 칸 104×96, 피벗(52,82), 24fps. 변형 10종: 약탈자 raider_a~g, 투석병 slinger_a·b, 약탈 우두머리 chief.

- 시트 3장(Godot 텍스처 한도 16384px): `*_16dir_sheet.png` 기본(이동·공격), `*_react_16dir_sheet.png` 피격·넉백·기절·사망, `*_situ_16dir_sheet.png` 도주·도발·약탈·환호. 행 = 동작_방향(json `sheets[].rows`), 열 = 프레임
- `*_16dir_shadow.png`: 같은 칸 배치의 접지 그림자. 유닛 스프라이트보다 먼저(아래 레이어) 그림, 겹치면 max 합성
- `*_16dir_sheet.json`: frames, loop, attackHitFrames, rootMotion, hitPoint.perFrame, footContactFrames, groundSpeedPxPerFrame, (투석병) projectileSpawn
- `stone_flight.png`: 투석 돌 16×16 4프레임, 그림자는 궁수 투사체 공용 그림자
- 피격 3종·사망 4종은 json `hurtPool`·`deathPool`에서 무작위 선택, 상황 동작은 `situational`
