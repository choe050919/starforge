extends Node
class_name PhaseChange

@export var enabled := true
@export var debug_log := false

# 의존성
var _data: DataLayer
var _rules: SubstanceRuleCache

## 코어: 계산만 담당
var _core: PhaseChangeCore
## 적용기: 계산 결과를 수요자들에게 전달
var _applier: PhaseChangeApplier

func setup(data: DataLayer, rule_cache: SubstanceRuleCache) -> void:
	_data = data
	_rules = rule_cache

	for _name in ["_data", "_rules"]:
		if get(_name) == null:
			push_error("[PhaseChange.setup]%s is null" % _name)

	_core = PhaseChangeCore.new()
	_core.bind_rule_cache(_rules)

	_applier = PhaseChangeApplier.new()
	_applier.setup(_data, _rules)

func _on_sim_tick(_dt: float, sim_time: float) -> void:
	if not enabled:
		return

	var diff: Dictionary = _core.tick_fullscan(
		_data.phase.get_raw_read(),
		_data.substance.get_raw_read(),
		_data.temperature.get_raw_read(),
		_data.index
	)

	var changes: Array = diff.get("changes", [])
	if changes.is_empty(): return

	_applier.apply(diff, sim_time)

	if debug_log:
		var stats: Dictionary = diff.get("stats", {})
		var total := 0
		for k in stats.keys():
			total += int(stats[k])
		print("[t=%.2f s][PhaseChange] Δ=%d pairs=%d" % [sim_time, total, stats.size()])
