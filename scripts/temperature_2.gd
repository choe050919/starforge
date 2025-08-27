extends Node
class_name Temperature2
## 씬 트리에 붙는 시스템 래퍼.
## - 의존성 주입
## - SimClock 신호 연결
## - 디버그/토글/프로파일

@export var enabled := true
@export var debug_log := false

# 의존성
var _temperature_store: TemperatureStore
var _index: GridIndex
var _clock : SimClock

# 코어
var _core: TemperatureCore

func setup(ts: TemperatureStore, index: GridIndex, clock: SimClock) -> void:
	_temperature_store = ts
	_index = index
	_clock = clock

	_core = TemperatureCore.new()
	#_core.setup_rules()

	# 시계 신호 연결
	if _clock.has_signal("tick_sim"):
		_clock.connect("tick_sim", Callable(self, "_on_sim_tick"))

func _on_sim_tick(dt: float) -> void:
	# 시뮬레이션 틱마다 실행
	if not enabled:
		return
	if _temperature_store == null or _index == null or _clock == null:
		return

	#var stats = _core.tick_fullscan(_phase_store, _substance_store, _temperature, _index)
	#if debug_log and stats.total > 0:
		#print("[PhaseChange] Δ=", stats.total,
			#" (ICE→WATER=", stats.ice_to_water, ", WATER→ICE=", stats.water_to_ice, ")")


# 런타임에서 파라미터를 바꿨다면 규칙 재적용
func rebuild_rules() -> void:
	if _core == null:
		_core = TemperatureCore.new()
	#_core.setup_rules()
