extends Sprite2D
class_name CornerHighlight

var _ground: TileMapLayer
var _tile_px := Vector2.ZERO
var _last_cell: Vector2i = Vector2i(-9999, -9999)

func setup(ground_layer: TileMapLayer) -> void:
	_ground = ground_layer
	if ground_layer == null:
		push_error("[CornerHighlight] 대상 레이어 지정에 실패했습니다.")
	_tile_px = ground_layer.tile_set.tile_size
	_autoscale_to_tile()

func _autoscale_to_tile() -> void:
	if texture == null: return
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		scale = _tile_px / tex_size

func show_cell(cell: Vector2i) -> void:
	# 가드: 무효 셀이면 숨김
	if cell.x < 0:
		hide()
		return
	# 같은 셀 반복 호출이면 스킵, 이중 검증용
	if cell == _last_cell and visible:
		return

	# 타일 좌표 → 로컬 좌표
	var p := _ground.map_to_local(cell)

	p -= _tile_px * 0.5

	position = p
	_last_cell = cell
	show()
