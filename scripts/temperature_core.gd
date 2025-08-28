extends RefCounted
class_name TemperatureCore
## 순수 온도 로직만 담당. 씬 트리와 무관.
## - 단위: cK (int). 계산은 float로 후 round.
## - 외부 의존: GridIndex, TemperatureStore
## - 초기화는 타일 타입 배열을 받아 간단히 처리(후속에 중앙 상수화 예정).

# ---- 외부 주입 ----
var _index: GridIndex
var _store: TemperatureStore

# ---- 내부 상태 ----
var _size: Vector2i
var _solid: PackedByteArray = PackedByteArray()      # 1=전달, 0=비활성(공기 등)
var _alpha: PackedFloat32Array = PackedFloat32Array()# α = k/c (상대)
#var _uranium_cells: PackedInt32Array = PackedInt32Array()

# ---- 파라미터 ----
# 외부 enum과 일치해야 함: SubstanceId
const SID = { "VACUUM":0, "ICE":1, "GROUND":2, "URANIUM":3, "WATER":4 }

# 재료별 파라미터 (상대값)
# 열전도
var k_ground := 0.9
var k_ice := 0.4
var k_uranium := 0.8
# 열용량
var c_ground := 1.0
var c_ice := 0.8
var c_uranium := 1.0

# 초기 온도(°C)
#var t_ground_init_c := 12.0
#var t_ice_init_c := -5.0
#var t_uranium_init_c := 12.0

# 우라늄 발열(cK/s)  ← 기존 °C/s를 그대로 숫자만 100배 하면 됨.
var uranium_power_ck_per_sec: int = 300  # 기본: 3.0 °C/s → 300 cK/s

# 4방 탐색
const DIRS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
