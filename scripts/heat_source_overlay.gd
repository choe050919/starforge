extends Node2D
class_name HeatSourceOverlay

@onready var sprite: Sprite2D = get_node("Map")

@export var opacity: float = 0.9          # 오버레이 기본 투명도
@export var max_abs_deltaT: float = 5.0   # ΔT 절대값 최대치 (이 이상은 동일 진하기)

var grid_size: Vector2i
var tile_px: Vector2i = Vector2i(32, 32)  # 타일 픽셀 크기

func _ready() -> void:
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1000

	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_layout(size: Vector2i, tile_size: Vector2i) -> void:
	grid_size = size
	tile_px = tile_size
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(tile_px)
	sprite.modulate.a = opacity

func render_heat_sources(delta_t_list: PackedFloat32Array) -> void:
	if grid_size.x * grid_size.y != delta_t_list.size():
		push_error("[HeatSourceOverlay] Size mismatch."); 
		return
	
	var img: Image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)

	for y in grid_size.y:
		for x in grid_size.x:
			var idx: int = y * grid_size.x + x
			var dt: float = delta_t_list[idx]

			if absf(dt) < 0.001:
				img.set_pixel(x, y, Color(0,0,0,0)) # 변화 거의 없음 → 투명
				continue
			
			var intensity: float = clamp(absf(dt) / max_abs_deltaT, 0.0, 1.0)
			var col: Color
			if dt > 0:
				# 가열 → 빨강 계열
				col = Color(1.0, 0.2, 0.0, opacity * intensity)
			else:
				# 냉각 → 파랑 계열
				col = Color(0.0, 0.4, 1.0, opacity * intensity)

			img.set_pixel(x, y, col)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex
