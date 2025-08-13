extends Camera2D

@export var zoom_step := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 3.0

var panning := false
var last_mouse := Vector2.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			panning = e.pressed
			last_mouse = get_global_mouse_position()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom = Vector2.ONE * clamp(zoom.x - zoom_step, min_zoom, max_zoom)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom = Vector2.ONE * clamp(zoom.x + zoom_step, min_zoom, max_zoom)

func _process(_dt: float) -> void:
	if panning:
		var now := get_global_mouse_position()
		var delta := (last_mouse - now)
		position += delta
		last_mouse = now
