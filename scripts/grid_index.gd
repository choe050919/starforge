class_name GridIndex

var size: Vector2i = Vector2i.ZERO

func setup(new_size: Vector2i) -> void:
	size = new_size

func idx(v: Vector2i) -> int:
	return v.y * size.x + v.x

func cell(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

func in_bounds(v: Vector2i) -> bool:
	return v.x >= 0 and v.y >= 0 and v.x < size.x and v.y < size.y

func in_bounds_i(i: int) -> bool:
	return i >= 0 and i < size.x * size.y
