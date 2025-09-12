extends Node
class_name VisualSync

var _data_layer: DataLayer
var substance: SubstanceStore
var phase: PhaseStore
var mass
var temp: TemperatureStore

@export var heatmap_overlay: HeatmapOverlay

func setup(data_layer: DataLayer) -> void:
	_data_layer = data_layer
	substance = _data_layer.substance
	phase = _data_layer.phase
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
		print("all")
		_refresh_all(payload) # ← 내부에서 각 레이어/텍스처 전체 재생성
		return

	# 2) 부분 업데이트 경로
	if idxs.is_empty():
		push_error("[VisualSync] not full_refresh and idxs is empty");
		return
		print("something")
	_refresh_indices(idxs, payload)

func _refresh_all(payload: Dictionary) -> void:
	var ch_sid  : bool = payload.get("sid_changed", false)
	var ch_phase: bool = payload.get("phase_changed", false)
	var ch_mass : bool = payload.get("mass_changed", false)
	var ch_temp : bool = payload.get("temp_changed", false)

	if ch_temp:
		heatmap_overlay.render_full_with_mask(temp.get_raw_read(), phase.get_raw_read())
	# 예시:
	#if ch_sid:
		#terrain.rebuild_all()      # 타일 아틀라스/메시 등 전체 재구성
	#if ch_mass:
		#liquid_overlay.rebuild_all()
	# ... 필요 노드만 호출

func _refresh_indices(idxs: PackedInt32Array, payload: Dictionary) -> void:
	pass

@export_node_path("Node") var terrain_path: NodePath
@export_node_path("Node") var liquid_overlay_path: NodePath

var _terrain: Terrain
var _lo: LiquidOverlay

func _ready() -> void:
	if terrain_path != NodePath():
		_terrain = get_node(terrain_path) as Terrain
	if liquid_overlay_path != NodePath():
		_lo = get_node(liquid_overlay_path) as LiquidOverlay

	# LiquidOverlay는 매 틱 render(amounts)로 동기화되므로 없어도 작동함.

	for _name in ["_terrain", "_lo"]:
		var value = get(_name)
		if value == null:
			push_error("[VisualSync.setup]%s is null" % _name)

# ── Terrain 목적지 ────────────────────────────────────────
func to_terrain_destroy_ice(cells: PackedVector2Array, _reason: StringName = &"") -> void:
	for c in cells:
		_terrain.apply_cell_change(c, Terrain.TILE_VACCUM)

func to_terrain_place_ice(cells: PackedVector2Array, _reason: StringName = &"") -> void:
	for c in cells:
		_terrain.apply_cell_change(c, Terrain.TILE_ICE)

# 필요시 범용 교체도 사용할 수 있게 한 줄
func to_terrain_replace(cells: PackedVector2Array, to_tile: int, _reason: StringName = &"") -> void:
	for c in cells:
		_terrain.apply_cell_change(c, to_tile)

# ── LiquidOverlay 목적지(현재 구조에선 알림 불필요: 매 틱 render) ──
func to_liquid_add(_cells: PackedVector2Array) -> void:
	# no-op (LiquidOverlay.render(amounts)에서 전역 동기화)
	pass

func to_liquid_remove(_cells: PackedVector2Array) -> void:
	# no-op
	pass
