extends Node
class_name TileChange

signal tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName)
signal tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName)
signal cells_changed()  # 필요 시 AABB/리스트로 확장

# 외부 참조
@export_node_path("Node") var terrain_node_path: NodePath     # Terrain 노드
var _terrain: Terrain

# 내부 상태
var size: Vector2i
var _tiles: PackedInt32Array = PackedInt32Array()  # 권한 보유: 현재 월드의 tile_types
var _ops: Array = []  # [{cell:Vector2i, to:int, reason:StringName}]

# 타일 ID (월드와 일치해야 함)
const TILE_AIR: int = 0
const TILE_ICE: int = 1
const TILE_GROUND: int = 2
const TILE_URANIUM: int = 3

func _ready() -> void:
	if terrain_node_path != NodePath():
		_terrain = get_node(terrain_node_path) as Terrain

func setup(initial_tiles: PackedInt32Array, grid_size: Vector2i) -> void:
	size = grid_size
	_tiles = PackedInt32Array(initial_tiles)  # 사본 보관
	_ops.clear()

func get_tiles() -> PackedInt32Array:
	return _tiles

func queue_replace(cell: Vector2i, to_tile: int, reason: StringName = &"") -> void:
	if size == Vector2i.ZERO:
		push_warning("[TileChange] setup() not called yet."); return
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return
	_ops.append({ "cell": cell, "to": to_tile, "reason": reason })

func queue_destroy(cell: Vector2i, reason: StringName = &"destroy") -> void:
	queue_replace(cell, TILE_AIR, reason)

func commit() -> void:
	if _ops.is_empty():
		return
	var changed: bool = false

	for op in _ops:
		var cell: Vector2i = op["cell"]
		var to_tile: int = int(op["to"])
		var reason: StringName = op["reason"]

		var idx: int = cell.y * size.x + cell.x
		if idx < 0 or idx >= _tiles.size():
			continue

		var from_tile: int = _tiles[idx]
		if from_tile == to_tile:
			continue

		# 내부 상태 갱신
		_tiles[idx] = to_tile
		changed = true

		# Terrain 반영(부분 업데이트)
		if _terrain != null:
			_terrain.apply_cell_change(cell, to_tile)

		# 이벤트 브로드캐스트
		if to_tile == TILE_AIR:
			emit_signal("tile_destroyed", cell, from_tile, reason)
		emit_signal("tile_replaced", cell, from_tile, to_tile, reason)

	_ops.clear()
	if changed:
		emit_signal("cells_changed")
