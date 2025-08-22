class_name GridIndex

var size: Vector2i = Vector2i.ZERO

func setup(new_size: Vector2i) -> void:
	size = new_size

func idx(cell_V: Vector2i) -> int:
	return cell_V.y * size.x + cell_V.x

func cell(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

func in_bounds(cell_V: Vector2i) -> bool:
	return cell_V.x >= 0 and cell_V.y >= 0 and cell_V.x < size.x and cell_V.y < size.y
