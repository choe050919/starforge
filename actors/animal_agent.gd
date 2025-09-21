extends Node2D
class_name AnimalAgent
## 표면 그래프(GridNav)를 이용해 경로를 구하고, 월드 포인트를 따라 이동하는 간단한 에이전트.
## - 이동은 "셀 센터" 경유점(world coords) 직선 보간
## - 목표 지점 지정, 노드 추적(타겟 따라가기), 정지 지원
## - 지형 변동 시(GridNav 시그널) 자동 재탐색
## - NavigationOverlay가 있으면 경로 프리뷰 표시(옵션)

@export var grid_nav_path: NodePath
@export var overlay_path: NodePath

@export var move_speed: float = 120.0            # px/sec
@export var arrive_epsilon_px: float = 4.0       # 경유점 도착 판정
@export var repath_interval_sec: float = 0.35    # 추적 모드에서 재탐색 주기
@export var show_own_path_preview: bool = true   # 내 경로를 오버레이에 띄우기

enum Mode { IDLE, MOVE_TO, FOLLOW }
var _mode: int = Mode.IDLE

var _grid_nav: GridNav
var _overlay: Node = null
var _cell_px: Vector2 = Vector2(32, 32)          # GridNav에서 가져옴(없으면 기본값)

var _path: PackedVector2Array = []               # 월드 좌표 경유점
var _path_index: int = 0
var _goal_cell: Vector2i = Vector2i(-9999, -9999)

var _follow_target: Node2D = null
var _time_since_repath := 0.0

func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
		if "cell_size" in _grid_nav:
			_cell_px = _grid_nav.cell_size
		# 지형 변경 신호에 반응해서 필요 시 재탐색
		if _grid_nav.has_signal("navigation_cell_changed"):
			_grid_nav.navigation_cell_changed.connect(_on_nav_changed)
		if _grid_nav.has_signal("navigation_bulk_changed"):
			_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)

	if overlay_path != NodePath() and has_node(overlay_path):
		_overlay = get_node(overlay_path)

	call_deferred("_snap_start_to_surface")

func _snap_start_to_surface() -> void:
	if _grid_nav == null:
		return
	var b := _grid_nav.iter_bounds()
	var cell := _world_to_cell(global_position)
	cell.x = clamp(cell.x, b.position.x, b.position.x + b.size.x - 1)

	var found := false
	# ↓ 아래로 먼저 탐색
	for y in range(cell.y, b.position.y + b.size.y):
		var c2 := Vector2i(cell.x, y)
		if _grid_nav.is_walkable(c2):
			global_position = Vector2(c2) * _cell_px + _cell_px * 0.5
			found = true
			break
	# ↑ 그래도 못 찾으면 위로
	if not found:
		for y in range(cell.y - 1, b.position.y - 1, -1):
			var c2 := Vector2i(cell.x, y)
			if _grid_nav.is_walkable(c2):
				global_position = Vector2(c2) * _cell_px + _cell_px * 0.5
				break

func _physics_process(delta: float) -> void:
	match _mode:
		Mode.IDLE:
			return
		Mode.MOVE_TO:
			_move_along_path(delta)
		Mode.FOLLOW:
			_time_since_repath += delta
			if _time_since_repath >= repath_interval_sec:
				_time_since_repath = 0.0
				_repath_follow()
			_move_along_path(delta)

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API

## 셀 목표로 이동(가장 가까운 표면으로 GridNav가 스냅)
func move_to_cell(cell: Vector2i) -> void:
	_follow_target = null
	_goal_cell = cell
	_rebuild_path_to(cell)
	_mode = (Mode.MOVE_TO if _path.size() >= 2 else Mode.IDLE)

## 월드 좌표 목표로 이동
func move_to_world(world_pos: Vector2) -> void:
	move_to_cell(_world_to_cell(world_pos))

## 타겟 노드를 따라가기(주기적으로 재탐색)
func follow_node(node: Node2D) -> void:
	_follow_target = node
	_time_since_repath = 9999.0 # 바로 한 번 재탐색 유도
	_mode = Mode.FOLLOW

## 정지
func stop() -> void:
	_mode = Mode.IDLE
	_path.clear()
	_path_index = 0
	_show_path_preview([])

# ────────────────────────────────────────────────────────────────────
# 내부: 이동/경로

func _move_along_path(delta: float) -> void:
	if _path.is_empty():
		_mode = Mode.IDLE
		return

	# 현재 목표 경유점
	if _path_index >= _path.size():
		_finish_path()
		return

	var p := global_position
	var t := _path[_path_index]
	var to_target := t - p
	var dist := to_target.length()

	if dist <= arrive_epsilon_px:
		_path_index += 1
		if _path_index >= _path.size():
			_finish_path()
		return

	var dir: Vector2 = to_target / max(dist, 0.0001)
	global_position += dir * move_speed * delta

func _finish_path() -> void:
	if _mode == Mode.MOVE_TO:
		_mode = Mode.IDLE
	_show_path_preview([])

func _rebuild_path_to(cell: Vector2i) -> void:
	if _grid_nav == null:
		return
	var start_cell := _world_to_cell(global_position)
	var pts := _grid_nav.find_path(start_cell, cell)
	_path = pts
	_path_index = 0
	_show_path_preview(_path)

func _repath_follow() -> void:
	if _follow_target == null or _grid_nav == null:
		_mode = Mode.IDLE
		return
	var target_cell := _world_to_cell(_follow_target.global_position)
	if target_cell != _goal_cell or _path.is_empty():
		_goal_cell = target_cell
		_rebuild_path_to(_goal_cell)

# ────────────────────────────────────────────────────────────────────
# 내부: 지형 변경 반응

func _on_nav_changed(_cell: Vector2i) -> void:
	# 간단하게: 경로가 있으면 재탐색(부분 검증 로직은 추후 최적화)
	if _mode != Mode.IDLE:
		_rebuild_path_to(_goal_cell)

func _on_nav_bulk_changed(_rect: Rect2i) -> void:
	if _mode != Mode.IDLE:
		_rebuild_path_to(_goal_cell)

# ────────────────────────────────────────────────────────────────────
# 유틸

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / _cell_px.x), floor(p.y / _cell_px.y))

func _show_path_preview(points: PackedVector2Array) -> void:
	if not show_own_path_preview: 
		return
	if _overlay and _overlay.has_method("set_path_preview"):
		_overlay.call("set_path_preview", points)
