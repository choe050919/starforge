extends Node
class_name TileChange

signal tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName)
signal tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName)
signal cells_changed() # 필요 시 AABB/리스트로 확장

# 외부 참조
@export_node_path("Node") var terrain_node_path: NodePath # Terrain 노드
var _terrain: Terrain

var _store: TileStore
var _queue: EventQueue
var size: Vector2i

# 타일 ID (월드와 일치해야 함)
const TILE_AIR: int = 0
const TILE_ICE: int = 1
const TILE_GROUND: int = 2
const TILE_URANIUM: int = 3

func _ready() -> void:
	if terrain_node_path != NodePath():
		_terrain = get_node(terrain_node_path) as Terrain

func setup(store: TileStore, grid_size: Vector2i, queue: EventQueue) -> void:
		_store = store
		_queue = queue
		size = grid_size

func get_tiles() -> PackedInt32Array:
		if _store:
				return _store.get_tiles()
		return PackedInt32Array()

func queue_replace(cell: Vector2i, to_tile: int, reason: StringName = &"") -> void:
	if size == Vector2i.ZERO or _queue == null:
			push_warning("[TileChange] setup() not ready."); return
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			return
	_queue.push_replace(cell, to_tile, reason)

func queue_destroy(cell: Vector2i, reason: StringName = &"destroy") -> void:
		queue_replace(cell, TILE_AIR, reason)

func apply_events(events: Array) -> void:
	if _store == null:
		return
	var changed: bool = false
	for op in events:
		if op.get("type") != "replace_tile":
			continue
		var cell: Vector2i = op.get("cell", Vector2i.ZERO)
		var to_tile: int = int(op.get("to", TILE_AIR))
		var reason: StringName = op.get("reason", &"")
		var from_tile: int = _store.get_tile(cell)
		if from_tile == to_tile:
			continue
		_store.set_tile(cell, to_tile)
		changed = true
		if _terrain != null:
			_terrain.apply_cell_change(cell, to_tile)
		if to_tile == TILE_AIR:
			emit_signal("tile_destroyed", cell, from_tile, reason)
		emit_signal("tile_replaced", cell, from_tile, to_tile, reason)
	if changed:
		emit_signal("cells_changed")
