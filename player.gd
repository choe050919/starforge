extends Node2D
class_name Player

signal arrived_at_destination

# ── 외부 참조 ───────────────────────────────────────────────────────
@export var grid_nav_path: NodePath
@export var overlay_path: NodePath
@export var ground_path: NodePath

var _grid_nav: GridNav = null
var _overlay: Node = null
var _ground: Ground = null

# ── 이동 튜닝 ───────────────────────────────────────────────────────
@export var move_speed: float = 180.0
@export var arrive_epsilon_px: float = 8.0
@export var show_path_preview: bool = true

# ── 재탐색 ──────────────────────────────────────────────────────────
@export var repath_interval_sec: float = 0.4
@export var repath_cooldown_sec: float = 0.2

var _time_since_repath := 0.0
var _repath_cooldown_left := 0.0

# ── 셀 판정 안정화 ──────────────────────────────────────────────────
@export var cell_hysteresis_px: float = 10.0

# ── 내부 상태 ───────────────────────────────────────────────────────
enum Mode { IDLE, MOVING }
var _mode: int = Mode.IDLE

var _cell_px: Vector2 = Vector2(32, 32)
var _path: PackedVector2Array = []
var _path_index: int = 0
var _goal_cell: Vector2i = Vector2i(-9999, -9999)
var _last_start_cell: Vector2i = Vector2i(-9999, -9999)

# ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
		var cs: Vector2 = _grid_nav.get("cell_size")
		if cs is Vector2:
			_cell_px = cs
		
		# 네비 변경 신호 연결
		if _grid_nav.has_signal("navigation_cell_changed"):
			_grid_nav.navigation_cell_changed.connect(_on_nav_changed)
		if _grid_nav.has_signal("navigation_bulk_changed"):
			_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)
	
	if overlay_path != NodePath() and has_node(overlay_path):
		_overlay = get_node(overlay_path)
	
	if ground_path != NodePath() and has_node(ground_path):
		_ground = get_node(ground_path)
	
	call_deferred("_snap_start_to_surface")

func _physics_process(delta: float) -> void:
	_repath_cooldown_left = max(_repath_cooldown_left - delta, 0.0)
	
	if _mode == Mode.MOVING:
		_time_since_repath += delta
		
		# 주기적 재탐색 (환경 변화 대응)
		if _time_since_repath >= repath_interval_sec and _repath_cooldown_left <= 0.0:
			_time_since_repath = 0.0
			_repath_to_goal()
		
		_move_along_path(delta)

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API

## 월드 좌표로 이동 명령
func move_to_world(world_pos: Vector2) -> void:
	var target_cell := _world_to_cell(world_pos)
	move_to_cell(target_cell)

## 셀 좌표로 이동 명령
func move_to_cell(cell: Vector2i) -> void:
	_goal_cell = cell
	_rebuild_path_to(cell)
	_mode = (Mode.MOVING if _path.size() >= 2 else Mode.IDLE)

## 정지
func stop() -> void:
	_mode = Mode.IDLE
	_path.clear()
	_path_index = 0
	_show_path_preview([])

# ────────────────────────────────────────────────────────────────────
# 내부: 시작 위치 스냅 (표면으로)

func _snap_start_to_surface() -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("iter_bounds") or not _grid_nav.has_method("is_walkable_player"):
		return
	
	var b: Rect2i = _grid_nav.iter_bounds()
	var cell := _world_to_cell(global_position)
	cell.x = clamp(cell.x, b.position.x, b.position.x + b.size.x - 1)
	
	# 아래로 표면 탐색
	for y in range(cell.y, b.position.y + b.size.y):
		var c := Vector2i(cell.x, y)
		if _grid_nav.is_walkable_player(c):
			global_position = Vector2(c) * _cell_px + _cell_px * 0.5
			_last_start_cell = c
			return
	
	# 위로 표면 탐색
	for y in range(cell.y - 1, b.position.y - 1, -1):
		var c := Vector2i(cell.x, y)
		if _grid_nav.is_walkable_player(c):
			global_position = Vector2(c) * _cell_px + _cell_px * 0.5
			_last_start_cell = c
			return

