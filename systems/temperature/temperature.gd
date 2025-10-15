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
var _temp_store: TemperatureStore
var _mass_store: MassStore
var _index: GridIndex
var _rules: SubstanceRuleCache

# 코어
var _core: TemperatureCore

func setup(
	data: DataLayer,
	rule_cache: SubstanceRuleCache
) -> void:
	_data = data
	_substance_store = _data.substance
	_phase_store = _data.phase
	_temp_store = _data.temperature
	_mass_store = _data.mass
	_index = _data.index
	_rules = rule_cache

	for _name in ["_substance_store", "_phase_store", "_temp_store", "_mass_store", "_index"]:
		var value = get(_name)
		if value == null:
			push_error("[Temperature.setup]%s is null" % _name)

	_core = TemperatureCore.new()
	_core.setup_thermal_from_cache(_rules)

# ── 틱 ─────────────────────────────────────────────────────────────
func _on_sim_tick(dt: float) -> void:
	if not enabled: return

	var stats := _core.tick_fullscan(
		_temp_store.get_raw_read(),
		_substance_store.get_raw_read(),
		_mass_store.get_raw_read(),
		_index,
		dt
	)

	_data.set_bulk_temp(stats)
