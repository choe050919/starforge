extends Camera2D

@export var pan_button: MouseButton = MOUSE_BUTTON_RIGHT
@export var pan_speed: float = 1.0            # 드래그 감도 (1.0 기본)
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var zoom_lerp_speed: float = 12.0     # 줌 보간 속도(크면 더 빠르게 붙음)

var _panning: bool = false
var _target_zoom: float = 1.0                 # 실제 zoom.x와 동기

func _ready() -> void:
	_target_zoom = zoom.x

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton

		if mb.button_index == pan_button:
			_panning = mb.pressed

		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_towards_cursor(-zoom_step)

		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_towards_cursor(+zoom_step)

	elif e is InputEventMouseMotion and _panning:
		var mm := e as InputEventMouseMotion
		# 화면 기준 상대 이동을 월드 이동으로 환산 (줌 반영)
		position -= mm.relative * (_target_zoom * pan_speed)

func _process(dt: float) -> void:
	# 줌 부드럽게 보간
	var z: float = lerp(zoom.x, _target_zoom, clamp(zoom_lerp_speed * dt, 0.0, 1.0))
	zoom = Vector2.ONE * z

func _zoom_towards_cursor(delta_step: float) -> void:
	var before_mouse_world := get_global_mouse_position()

	_target_zoom = clamp(_target_zoom + delta_step, min_zoom, max_zoom)
	# 즉시 살짝 반영해서 포인트 보정 정확도 ↑
	zoom = Vector2.ONE * _target_zoom

	var after_mouse_world := get_global_mouse_position()
	# 커서 아래 포인트 고정: 줌으로 바뀐 만큼 카메라 위치를 되돌림
	position += (before_mouse_world - after_mouse_world)
