# CornerHighlight.gd
# TODO
extends Sprite2D

var _ground: TileMapLayer # TODO # 변수 이름도 뭘로 할지... 걍 _terrain으로 할까?
var _tile_px := Vector2.ZERO # TODO

func _ready() -> void:
	
	_autoscale_to_tile()

func _autoscale_to_tile() -> void:
	if texture == null: return
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		scale = _tile_px / tex_size
