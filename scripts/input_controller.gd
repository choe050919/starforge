extends Node
class_name InputController

signal pan_requested(delta: Vector2)
signal zoom_requested(direction: float)
signal overlay_toggle_requested(mode: OverlayManager.OverlayMode)

var data_layer: DataLayer
var hover_service: HoverService
var cell_size: Vector2 = Vector2.ONE

func set_dependencies(dl: DataLayer, hover: HoverService) -> void:
	data_layer = dl
	hover_service = hover
	if dl == null:
		push_warning("[InputController] DataLayer injected as null")
	else:
		print("[InputController] DataLayer injected: SUCCESS")
	if hover == null:
		push_warning("[InputController] HoverService injected as null")
	else:
		print("[InputController] HoverService injected: SUCCESS")

func set_cell_size(size: Vector2) -> void:
		cell_size = size

# 우선순위: 오버레이 토글 > 줌 > 패닝
# UI(Control)가 이벤트를 소비하면 _unhandled_input이 호출되지 않는다.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_echo():
		return
	if event is InputEventMouseMotion:
		_update_hover()
		if Input.is_action_pressed("pan"):
			pan_requested.emit((event as InputEventMouseMotion).relative)
	if event.is_action_pressed("zoom_in"):
		zoom_requested.emit(-1.0)
	elif event.is_action_pressed("zoom_out"):
		zoom_requested.emit(1.0)
	if event.is_action_pressed("overlay_toggle_heatmap"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.HEATMAP)
	elif event.is_action_pressed("overlay_toggle_heatsrc"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.HEAT_SOURCE)

func _update_hover() -> void:
	if hover_service == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var world_pos := cam.get_global_mouse_position()
	var cell := Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
	hover_service.update_hover(cell)
