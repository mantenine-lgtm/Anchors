궁수 v7 렌더러·출력 스크립트 사본(2026-11-07, 궁수 스프라이트 스레드 컨테이너 scratchpad/v7 에서 복사).
- fig4.py / fig8.py: 3D 타원체 z-버퍼 렌더러 + 2px 도트 후처리. fig8 v7: 몸 전체 회전 gpitch/groll/gpiv/goff, 머리 hdrop/hturn, vial(물약병), _solid_prop(얇은 활대 굳힘), 석궁 sp['xbow'].
- anim8.py: 포즈·키포즈·MOVES, set_weapon('bow'|'longbow'|'runebow'|'shortbow'|'crossbow'), GK='AG'(활)/'XG'(석궁) 전투 준비자세.
- astages7.py: 궁수 1~5단계 정지 스펙(v3 민첩형). setload.py: load_set('a{n}_{bow}'|'xstage{n}').
- exportw.py: 기본 동작 16방향 시트. 실행: PYTHONDONTWRITEBYTECODE=1 CELL_W=104 CELL_H=96 CELL_FOOT=82 python3 exportw.py a3_longbow out/
- react8.py + exportr.py: 반응 동작 16종(+death_side). REUSE=<이전 출력 폴더> 지정 시 안 바뀐 동작 행 재사용. react8_v1.py는 13종 첫 버전.
- fxrecall.py: 귀환 발밑 빛 recall_fx_back/front 36f 공용 시트.
- rtest.py / rtest2.py: 키프레임·방향 검수 시트. rebuild*.sh: 25세트 병렬 일괄 출력(xargs -P 4). finr2.py: 게임 스테이징·미리보기 합본 webp·data.js 반영.
