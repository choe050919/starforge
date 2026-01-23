extends Node2D
class_name CornerHighlight



var _ground: TileMapLayer
var _tile_px := Vector2.ZERO
var _visible := false

func setup(ground_layer: TileMapLayer) -> void:
	_ground = ground_layer
	if ground_layer == null:
		Debug.error(self, "대상 레이어 지정에 실패했습니다.")
		return
	_tile_px = Vector2(ground_layer.tile_set.tile_size)

func show_cell(cell: Vector2i) -> void:
	if cell.x < 0:
		_visible = false
		queue_redraw()
		return
	
	position = _ground.map_to_local(cell) - _tile_px * 0.5
	_visible = true
	queue_redraw()

func _draw() -> void:
	if not _visible:
		return
	
	var length := _tile_px.x * 0.25  # 브라켓 길이 (타일의 1/4)
	var w := _tile_px.x
	var h := _tile_px.y
	
	# 좌상단 ┌
	_draw_bracket(Vector2.ZERO, Vector2(length, 0), Vector2(0, length))
	# 우상단 ┐
	_draw_bracket(Vector2(w, 0), Vector2(-length, 0), Vector2(0, length))
	# 좌하단 └
	_draw_bracket(Vector2(0, h), Vector2(length, 0), Vector2(0, -length))
	# 우하단 ┘
	_draw_bracket(Vector2(w, h), Vector2(-length, 0), Vector2(0, -length))

func _draw_bracket(corner: Vector2, dir1: Vector2, dir2: Vector2) -> void:
	# 검정 (두꺼운 배경)
	draw_line(corner, corner + dir1, Color.BLACK, 4.0, true)
	draw_line(corner, corner + dir2, Color.BLACK, 4.0, true)
	# 흰색 (얇은 전경)
	draw_line(corner, corner + dir1, Color.WHITE, 2.0, true)
	draw_line(corner, corner + dir2, Color.WHITE, 2.0, true)
