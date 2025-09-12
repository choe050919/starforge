extends RefCounted
class_name PhaseChangeApplier

var _data: DataLayer
var _index: GridIndex
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _rules: SubstanceRuleCache

func setup(data: DataLayer, rule_cache: SubstanceRuleCache) -> void:
	_data = data
	_index = _data.index
	_phase_store = _data.phase
	_substance_store = _data.substance
	_rules = rule_cache

## diff: { "changes": Array[{cell, from_sid, to_sid}], "stats": Dictionary }
func apply(diff: Dictionary, _sim_time: float = 0.0) -> void:
	if diff.is_empty(): return
	var changes: Array = diff.get("changes", [])
	if changes.is_empty(): return

	for ch in changes:
		var cell: Vector2i = ch["cell"]

		# 1) to_value 계산, spec 포장
		var to_sid: int = ch["to_sid"]
		var to_ph := int(_rules.phase_of_sid.get(to_sid, 0))
		var spec := {"sid": to_sid, "phase": to_ph}

		# 2) sid, phase 설정
		_data.set_cell_with_spec(cell, spec)
