class_name GridIndex

var size: Vector2i = Vector2i.ZERO

func setup(new_size: Vector2i) -> void:
	size = new_size

func idx(c: Vector2i) -> int:
	return c.y * size.x + c.x

func cell(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

func in_bounds_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func in_bounds_idx(i: int) -> bool:
	return i >= 0 and i < size.x * size.y
