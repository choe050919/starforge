extends Node
class_name HoverService

signal hover_changed(cell: Vector2i)

var data_layer: DataLayer
var _current: Vector2i = Vector2i(-1, -1)

func setup(dl: DataLayer) -> void:
	data_layer = dl
	if dl == null:
		push_warning("[HoverService] DataLayer injected as null")
	else:
		print("[HoverService] DataLayer injected: SUCCESS")

func update_hover(cell: Vector2i) -> void:
	if not data_layer.index.in_bounds_cell(cell): # 범위 밖의 셀 무효값으로 처리
		cell = Vector2i(-1, -1)
	if cell == _current: # 같은 셀 반복 호출이면 스킵
		return
	_current = cell

	# print("[HoverService] current cell: (%d, %d)" % [_current.x, _current.y])
	# world.gd를 거친 후 corner_highlight.gd의 show_cell로 연결된다.
	hover_changed.emit(cell)
