class_name GridIndex

var size: Vector2i = Vector2i.ZERO

func setup(new_size: Vector2i) -> void:
	size = new_size

func idx(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x

func cell(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

func in_bounds_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y

func in_bounds_idx(i: int) -> bool:
	return i >= 0 and i < size.x * size.y
