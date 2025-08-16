extends TileMapLayer
class_name CrackOverlay

@export var tile_shallow: int = 0
@export var tile_medium: int = 1
@export var tile_deep: int = 2

var size: Vector2i = Vector2i.ZERO
var _stage: PackedByteArray = PackedByteArray()

const THRESHOLDS := [0.8, 0.5, 0.25]

func set_layout(grid_size: Vector2i) -> void:
		size = grid_size
		_stage = PackedByteArray()
		_stage.resize(size.x * size.y)
		clear()

func _index(cell: Vector2i) -> int:
		return cell.y * size.x + cell.x

func on_hp_changed(cell: Vector2i, hp: float, max_hp: float) -> void:
		if size == Vector2i.ZERO:
				return
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
				return
		var idx := _index(cell)
		var stage := 0
		if max_hp > 0.0:
				var ratio := hp / max_hp
				if ratio <= THRESHOLDS[2]:
						stage = 3
				elif ratio <= THRESHOLDS[1]:
						stage = 2
				elif ratio <= THRESHOLDS[0]:
						stage = 1
		if _stage[idx] == stage:
				return
		_stage[idx] = stage
		if stage == 0:
				erase_cell(cell)
		elif stage == 1:
				set_cell(cell, 0, Vector2i(tile_shallow, 0))
		elif stage == 2:
				set_cell(cell, 0, Vector2i(tile_medium, 0))
		else:
				set_cell(cell, 0, Vector2i(tile_deep, 0))

func on_break_requested(cell: Vector2i) -> void:
		if size == Vector2i.ZERO:
				return
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
				return
		var idx := _index(cell)
		if idx < 0 or idx >= _stage.size():
				return
		_stage[idx] = 0
		erase_cell(cell)
