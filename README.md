# Anchors

ROFLY(로블록스FLY) 게임 저장소. [Rojo](https://rojo.space)로 VS Code에서 짠 코드를 Roblox Studio에 실시간 동기화합니다.

## 자료

- 기획서(온라인, 최신본): https://claude.ai/artifact/BPTtwcD7fyrYZ7Ac6vHFE4
- `docs/concept-images`: 챕터별 콘셉트 이미지 (`old-v1`은 이전 버전)
- `docs/diagrams`: 로켓 부품 그리드 다이어그램

## 폴더 구조

| 폴더 | Studio 위치 | 용도 |
|---|---|---|
| `src/server` | ServerScriptService › Server | 서버 코드 |
| `src/client` | StarterPlayer › StarterPlayerScripts › Client | 클라이언트 코드 |
| `src/shared` | ReplicatedStorage › Shared | 서버·클라 공용 모듈 |

- 파일 이름 규칙: `이름.server.luau` = Script, `이름.client.luau` = LocalScript, `이름.luau` = ModuleScript
- **코드는 VS Code에서만 수정.** Studio에서 고친 코드는 파일에 안 남습니다.
- 맵·모델·UI 배치는 Studio에서 작업하고 `File › Publish to Roblox`로 저장합니다.

## 처음 세팅 (맥, 1회)

1. **Roblox Studio**: [create.roblox.com](https://create.roblox.com)에서 Studio 다운로드 → 설치 → 로그인
2. **VS Code**: [code.visualstudio.com](https://code.visualstudio.com)에서 다운로드 → 앱을 `응용 프로그램` 폴더로 이동
3. **Git**: 터미널 앱 열고 실행 (이미 설치됐다고 나오면 통과)
   ```sh
   xcode-select --install
   ```
4. **Rokit** (Rojo 설치 도구): 실행 후 터미널 창 닫고 새로 열기
   ```sh
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```
5. **프로젝트 받기 + Rojo 설치**: Studio는 끈 상태에서 (작업 폴더는 `~/ROFLY`)
   ```sh
   git clone https://github.com/mantenine-lgtm/Anchors.git ~/ROFLY
   cd ~/ROFLY
   rokit install          # Rojo 설치 (물어보면 y)
   mkdir -p ~/Documents/Roblox/Plugins
   rojo plugin install    # Studio용 Rojo 플러그인 설치
   ```
6. **VS Code 확장**: VS Code `File › Open Folder` → `ROFLY` 폴더 열기 → 오른쪽 아래 권장 확장 알림에서 설치
   (안 뜨면 확장 탭에서 `Luau Language Server` 검색 → 설치. 자동완성·오류 표시용)

## 연결 확인

1. VS Code `Terminal › New Terminal` → `rojo serve`
2. Studio 실행 → Baseplate 새로 만들기 → 상단 `Plugins` 탭 → `Rojo` → `Connect` (접근 허용 물으면 허용)
   - **▶ Play 전, 편집 상태에서 연결해야 합니다.** 플레이 중에 누르면 `Http requests can only be executed by game server` 오류가 납니다.
   - 연결되면 Explorer의 ServerScriptService 안에 `Server › Main`이 생깁니다.
3. ▶ Play → Output 창(안 보이면 `Script` 탭에서 열기)에 아래 두 줄이 나오면 성공
   ```
   [ROFLY] 데모 1 서버 시작
   [ROFLY] 데모 1 클라이언트 시작
   ```
4. `File › Publish to Roblox`로 게임 게시 → 다음부터 이 게임을 열어서 작업

## 데모 1 해 보기 (비행이 재밌는가)

발사장·로켓은 코드가 ▶ Play 때 만듭니다(회색 상자). Studio 맵에 따로 놓을 것은 없습니다.

1. `rojo serve` → Studio에서 `Rojo › Connect` → ▶ Play
2. 한 판 흐름: 탑승(30초, 모두 타면 5초) → 조립(10초) → 카운트다운(10초) → 비행 → 정산(20초) → 다시 탑승
   - 비행 연출: 대기권(100 km까지)에서는 빠를수록 코와 외창 바깥면이 빨갛게 달아오르고 화면이 흔들립니다. 별빛 줄기는 대기권을 벗어난 뒤에만 나옵니다(보통 장비는 대기권 안에서 끝나므로, 보려면 디버그 패널의 `장비` 버튼으로 `전설 Lv10`을 고릅니다. 다음 판부터). 수치는 `Config.Atmosphere`
3. 조작
   - 탑승: 화면 아래 `탑승` 버튼
   - 미션: 화면에 뜬 순서대로 방향키(또는 WASD)와 스페이스(점프). 터치 기기는 화면 버튼
     (WASD가 안 먹으면 방향키를 쓰거나 한/영 키로 영문 입력 상태로 바꿉니다. 채팅을 치는 동안에는 미션 키가 눌리지 않습니다)
   - 선장 발사: 카운트다운이 0이 되는 순간 스페이스 또는 `발사!` 버튼 (안 누르면 자동 발사)
   - 부스터: 비행 중 화면 왼쪽 메뉴의 버튼 6개(구원 연료·터보 엔진·중력 새총·웜홀·황금 항로·공명 코어). 누르면 바로 쓰고 티켓 1장이 듭니다.
     종류마다 한 비행에 로켓 전체에서 한 번(먼저 누른 사람)이고, 구원 연료는 위기(충격파 접근) 때만 켜집니다.
     버튼 아래 줄: `티켓 1`(쓸 수 있음) · `위기 때만` · `티켓 없음` · 남은 초(효과 중) · `적용 중`(황금 항로) · `사용됨`.
     PC는 버튼에 마우스를 올리면 효과 설명이 나옵니다. 처음 들어오면 티켓 3장(임시)이고, 디버그 패널의 `티켓 +1`로 더 받을 수 있습니다
   - 감사: 다른 사람(봇)이 부스터를 쓰면 뜨는 `고마워요!` 버튼
   - 시점: 오른쪽 위 `시점` 버튼으로 선실 ↔ 바깥
4. 혼자 하면 빈자리는 봇이 채웁니다(기본 10명).
5. 디버그 패널: 오른쪽 위 `디버그` 버튼 (Studio와 게임 주인에게만 보임)
   - 다음 단계로 넘기기, 티켓 +1, 코인 +1000, 위기 구간으로 건너뛰기, 봇이 구원 연료 사용
   - 승무원 수·장비 바꾸기(다음 판부터), 봇 실력 바꾸기(다음 미션부터), 지표 출력(Output 창)
   - 선실 화면은 승무원 10명(기본)에 맞춰져 있습니다. 20명·50명은 수치를 보는 용도입니다. 25명부터는 한 줄 안내가 전광판에 바짝 붙고(휴대폰에서는 조금 겹침), 50명에서는 한 줄 안내가 전광판 아래쪽에 겹치고 윗줄 좌석이 전광판을 일부 가립니다.
6. 휴대폰 화면은 Studio `Test › Device`에서 기기를 골라 확인합니다.
7. 수치는 모두 `src/shared/Config.luau` 한 파일에 있습니다. 고치고 저장하면 다음 ▶ Play부터 반영됩니다.
8. 소리는 Roblox 내장 임시 소리입니다. 일부는 안 날 수 있습니다(Output에 경고만 뜸).

## 매일 작업

1. VS Code로 `ROFLY` 폴더 열기 → 터미널에 `rojo serve`
2. Studio에서 게임 열기 → `Rojo` → `Connect` (▶ Play 전에)
3. VS Code에서 코드 수정·저장 → Studio에 바로 반영
