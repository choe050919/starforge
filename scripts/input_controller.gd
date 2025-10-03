extends Node
class_name InputController

signal pan_requested(delta: Vector2)
signal zoom_requested(direction: float)
signal overlay_toggle_requested(mode: OverlayManager.OverlayMode)

## ToolManager에 직접 라우팅 (입력 해석만 하고, 의미 실행은 ToolManager가 담당)
@export var _tool_manager: ToolManager

var data_layer: DataLayer
var hover_service: HoverManager
var cell_size: Vector2 = Vector2.ONE

func setup(dl: DataLayer, hover: HoverManager) -> void:
	data_layer = dl
	hover_service = hover
	if dl == null:
		push_warning("[InputController] DataLayer injected as null")
	if hover == null:
		push_warning("[InputController] HoverManager injected as null")

func set_cell_size(size: Vector2) -> void:
		cell_size = size

# 우선순위: 오버레이 토글 > 줌 > 패닝 > 클릭/툴 전환
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_echo():
		return

	# 마우스 이동: 호버/패닝
	if event is InputEventMouseMotion:
		_update_hover()
		if Input.is_action_pressed("pan"):
			pan_requested.emit((event as InputEventMouseMotion).relative)

	# 줌
	if event.is_action_pressed("zoom_in"):
		zoom_requested.emit(-1.0)
	elif event.is_action_pressed("zoom_out"):
		zoom_requested.emit(1.0)

	# 오버레이 토글
	if event.is_action_pressed("overlay_toggle_heatmap"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.HEATMAP)
	elif event.is_action_pressed("overlay_toggle_heatsrc"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.HEAT_SOURCE)
	elif event.is_action_pressed("overlay_toggle_light"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.LIGHT)
	elif event.is_action_pressed("overlay_toggle_nav"):
		overlay_toggle_requested.emit(OverlayManager.OverlayMode.NAVIGATION)

	# 툴 전환(핫키)
	if event.is_action_pressed("tool_select_1"):
		_select_tool_by_index(1)
	elif event.is_action_pressed("tool_select_2"):
		_select_tool_by_index(2)
	elif event.is_action_pressed("tool_select_3"):
		_select_tool_by_index(3)
	elif event.is_action_pressed("tool_select_4"):
		_select_tool_by_index(4)

	# 좌클릭: ToolManager에 라우팅
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed and not event.is_echo():
		_route_click_to_tool_manager()

func _update_hover() -> void:
	if hover_service == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var world_pos := cam.get_global_mouse_position()
	var cell := Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
	hover_service.update_hover(cell)

func _route_click_to_tool_manager() -> void:
	if _tool_manager == null: return
	var cam := get_viewport().get_camera_2d()
	if cam == null: return
	var world_pos := cam.get_global_mouse_position()
	var cell := Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
	_tool_manager.handle_click(cell, world_pos, 0)

func _select_tool_by_index(idx: int) -> void:
	if _tool_manager == null:
		return
	_tool_manager.select_tool_by_index(idx)
