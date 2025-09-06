extends Node2D
class_name MoistureOverlay

@onready var sprite: Sprite2D = get_node("Map")

# 건조/습함 컬러(필요하면 조정)
@export var dry_color: Color = Color(0.45, 0.28, 0.1, 0.0)  # 갈색, 알파는 값에 따라 설정
@export var wet_color: Color = Color(0.15, 0.35, 0.9, 0.0)  # 파랑, 알파는 값에 따라 설정
@export var max_alpha: float = 0.9

var grid_size: Vector2i
var tile_px: Vector2i = Vector2i(32, 32)

var _img: Image
var _tex: ImageTexture

# 의존
var _moisture: MoistureStore
var _hydro: HydrologyField

func _ready() -> void:
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 901
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_layout(size: Vector2i, tile_size: Vector2i) -> void:
	grid_size = size
	tile_px = tile_size
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(tile_px)

	_img = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	sprite.texture = _tex

func bind_data(moisture_store: MoistureStore, hydro_field: HydrologyField) -> void:
	# 기존 연결 해제 방지
	if _moisture != null:
		if _moisture.is_connected("moisture_changed_batch", Callable(self, "_on_moisture_changed_batch")):
			_moisture.disconnect("moisture_changed_batch", Callable(self, "_on_moisture_changed_batch"))

	_moisture = moisture_store
	_hydro = hydro_field

	if _moisture != null:
		_moisture.connect("moisture_changed_batch", Callable(self, "_on_moisture_changed_batch"))

	# 최초 풀렌더
	_full_render()

func _full_render() -> void:

	if _moisture == null or _hydro == null:
		return
	var m: PackedInt32Array = _moisture.get_raw_read()
	var cap: PackedInt32Array = _hydro.capacity
	print("[MoistureOverlay] grid_n=", grid_size.x * grid_size.y,
		  " m=", m.size(), " cap=", cap.size())
	var n: int = grid_size.x * grid_size.y
	if m.size() != n or cap.size() != n:
		push_error("[MoistureOverlay] Size mismatch.")
		return

	_img.lock()
	for y in grid_size.y:
		for x in grid_size.x:
			var i: int = y * grid_size.x + x
			_img.set_pixel(x, y, _color_for(i, m, cap))
	_img.unlock()
	_tex.update(_img)

func _on_moisture_changed_batch(indices: PackedInt32Array) -> void:
	if _moisture == null or _hydro == null:
		return
	var m: PackedInt32Array = _moisture.get_raw_read()
	var cap: PackedInt32Array = _hydro.capacity
	var n: int = grid_size.x * grid_size.y
	if m.size() != n or cap.size() != n:
		return

	_img.lock()
	for k in indices.size():
		var i: int = indices[k]
		if i < 0 or i >= n: continue
		var x: int = i % grid_size.x
		var y: int = i / grid_size.x
		_img.set_pixel(x, y, _color_for(i, m, cap))
	_img.unlock()
	_tex.update(_img)

func _color_for(i: int, m: PackedInt32Array, cap: PackedInt32Array) -> Color:
	var cmax: int = cap[i]
	if cmax <= 0:
		return Color(0,0,0,0) # 비토양/용량0은 비표시
	var ratio: float = clamp(float(m[i]) / float(cmax), 0.0, 1.0)
	# 간단 보간 + 알파 스케일
	var rgb: Color = dry_color.lerp(wet_color, ratio)
	rgb.a = ratio * max_alpha
	return rgb
