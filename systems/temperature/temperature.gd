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
var _data: DataLayer
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
	data: DataLayer,
	clock: SimClock,
	rule_cache: SubstanceRuleCache
) -> void:
	_data = data
	_substance_store = _data.substance
	_phase_store = _data.phase
	_temperature_store = _data.temperature
	_mass_store = _data.mass
	_index = _data.index
	_clock = clock
	_rules = rule_cache

	for _name in ["_substance_store", "_phase_store", "_temperature_store", "_mass_store", "_index", "_clock"]:
		var value = get(_name)
		if value == null:
			push_error("[Temperature.setup]%s is null" % _name)

	_core = TemperatureCore.new()
	_core.setup_thermal_from_cache(_rules)

# ── 틱 ─────────────────────────────────────────────────────────────
func _on_sim_tick(dt: float) -> void:
	if not enabled: return

	var stats := _core.tick_fullscan(_temperature_store, _substance_store, _mass_store, _index, dt)

	# TODO write-commit은 DataLayer에서 하도록 수정필요.

	_data.set_bulk_temp(stats)

	# DEPRECATED
	#_temperature_store.begin_write()
	#if stats.is_empty(): print("[Temperature] empty array"); return
#
	#for i in stats.size():
		#var t: int = stats[i]
		#_temperature_store.set_by_index(i, t)
#
	#_temperature_store.commit()
