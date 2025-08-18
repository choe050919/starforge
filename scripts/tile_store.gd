extends Resource
class_name TileStore

var size: Vector2i = Vector2i.ZERO
var tiles: PackedInt32Array = PackedInt32Array()

func setup(initial_tiles: PackedInt32Array, grid_size: Vector2i) -> void:
	size = grid_size
	tiles = PackedInt32Array(initial_tiles)

func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x

func get_tile(cell: Vector2i) -> int:
	var idx: int = _index(cell)
	if idx < 0 or idx >= tiles.size():
		return 0
	return tiles[idx]

func set_tile(cell: Vector2i, tile_id: int) -> void:
	var idx: int = _index(cell)
	if idx < 0 or idx >= tiles.size():
		return
	tiles[idx] = tile_id

func get_tiles() -> PackedInt32Array:
	return tiles