# ────────────────────────────────────────────────────────────────────
# 내부: 이동 (오버슈트 방지)

func _move_along_path(delta: float) -> void:
	if _path.is_empty():
		_mode = Mode.IDLE
		return
	
	var eps: float = max(arrive_epsilon_px, 0.001)
	
	while delta > 0.0 and _path_index < _path.size():
		var p := global_position
		var t := _path[_path_index]
		var to_target := t - p
		var dist := to_target.length()
		
		if dist <= eps:
			global_position = t
			_path_index += 1
			continue
		
		var step := move_speed * delta
		
		if step >= dist:
			global_position = t
			_path_index += 1
			delta -= dist / max(move_speed, 0.0001)
			continue
		
		var dir := to_target / dist
		global_position = p + dir * step
		break
	
	if _path_index >= _path.size():
		_finish_path()

func _finish_path() -> void:
	_mode = Mode.IDLE
	_show_path_preview([])
	arrived_at_destination.emit()

# ────────────────────────────────────────────────────────────────────
# 내부: 경로 재생성

func _rebuild_path_to(cell: Vector2i) -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("find_path_player"):
		push_warning("[Player] GridNav doesn't have find_path_player method")
		return
	
	var start_cell := _stable_start_cell_from_world(global_position)
	var pts: PackedVector2Array = _grid_nav.find_path_player(start_cell, cell)
	
	if pts.is_empty():
		_path = []
		_path_index = 0
		_show_path_preview(_path)
		return
	
	# 현재 위치 기준으로 경로 당겨 채택
	_adopt_path_from_current_position(pts)
	_show_path_preview(_path)

func _repath_to_goal() -> void:
	if _goal_cell.x < -9998:
		return
	_rebuild_path_to(_goal_cell)
	_repath_cooldown_left = repath_cooldown_sec

# ────────────────────────────────────────────────────────────────────
# 내부: Nav 변경 반응

func _on_nav_changed(_cell: Vector2i) -> void:
	if _mode != Mode.IDLE:
		_repath_cooldown_left = repath_cooldown_sec

func _on_nav_bulk_changed(_rect: Rect2i) -> void:
	if _mode != Mode.IDLE:
		_repath_cooldown_left = repath_cooldown_sec

# ────────────────────────────────────────────────────────────────────
# 내부: 유틸

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / _cell_px.x), floor(p.y / _cell_px.y))

func _stable_start_cell_from_world(p: Vector2) -> Vector2i:
	var raw := _world_to_cell(p)
	if _last_start_cell.x < -9998:
		_last_start_cell = raw
		return _last_start_cell
	
	var center := Vector2(_last_start_cell) * _cell_px + _cell_px * 0.5
	if (p - center).length() >= cell_hysteresis_px:
		_last_start_cell = raw
	return _last_start_cell

func _adopt_path_from_current_position(pts: PackedVector2Array) -> void:
	if pts.is_empty():
		_path = []
		_path_index = 0
		return
	
	if pts.size() == 1:
		_path = PackedVector2Array([pts[0]])
		_path_index = 0
		return
	
	var near := _nearest_point_on_polyline(global_position, pts)
	var new_path := PackedVector2Array()
	new_path.append(near.point)
	for i in range(near.seg_idx + 1, pts.size()):
		new_path.append(pts[i])
	
	_path = new_path
	_path_index = 0

func _nearest_point_on_polyline(p: Vector2, pts: PackedVector2Array) -> Dictionary:
	var best_d2 := INF
	var best_idx := 0
	var best_point := pts[0]
	
	for i in range(0, pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		var t := 0.0
		if ab_len2 > 0.0:
			t = clamp(((p - a).dot(ab)) / ab_len2, 0.0, 1.0)
		var proj := a + ab * t
		var d2 := (p - proj).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
			best_point = proj
	
	return {"seg_idx": best_idx, "point": best_point}

func _show_path_preview(points: PackedVector2Array) -> void:
	if not show_path_preview:
		return
	if _overlay and _overlay.has_method("set_path_preview"):
		_overlay.call("set_path_preview", points)
