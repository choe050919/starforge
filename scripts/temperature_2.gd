extends Node
class_name Temperature2
## 씬 트리에 붙는 시스템 래퍼.
## - 의존성 주입
## - SimClock 신호 연결
## - 디버그/토글/프로파일

@export var enabled := true
@export var debug_log := false

# 규칙 파라미터 (Core로 전달)
# α = k/c (무차원, 상대값). 확산 블렌딩에 사용.
@export var alpha_ground := 0.9
@export var alpha_ice := 0.4
@export var alpha_uranium := 0.8

@export var c_ground := 1.0
@export var c_ice := 0.8
@export var c_uranium := 1.0

@export var uranium_power_c_per_s := 3.0

# 의존성
var _substance_store: SubstanceStore
var _phase_store: PhaseStore
var _temperature_store: TemperatureStore
var _index: GridIndex
var _clock : SimClock

# 코어
var _core: TemperatureCore

func setup(ss: SubstanceStore, ps: PhaseStore, ts: TemperatureStore, index: GridIndex, clock: SimClock) -> void:
	_substance_store = ss
	_phase_store = ps
	_temperature_store = ts
	_index = index
	_clock = clock

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_temperature_store", "_index", "_clock"]:
		var value = get(name)
		if value == null:
			push_error("[PhaseChange.setup]%s is null" % name)

	_core = TemperatureCore.new()
	_core.setup_rules()

	# 시계 신호 연결
	if _clock.has_signal("tick_sim"):
		_clock.connect("tick_sim", Callable(self, "_on_sim_tick"))

func _on_sim_tick(dt: float) -> void:
	# 시뮬레이션 틱마다 실행
	if not enabled:
		return

	var stats = _core.tick_fullscan(_phase_store, _substance_store, _temperature_store, _index, dt)
	if debug_log and stats.total > 0:
		print("[PhaseChange] Δ=", stats.total,
			" (ICE→WATER=", stats.ice_to_water, ", WATER→ICE=", stats.water_to_ice, ")")

# 런타임에서 파라미터를 바꿨다면 규칙 재적용
func rebuild_rules() -> void:
	if _core == null:
		_core = TemperatureCore.new()
	#_core.setup_rules()
