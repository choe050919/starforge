extends Node2D
class_name HeatmapOverlay

@onready var sprite: Sprite2D = get_node("Map")

@export var opacity: float = 0.8 ## 오버레이 투명도

@export var t_min_cc: int = -2000 # 히트맵 표시 최소/최대(시각화용)
@export var t_max_cc: int = 4000

# °cC → cK(centiKelvin) 변환: cK = round(°C*100 + 27315)
const CK_0C := 27315
static func _cc_to_ck(c: int) -> int:
	return int(c + CK_0C)

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

func render_full_with_mask(T: PackedInt32Array, mask: PackedByteArray) -> void:
	if grid_size.x * grid_size.y != T.size() or mask.size() != T.size():
		Debug.error(self, "Size mismatch with mask."); return

	var img := Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	var denom: int = max(1, (_cc_to_ck(t_max_cc) - _cc_to_ck(t_min_cc)))
	var inv: float = 1.0 / denom

	for y in grid_size.y:
		for x in grid_size.x:
			var idx: int = y * grid_size.x + x
			if mask[idx] == 0:
				img.set_pixel(x, y, Color(0,0,0,0)) # 공기=완전 투명
				continue
			var v: int = T[idx]
			var t: float = clamp((v - _cc_to_ck(t_min_cc)) * inv, 0.0, 1.0)
			var col: Color = _color_map(t, opacity)
			img.set_pixel(x, y, col)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex

static func _color_map(t: float, alpha: float) -> Color:
	# 간단한 blue→red LERP
	var c_cold := Color(0.0, 0.4, 1.0, alpha)
	var c_hot  := Color(1.0, 0.2, 0.0, alpha)
	return c_cold.lerp(c_hot, t)
