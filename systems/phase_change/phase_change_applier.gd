extends RefCounted
class_name PhaseChangeApplier

var _index: GridIndex
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _visual: VisualSync
var _rules: SubstanceRuleCache

func setup(
	index: GridIndex,
	phase_store: PhaseStore,
	substance_store: SubstanceStore,
	visual_sync: VisualSync,
	rule_cache: SubstanceRuleCache
) -> void:
	_index = index
	_phase_store = phase_store
	_substance_store = substance_store
	_visual = visual_sync
	_rules = rule_cache

## diff: { "changes": Array[{cell, from_sid, to_sid}], "stats": Dictionary }
func apply(diff: Dictionary, _sim_time: float = 0.0) -> void:
	if diff.is_empty(): return
	var changes: Array = diff.get("changes", [])
	if changes.is_empty(): return

	_phase_store.begin_write()
	_substance_store.begin_write()

	# 도착지별 묶음(비주얼 라우팅 편의)
	var by_pair: Dictionary = {} # key: (from_sid<<32)|to_sid -> PackedVector2Array

	for ch in changes:
		var cell: Vector2i = ch["cell"]
		var from_sid: int = ch["from_sid"]
		var to_sid: int = ch["to_sid"]

		var i := _index.idx(cell)

		# 1) Substance 교체 (반드시)
		_substance_store.set_by_index(i, to_sid)

		# 2) Phase 동기화 (to_sid의 소속 phase로)
		var to_ph: int = int(_rules.phase_of_sid.get(to_sid, 0))
		_phase_store.set_by_index(i, to_ph)

		# 3) 비주얼용 묶음
		var key := (int(from_sid) << 32) | int(to_sid)
		if not by_pair.has(key):
			by_pair[key] = PackedVector2Array()
		by_pair[key].push_back(cell)

	# 커밋
	_phase_store.commit()
	_substance_store.commit()

	## 4) 비주얼 라우팅(최소 구현) # TODO
	#if _visual:
		#for key in by_pair.keys():
			#var cells: PackedVector2Array = by_pair[key]
			#var from_sid := int(key >> 32)
			#var to_sid   := int(key & 0xFFFFFFFF)
			#_visual.route_phase_change(from_sid, to_sid, cells)
