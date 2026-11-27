# ROFLY · BREAKLINE 구현 노트

디자인과 비교 기준은 [DESIGN.md](DESIGN.md), 정면·측면과 바이옴 콘셉트는 [concepts](concepts/)에 있습니다.

## RocketShell.luau · CITADEL

폭이 넓은 팔각 하부 장갑, 원형 선실과 이어지는 장갑 테두리, 뒤로 물러난 비대칭 노즈 능선을 조립합니다. 추진부는 직사각형 카세트 두 줄에 벨을 3개씩 배치했습니다. 기본 반경 38에서 최대 외곽 반경은 49.417스터드, `NoseTip` 최고점은 Y=275.498입니다.

- **156 BaseParts**, 조명 0개입니다.
- 총 **14파트**에 `Heat`를 설정합니다. `UpperHull` 1개는 0.30, `LeadingEdge` 2개는 0.50, `ForeCrown` 3개는 0.63, `AftCrown` 3개는 0.74, `CrownCheek` 4개는 0.87, `NoseTip` 1개는 1.00입니다.
- 기존 `World.buildRocket` 호출에서 반환되는 `LowerHull`를 `PrimaryPart`로 사용합니다. `UpperHull`과 `NoseTip`은 모델의 직속 파트입니다. 엔진 벨 하단은 `mountY`에 닿고 카세트를 포함한 추진부는 `hullRadius - 6` 안에 들어갑니다.
- 반경을 36 이하로 낮출 때는 `Config.World.CabinRadius`도 조정해야 합니다. 기존 `World`의 선실 계산에는 `CabinRadius < HullRadius`와 `(CabinRadius + HullRadius) / 2 > PanelWallX + 1` 조건이 필요합니다.

## LaunchPad.luau · LAST GATE

어긋난 두 콘크리트 교각을 상부 헤더와 접근 암으로 연결합니다. 발사대 옆의 사선 방열 유도로, 평평한 유도선, 반대편 계단형 운영동과 밀폐 서비스 베이가 한 단지를 이룹니다.

- **77 BaseParts**, **SpotLight 2개**입니다. `World`의 `Plaza`와 `Spawn`을 포함하면 79파트입니다.
- 기본 배치에서 관문의 최고점은 194.35스터드, 스폰 중심과 가장 가까운 외장 사이 거리는 23스터드입니다. 최대 반경은 146.780스터드, 최저점은 Y=−0.6입니다. `Mount` 윗면은 `mountY`, `TowerArm` 안쪽 끝은 X=`hullRadius + 1`입니다.
- `PlanetMood`가 `RimLight` 13개, `ControlWindow` 1개, `MastLamp` 2개와 그 안의 SpotLight를 행성별 색으로 바꿉니다.

## PlanetProps.luau · 여섯 바이옴

갈라진 칼데라, 두 겹의 빙하 능선, 펼쳐진 정글 수관, 기울어진 사암 다리, 발광 결정의 틈, 잔디 처마와 가로 등대로 각 바이옴의 실루엣을 나눴습니다. 반환 반경은 기존 배치 간격과 맞추고, 모양과 크기 변이는 호출자가 주는 `rng`로 결정합니다.

| 종류 | 최소 | 평균 | 최대 |
| --- | ---: | ---: | ---: |
| rock | 2 | 2 | 2 |
| spike | 3 | 3 | 3 |
| pool | 3 | 3 | 3 |
| pine | 4 | 4 | 4 |
| tree | 3 | 3 | 3 |
| mushroom | 3 | 3 | 3 |
| bush | 3 | 3 | 3 |
| cactus | 4 | 4 | 4 |
| deadTree | 4 | 4 | 4 |
| crystal | 4 | 4 | 4 |
| palm | 4 | 4 | 4 |
| volcano | 13 | 13 | 13 |
| mountain | 12 | 12 | 12 |
| giantTree | 15 | 15 | 15 |
| mesa | 14 | 14 | 14 |
| arch | 11 | 11 | 11 |
| spire | 12 | 12 | 12 |
| seaStack | 13 | 13 | 13 |
| lighthouse | 12 | 12 | 12 |

| 행성 | 전체 설정 수량 기준 BaseParts | 소품 1개당 평균 |
| --- | ---: | ---: |
| lava | 260 | 2.53 |
| ice | 334 | 3.21 |
| jungle | 398 | 2.89 |
| desert | 362 | 3.17 |
| crystal | 354 | 3.32 |
| ocean | 316 | 3.32 |

소품 평균은 종류 기준 3.36파트, 설정 수량으로 가중하면 3.07파트입니다. 등대는 PointLight를 1개씩 생성합니다. 기존 `PlanetMood`는 Neon으로 만든 `Pool`, `Cap`, `Crystal`을 찾습니다. 비발광 파트의 런타임 그림자는 `Planet.luau`가 제어합니다.

## 검증

반경 30~45에서 외장 방위각, 창 높이와 범위, 추진부 반경, 발사장 통로, 파트 플래그를 좌표와 Roblox API 모형으로 확인했습니다. 소품은 여러 표면 기울기와 배율에서 시드 재현성, 이름, 행성별 최대 합계를 확인했습니다. 세 PNG는 디자인 단계에 만든 오프라인 프리뷰입니다. Studio 렌더링과 기기별 프레임률은 실제 통합 환경에서 확인할 수 있습니다.
