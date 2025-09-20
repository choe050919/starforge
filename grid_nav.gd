extends Node
class_name GridNav

signal navigation_cell_changed(cell: Vector2i)
signal navigation_bulk_changed(rect: Rect2i)

var grid := AStarGrid2D.new()
var cell_size := Vector2(32, 32)

func setup(grid_index: GridIndex):
	grid.size = Vector2i(grid_index.size.x, grid_index.size.y)
	grid.cell_size = cell_size
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()

func set_walkable(cell: Vector2i, walkable: bool) -> void:
	grid.set_point_solid(cell, not walkable)
	navigation_cell_changed.emit(cell)

func find_path(start_cell: Vector2i, goal_cell: Vector2i) -> PackedVector2Array:
	if grid.is_point_solid(goal_cell): return []
	var pts := grid.get_point_path(start_cell, goal_cell)
	var world_pts := PackedVector2Array()
	for p in pts:
		world_pts.push_back(Vector2(p) * cell_size + cell_size * 0.5)
	return world_pts

func mark_region_rebuilt(rect: Rect2i) -> void:
	navigation_bulk_changed.emit(rect)

func is_walkable(cell: Vector2i) -> bool:
	return not grid.is_point_solid(cell)

func iter_bounds() -> Rect2i:
	# 전체 그리드 영역을 Rect2i로 반환 (size는 AStarGrid2D.size)
	return Rect2i(Vector2i.ZERO, Vector2i(grid.size))
