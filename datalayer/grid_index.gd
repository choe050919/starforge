class_name GridIndex

var size: Vector2i = Vector2i.ZERO

func setup(new_size: Vector2i) -> void:
	size = new_size

## Convert 2D cell coordinate to 1D array index
func idx(c: Vector2i) -> int:
	return c.y * size.x + c.x

## Convert 1D array index to 2D cell coordinate
func cell(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % size.x, i / size.x)

func _index_array_to_cells(index_array: Array[int]) -> Array[Vector2i]:
	var cell_array := []
	cell_array.resize(index_array.size())
	for i in index_array.size():
		cell_array.append(cell(index_array[i]))
	return cell_array

func in_bounds_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func in_bounds_index(i: int) -> bool:
	return i >= 0 and i < size.x * size.y

## Generic bounds checker that accepts both cell and index
func in_bounds(value) -> bool:
	if value is int:
		return in_bounds_index(value)
	elif value is Vector2i:
		return in_bounds_cell(value)
	else:
		push_warning("[GridIndex] Invalid type for in_bounds(): expected int or Vector2i, got %s" % type_string(typeof(value)))
		return false
