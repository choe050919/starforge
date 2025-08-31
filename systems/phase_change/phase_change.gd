extends Node
class_name PhaseChange

@export var enabled := true
@export var debug_log := false

# (구) 공용 파라미터는 호환 모드용으로만 남겨둠 (legacy)
@export var hyst_ck := 100        # ICE/WATER 공용 히스테리시스 폭
@export var melt_ck := 27315        # ICE 쪽 융해 기준(상향)
@export var freeze_ck := 27314     # WATER 쪽 응고 기준(하향)

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
	if changes.is_empty():
		return

	_applier.apply(diff, sim_time)

	if debug_log:
		var stats: Dictionary = diff.get("stats", {})
		var total := 0
		for k in stats.keys():
			total += int(stats[k])
		print("[t=%.2f s][PhaseChange] Δ=%d pairs=%d" % [sim_time, total, stats.size()])

"""
	# 1) Core: diff 생성 (셀 목록)
	var diff: Dictionary = _core.tick_fullscan(_phase_store, _substance_store, _temperature_store, _index)
	if diff.is_empty():
		return

	var melt: PackedVector2Array   = diff.get("ice_to_water", PackedVector2Array())
	var freeze: PackedVector2Array = diff.get("water_to_ice", PackedVector2Array())
	var total := melt.size() + freeze.size()

	# 2) Applier: 스토어에 반영 + VisualSync 라우팅 (commit 포함)
	if total > 0:
		_applier.apply(diff, sim_time)

		# 3) 디버그 로그
		if debug_log:
			print("[t=%.2f s][PhaseChange] Δ=%d (ICE→WATER=%d, WATER→ICE=%d)" % [
				sim_time, total, melt.size(), freeze.size()
			])
"""

## 호환 모드: 전이가 전혀 없을 때만 구식 파라미터로 룰 생성(선택)
func rebuild_rules() -> void:
	if _core == null:
		_core = PhaseChangeCore.new()
	_core.setup_rules(hyst_ck, melt_ck, freeze_ck)
	_core.bind_rule_cache(_rules)
