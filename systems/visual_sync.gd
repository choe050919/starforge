extends Node
class_name VisualSync
## 목적지(도착지) 기준 라우터. TileChange 경유 없음.

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
