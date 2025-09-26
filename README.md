마지막 수정 날짜: 2025-09-26

# StarForge

## 프로젝트 개요
StarForge는 Godot 4.5 기반의 2D 격자 시뮬레이션 프로젝트로, 행성 표면을 구성하는 물질과 생태를 실시간으로 계산하고 시각화하는 것을 목표로 한다. 현재 월드 생성과 데이터 계층, 여러 시뮬레이션 시스템, 그리고 플레이어 도구/오버레이 UI가 맞물려 동작하는 단계에 있다.

## 현재 구현된 구성요소
### 데이터 계층과 월드 초기화
- `World` 노드는 월드 생성 결과를 수신해 타일맵, 데이터 계층, 각종 시스템, 그리고 카메라/오버레이 레이아웃까지 한 번에 구성한다.【F:world/world.gd†L21-L188】
- `DataLayer`는 격자 색인, 물질, 상(phase), 질량, 온도, 광량 스토어를 보유하고 일괄 업데이트 API를 제공해 시뮬레이션 결과를 안전하게 반영한다.【F:datalayer/data_layer.gd†L1-L120】

### 시뮬레이션 시스템 현황
- **온도**: `Temperature` 시스템은 `TemperatureCore`를 통해 4방 전도, 물질별 열전도율/비열, 저질량 완화 등을 포함한 풀스캔 확산을 수행한다.【F:systems/temperature/temperature.gd†L1-L50】【F:systems/temperature/temperature_core.gd†L1-L155】
- **액체**: `Liquid` 시스템은 질량 보존을 기반으로 물 셀을 이동시키고, 상/물질 ID 및 온도까지 일관되게 동기화한다.【F:systems/liquid/liquid.gd†L1-L160】
- **광원**: `Light` 시스템은 상단 경계광과 물질별 투과/차광 규칙을 사용해 칼럼 단위 복사조도를 재계산하고, 글로벌 스케일링으로 비용을 줄인다.【F:systems/light.gd†L1-L190】
- **식물/에이전트**: 월드 초기화 시 식물 시스템은 토양 판별과 광량 샘플러를 주입받고, 크리터 스포너는 수생 생물과 건설/파괴 AI를 월드 데이터에 연결한다.【F:world/world.gd†L115-L184】【F:scripts/critter_spawner.gd†L1-L99】

### 입력, 도구, UI
- `InputController`는 패닝/줌, 오버레이 토글, 도구 선택과 클릭을 해석해 대응 시스템에 신호로 전달한다.【F:scripts/input_controller.gd†L1-L88】
- `ToolManager`는 진공, 물고기 소환, 식물 심기 도구를 enum으로 관리하고 요청 신호를 방송한다.【F:systems/tool_manager.gd†L1-L73】
- HUD는 재생/배속, 수면·온도 오버레이 토글, 도구 버튼을 제공하며 ToolManager와 상태를 동기화한다.【F:UI/hud.gd†L1-L112】
- `OverlayManager`는 열지도, 발열원, 광량, 내비게이션 등 여러 오버레이를 토글해 UI와 렌더를 묶는다.【F:visualsync/overlay_manager.gd†L1-L71】
- `HoverManager`와 타일 정보 HUD가 연계되어 마우스 위치 셀을 추적하고 세부 데이터를 노출한다.【F:scripts/hover_manager.gd†L1-L23】【F:world/world.gd†L149-L188】

## 추후 정비 필요 (간략)
- Durability 파괴 신호가 `TileChange.queue_destroy`로 연결되어 있으나 대상 메서드가 아직 구현되지 않았다.【F:world/world.gd†L77-L80】【F:systems/tile_change.gd†L24-L41】
- Gas 시스템 스크립트가 비어 있어 현재는 사용되지 않는다.【F:systems/gas.gd†L1-L1】
- `TileChange.replace_cell`가 교체 타일을 적용하지 못한다는 TODO 상태다.【F:systems/tile_change.gd†L28-L37】
