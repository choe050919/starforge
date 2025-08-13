extends Node2D

@onready var layer: TileMapLayer = get_node("Ground")

const SIZE: Vector2i = Vector2i(256, 128)
const SID_GROUND: int = 3
const ATLAS_GROUND: Vector2i = Vector2i(1, 0)
const ALT_GROUND: int = 0   # ★ 이 프로젝트에선 0이어야 함

func _ready() -> void:
	_generate_ground()
	var ts := layer.tile_set
	var map_px := Vector2(SIZE.x * ts.tile_size.x, SIZE.y * ts.tile_size.y)
	if has_node("Camera2D"):
		$Camera2D.position = map_px * 0.5

func _generate_ground() -> void:
	layer.clear()
	var noise := FastNoiseLite.new()
	noise.seed = 12345
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02

	# 간단 높이맵
	var hmap := PackedInt32Array()
	hmap.resize(SIZE.x)
	for x in SIZE.x:
		var h := int(noise.get_noise_1d(float(x)) * 12.0) + int(SIZE.y * 0.55)
		hmap[x] = clamp(h, 16, SIZE.y - 8)

	# 공기(빈칸)는 배치하지 않고 '땅'만 찍기
	for y in SIZE.y:
		for x in SIZE.x:
			if y >= hmap[x]:
				layer.set_cell(Vector2i(x, y), SID_GROUND, ATLAS_GROUND, ALT_GROUND)
