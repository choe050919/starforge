extends RefCounted
class_name PhaseChangeApplier

var _index: GridIndex
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _visual: VisualSync

const PH_SOLID  := 1
const PH_LIQUID := 2
const SID_ICE   := 1
const SID_WATER := 4

func setup(index: GridIndex, phase_store: PhaseStore, substance_store: SubstanceStore, visual_sync: VisualSync) -> void:
	_index = index
	_phase_store = phase_store
	_substance_store = substance_store
	_visual = visual_sync

## diff: { "ice_to_water": PackedVector2Array, "water_to_ice": PackedVector2Array }
func apply(diff: Dictionary, _sim_time: float = 0.0) -> void:
	if diff.is_empty(): return

	var melt: PackedVector2Array = diff.get("ice_to_water", PackedVector2Array())
	var freeze: PackedVector2Array = diff.get("water_to_ice", PackedVector2Array())

	_phase_store.begin_write()
	_substance_store.begin_write()

	for cell in melt:
		var i := _index.idx(cell)
		_phase_store.set_by_index(i, PH_LIQUID)
		#_substance_store.set_by_index(i, SID_WATER)

	for cell in freeze:
		var i := _index.idx(cell)
		_phase_store.set_by_index(i, PH_SOLID)
		#_substance_store.set_by_index(i, SID_ICE)

	_phase_store.commit()
	_substance_store.commit()

	# 시각화: 도착지 기준 라우팅
	if _visual:
		if melt.size() > 0:
			_visual.to_terrain_destroy_ice(melt, &"phase_change:ice_to_water")
			_visual.to_liquid_add(melt) # 현재는 no-op
		if freeze.size() > 0:
			_visual.to_terrain_place_ice(freeze, &"phase_change:water_to_ice")
			_visual.to_liquid_remove(freeze) # 현재는 no-op
