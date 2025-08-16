extends Node2D
class_name HeatmapOverlay

@onready var sprite: Sprite2D = get_node("Map")

@export var opacity: float = 0.9 # 오버레이 투명도

var grid_size: Vector2i
var tile_px: Vector2i = Vector2i(32, 32) # 타일 픽셀(런타임에 World가 세팅해줌)

func _ready() -> void:
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1000

	# Ground와 동일한 원점 사용: 부모(Terrain) 기준 (Terrain 아래에 두면 (0,0) 공유)
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE # 노드 자체 스케일은 1로, 스프라이트로만 스케일링

func set_layout(size: Vector2i, tile_size: Vector2i) -> void:
	grid_size = size
	tile_px = tile_size
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(tile_px) # 1 텍셀 = 1 타일
	sprite.modulate.a = opacity

func render_full_with_mask(T: PackedFloat32Array, mask: PackedByteArray, t_min: float, t_max: float) -> void:
	if grid_size.x * grid_size.y != T.size() or mask.size() != T.size():
		push_error("[HeatmapOverlay] Size mismatch with mask."); 
		return
	
	var img: Image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	var denom: float = max(0.0001, (t_max - t_min))
	var inv: float = 1.0 / denom

	for y in grid_size.y:
		for x in grid_size.x:
			var idx: int = y * grid_size.x + x
			if mask[idx] == 0:
				img.set_pixel(x, y, Color(0,0,0,0)) # 공기=완전 투명
				continue
			var v: float = T[idx]
			var t: float = clamp((v - t_min) * inv, 0.0, 1.0)
			var col: Color = _color_map(t)
			img.set_pixel(x, y, col)

	# flip_y() 제거!
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex

func _color_map(t: float) -> Color:
	# 간단한 blue→red LERP (원하면 더 이쁜 그라데이션으로 교체)
	var c_cold := Color(0.0, 0.4, 1.0, opacity)
	var c_hot  := Color(1.0, 0.2, 0.0, opacity)
	return c_cold.lerp(c_hot, t)
