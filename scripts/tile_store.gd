extends Resource
class_name TileStore

var size: Vector2i = Vector2i.ZERO
var tiles: PackedInt32Array = PackedInt32Array()

# 초기 설정
func setup(initial_tiles: PackedInt32Array, grid_size: Vector2i) -> void:
	size = grid_size
	var expected := size.x * size.y
	if initial_tiles.size() != expected: # 타일 배열 검증용 방어 코드
		push_error("TileStore.setup: size mismatch. expected=%d, got=%d" % [expected, initial_tiles.size()])
		tiles = PackedInt32Array()
		tiles.resize(expected)
		return
	tiles = PackedInt32Array(initial_tiles)

# cell 좌표를 index로 변환
func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x

# index를 cell 좌표로 변환
func index_to_cell(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

# cell 좌표가 경계 내에 있는지 검사 후 반환
func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y

# 입력된 좌표의 타일 값을 반환
func get_tile(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	return tiles[_index(cell)]

# 입력된 좌표의 타일 값을 설정
func set_tile(cell: Vector2i, tile_id: int) -> void:
	if not is_in_bounds(cell):
		return
	tiles[_index(cell)] = tile_id

func get_tiles() -> PackedInt32Array:
	return tiles

# 이웃 네 타일의 값을 반환, 좌우상하 순서
func neighbors4(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dirs = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		var n = cell + d
		if is_in_bounds(n):
			out.append(n)
	return out
