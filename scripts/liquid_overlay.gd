extends Node2D
class_name LiquidOverlay

@onready var sprite: Sprite2D = get_node("Map")

@export var color: Color = Color(0.2, 0.4, 1.0, 0.8)

var grid_size: Vector2i
var tile_px: Vector2i = Vector2i(32, 32)

func _ready() -> void:
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 900
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_layout(size: Vector2i, tile_size: Vector2i) -> void:
	grid_size = size
	tile_px = tile_size
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(tile_px)
	sprite.modulate.a = color.a

func render(amounts: PackedFloat32Array) -> void:
	if amounts.size() != grid_size.x * grid_size.y:
		push_error("[LiquidOverlay] Size mismatch.")
		return
	var img: Image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	for y in grid_size.y:
		for x in grid_size.x:
			var idx: int = y * grid_size.x + x
			var a: float = clamp(amounts[idx], 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0,0,0,0))
			else:
				var c: Color = color
				c.a = a * color.a
				img.set_pixel(x, y, c)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex
