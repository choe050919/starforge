extends Node
class_name PhaseChange
## 씬 트리에 붙는 시스템 래퍼.
## - 의존성 주입
## - SimClock 신호 연결
## - 디버그/토글/프로파일

@export var enabled := true
@export var debug_log := false

# 히스테리시스/임계값 규칙 파라미터 (Core로 전달)
@export var hyst_c := 1        # ICE/WATER 공용 히스테리시스 폭
@export var melt_c := 27315        # ICE 쪽 융해 기준(상향)
@export var freeze_c := 27314     # WATER 쪽 응고 기준(하향)

# 의존성
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _temperature_store: TemperatureStore
var _index: GridIndex
var _clock : SimClock

# 코어
var _core: PhaseChangeCore

func setup(phase_store: PhaseStore, substance_store: SubstanceStore, temperature_store: TemperatureStore, index: GridIndex, clock: SimClock) -> void:
	_phase_store = phase_store
	_substance_store = substance_store
	_temperature_store = temperature_store
	_index = index
	_clock = clock

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_phase_store", "_substance_store", "_temperature_store", "_index", "_clock"]:
		var value = get(name)
		if value == null:
			push_error("[PhaseChange.setup]%s is null" % name)

	_core = PhaseChangeCore.new()
	_core.setup_rules(hyst_c, melt_c, freeze_c)

	## 시계 신호 연결
	#if _clock.has_signal("tick_sim"):
		#_clock.connect("tick_sim", Callable(self, "_on_sim_tick"))

func _on_sim_tick(dt: float) -> void:
	# 시뮬레이션 틱마다 실행
	if not enabled:
		return

	var stats = _core.tick_fullscan(_phase_store, _substance_store, _temperature_store, _index)
	if debug_log and stats.total > 0:
		print("[PhaseChange] Δ=", stats.total,
			" (ICE→WATER=", stats.ice_to_water, ", WATER→ICE=", stats.water_to_ice, ")")

# 런타임에서 파라미터를 바꿨다면 규칙 재적용
func rebuild_rules() -> void:
	if _core == null:
		_core = PhaseChangeCore.new()
	_core.setup_rules(hyst_c, melt_c, freeze_c)
