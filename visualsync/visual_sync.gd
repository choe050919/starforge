extends Node
class_name VisualSync

var _data_layer: DataLayer
var substance: SubstanceStore
var phase: PhaseStore
var mass: MassStore
var temp: TemperatureStore

@onready var ground: Ground = %Ground
@onready var heatmap_overlay: HeatmapOverlay = %HeatmapOverlay

func setup(data_layer: DataLayer) -> void:
	_data_layer = data_layer
	substance = _data_layer.substance
	phase = _data_layer.phase
	mass = _data_layer.mass
	temp = _data_layer.temperature

## 본체
## DataLayer의 set_cells_with_spec함수에서 인자 전달됨
## payload 키:
## "sid_changed" | "phase_changed" | "mass_changed" | "temp_changed"
func _on_tiles_changed(
	idxs: PackedInt32Array,
	reason: StringName,
	payload: Dictionary
) -> void:
	# 1) 전체 무효화 신호면 풀 리프레시
	if payload.get("full_refresh", false):
		_refresh_all(payload) # ← 내부에서 각 레이어/텍스처 전체 재생성
		return

	# 2) 부분 업데이트 경로
	if idxs.is_empty():
		print("something") # DEBUG HACK
		push_error("[VisualSync] not full_refresh and idxs is empty"); return
	_refresh_indices(idxs, payload)

## 전체 갱신. 어떤 정보를 동기화하느냐에 대한 입력만 받으며, 구체적 갱신은 직접 한다.
func _refresh_all(payload: Dictionary) -> void:
	var ch_sid   : bool = payload.get("sid_changed", false)
	var ch_phase : bool = payload.get("phase_changed", false)
	var ch_mass  : bool = payload.get("mass_changed", false)
	var ch_temp  : bool = payload.get("temp_changed", false)

	if ch_temp:
		heatmap_overlay.render_full_with_mask(temp.get_raw_read(), phase.get_raw_read())
	# 예시:
	#if ch_sid:
		#terrain.rebuild_all()      # 타일 아틀라스/메시 등 전체 재구성
	#if ch_mass:
		#liquid_overlay.rebuild_all()
	# ... 필요 노드만 호출

func _refresh_indices(idxs: PackedInt32Array, payload: Dictionary) -> void:
	var ch_sid   : bool = payload.get("sid_changed", false)
	var ch_phase : bool = payload.get("phase_changed", false)
	var ch_mass  : bool = payload.get("mass_changed", false)
	var ch_temp  : bool = payload.get("temp_changed", false)

	for i in idxs:
		var cell := _data_layer.index.cell(i)

		# ── Substance/Phase 변경 → Terrain 쪽 갱신
		if ch_sid or ch_phase:
			var sid   := substance.get_by_index(i)
			var phase := phase.get_by_index(i)
			ground.apply_cell_change(cell, sid)

		# ── Mass 변경 → 액체 오버레이
		#if ch_mass:
			#var m := mass.get_by_index(i)
			#_lo.update_cell(cell, m)

		# ── Temperature 변경 → 히트맵 오버레이
		#if ch_temp:
			#var t := temp.get_by_index(i)
			#_lo.update_heat(cell, t)
