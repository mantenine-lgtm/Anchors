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
3. ▶ Play → Output 창(안 보이면 `View › Output`)에 아래 두 줄이 나오면 성공
   ```
   [Server] Rojo 연결 OK
   [Client] Rojo 연결 OK
   ```
4. `File › Publish to Roblox`로 게임 게시 → 다음부터 이 게임을 열어서 작업

## 매일 작업

1. VS Code로 `ROFLY` 폴더 열기 → 터미널에 `rojo serve`
2. Studio에서 게임 열기 → `Rojo` → `Connect`
3. VS Code에서 코드 수정·저장 → Studio에 바로 반영
