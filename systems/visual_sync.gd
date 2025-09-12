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
	changed_by_index: PackedInt32Array,
	reason: StringName,
	payload: Dictionary
) -> void:
	if changed_by_index.is_empty(): push_error("[VisualSync] nothing changed"); return

	if payload["sid_changed"] == true:
		pass

	if payload["temp_changed"] == true:
		print("dd")
		heatmap_overlay.render_full_with_mask(temp.get_raw_read(), phase.get_raw_read())




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

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_terrain", "_lo"]:
		var value = get(name)
		if value == null:
			push_error("[VisualSync.setup]%s is null" % name)

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
