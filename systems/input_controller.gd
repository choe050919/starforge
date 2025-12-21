extends Node
class_name InputController

signal pan_requested(delta: Vector2)
signal zoom_requested(direction: float)
signal overlay_toggle_requested(mode: OverlayManager.OverlayMode)
signal player_move_requested(world_pos: Vector2)
signal mining_requested(cell: Vector2i)
signal pickup_requested(cell: Vector2i)  # 추가
signal eat_food_requested()

## ToolManager에 직접 라우팅 (입력 해석만 하고, 의미 실행은 ToolManager가 담당)
@export var _tool_manager: ToolManager

var data_layer: DataLayer
var hover_service: HoverManager
var cell_size: Vector2 = Vector2.ONE

@export var keyboard_pan_speed: float = 400.0  # WASD 이동 속도 (px/sec)

func setup(dl: DataLayer, hover: HoverManager) -> void:
	data_layer = dl
	hover_service = hover
	if dl == null:
		push_warning("[InputController] DataLayer injected as null")
	if hover == null:
		push_warning("[InputController] HoverManager injected as null")

func set_cell_size(size: Vector2) -> void:
	cell_size = size

func _process(delta: float) -> void:
	# WASD 키보드 이동
	var pan_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		pan_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		pan_dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		pan_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		pan_dir.x += 1.0
	
	if pan_dir.length_squared() > 0.0:
		pan_dir = pan_dir.normalized()
		pan_requested.emit(pan_dir * keyboard_pan_speed * delta)

# 우선순위: 오버레이 토글 > 줌 > 마우스 패닝 > 클릭/툴 전환
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_echo():
		return

	# 마우스 이동: 호버 업데이트
	if event is InputEventMouseMotion:
		_update_hover()
		# 마우스 드래그 패닝 (MMB 또는 Shift+드래그 등)
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
	elif event.is_action_pressed("tool_select_5"):
		_select_tool_by_index(5)
	elif event.is_action_pressed("tool_select_6"):
		_select_tool_by_index(6)
	elif event.is_action_pressed("tool_select_7"):
		_select_tool_by_index(7)

	# 좌클릭: ToolManager에 라우팅
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed and not event.is_echo():
		_route_click_to_tool_manager()

	# 우클릭: 플레이어 이동
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mouse_world = get_viewport().get_canvas_transform().affine_inverse() * event.position
			player_move_requested.emit(mouse_world)
			get_viewport().set_input_as_handled()

	# G키: 채굴 시작/중단
	if event.is_action_pressed("mine"):
		var cam := get_viewport().get_camera_2d()
		if cam:
			var world_pos := cam.get_global_mouse_position()
			var cell := Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
			mining_requested.emit(cell)
			get_viewport().set_input_as_handled()
	
	# F키: 아이템 줍기 (추가)
	if event.is_action_pressed("pickup"):
		var cam := get_viewport().get_camera_2d()
		if cam:
			var world_pos := cam.get_global_mouse_position()
			var cell := Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
			pickup_requested.emit(cell)
			get_viewport().set_input_as_handled()
			print("[InputController] Pickup requested at cell=", cell)
	
	# E키: 음식 섭취
	if event.is_action_pressed("eat_food"):
		eat_food_requested.emit()
		get_viewport().set_input_as_handled()
		print("[InputController] Eat food requested")

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
	_tool_manager.handle_click(cell, world_pos)

func _select_tool_by_index(idx: int) -> void:
	if _tool_manager == null:
		return
	_tool_manager.select_tool_by_index(idx)
