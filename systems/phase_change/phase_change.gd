extends Node
class_name PhaseChange

@export var enabled := true
@export var debug_log := false

# 의존성
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _temperature_store: TemperatureStore
var _index: GridIndex
var _clock: SimClock
var _rules: SubstanceRuleCache

## 코어: 계산만 담당
var _core: PhaseChangeCore
## 적용기: 계산 결과를 수요자들에게 전달
var _applier: PhaseChangeApplier

func setup(
	phase_store: PhaseStore,
	substance_store: SubstanceStore,
	temperature_store: TemperatureStore,
	index: GridIndex,
	visual_sync: VisualSync,
	clock: SimClock,
	rule_cache: SubstanceRuleCache
) -> void:
	_phase_store = phase_store
	_substance_store = substance_store
	_temperature_store = temperature_store
	_index = index
	_clock = clock
	_rules = rule_cache

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_phase_store", "_substance_store", "_temperature_store", "_index", "_clock", "_rules"]:
		if get(name) == null:
			push_error("[PhaseChange.setup]%s is null" % name)

	_core = PhaseChangeCore.new()
	_core.bind_rule_cache(_rules)

	_applier = PhaseChangeApplier.new()
	_applier.setup(_index, _phase_store, _substance_store, visual_sync, _rules)

func _on_sim_tick(_dt: float, sim_time: float) -> void:
	if not enabled:
		return

	var diff: Dictionary = _core.tick_fullscan(_phase_store, _substance_store, _temperature_store, _index)

	var changes: Array = diff.get("changes", [])
	if changes.is_empty(): return

	_applier.apply(diff, sim_time)

	if debug_log:
		var stats: Dictionary = diff.get("stats", {})
		var total := 0
		for k in stats.keys():
			total += int(stats[k])
		print("[t=%.2f s][PhaseChange] Δ=%d pairs=%d" % [sim_time, total, stats.size()])
