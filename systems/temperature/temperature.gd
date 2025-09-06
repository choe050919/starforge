## 씬 트리에 붙는 시스템 래퍼.
## - 의존성 주입
## - SimClock 신호 연결
## - 디버그/토글/프로파일
extends Node
class_name Temperature

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled := true
@export var debug_log := false

# ── 의존성 ─────────────────────────────────────────────────────────
var _substance_store: SubstanceStore
var _phase_store: PhaseStore
var _temperature_store: TemperatureStore
var _mass_store: MassStore
var _index: GridIndex
var _clock : SimClock
var _rules: SubstanceRuleCache

# 코어
var _core: TemperatureCore

func setup(
	ss: SubstanceStore,
	ps: PhaseStore,
	ts: TemperatureStore,
	ms: MassStore,
	index: GridIndex,
	clock: SimClock,
	rule_cache: SubstanceRuleCache
) -> void:
	_substance_store = ss
	_phase_store = ps
	_temperature_store = ts
	_mass_store = ms
	_index = index
	_clock = clock
	_rules = rule_cache

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_substance_store", "_phase_store", "_temperature_store", "_mass_store", "_index", "_clock"]:
		var value = get(name)
		if value == null:
			push_error("[Temperature.setup]%s is null" % name)

	_core = TemperatureCore.new()
	_core.setup_thermal_from_cache(_rules)

# ── 틱 ─────────────────────────────────────────────────────────────
func _on_sim_tick(dt: float) -> void:
	if not enabled: return

	var stats := _core.tick_fullscan(_temperature_store, _substance_store, _mass_store, _index, dt)

	_temperature_store.begin_write()
	if stats.is_empty(): push_error("[Temperature] empty array"); return

	for i in stats.size():
		var t: int = stats[i]
		_temperature_store.set_by_index(i, t)

	_temperature_store.commit()

	if debug_log and stats:
		pass
		#var avg := float(stats.get("avg_delta_c", 0.0))
		#var mx  := float(stats.get("max_abs_delta_c", 0.0))
		#print("[Temperature] avgΔ=%.2f°C, max|Δ|=%.2f°C" % [avg, mx])
