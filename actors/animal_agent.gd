extends Node2D
class_name AnimalAgent
## GridNav 표면 그래프를 따라 셀 센터 경유점(월드 좌표)로 이동하는 에이전트.
## - 선형 보간 이동(오버슈트 방지)
## - 재탐색 시 "현재 위치 기준"으로 경로를 당겨 채택(과거 셀 센터로 끌림 방지)
## - FOLLOW 재탐색 주기 + 문턱 + 디바운스
## - 셀 판정 히스테리시스(대각선/경계 떨림 완화)
## - Nav 변경 신호에 쿨다운 방식으로 반응
## - 오버레이가 있으면 경로 프리뷰 출력(옵션)

# ── 외부 참조 ───────────────────────────────────────────────────────
@export var grid_nav_path: NodePath
@export var overlay_path: NodePath

# ── 이동 튜닝 ───────────────────────────────────────────────────────
@export var move_speed: float = 120.0           # px/sec
@export var arrive_epsilon_px: float = 10.0     # 경유점 도착 판정(셀 크기 32일 때 8~16 권장)
@export var show_own_path_preview: bool = true  # 내 경로를 오버레이에 띄우기

# ── 추적/재탐색 ─────────────────────────────────────────────────────
@export var repath_interval_sec: float = 0.35   # FOLLOW 기본 주기
@export var repath_cooldown_sec: float = 0.15   # 재탐색 쿨다운(신호/빈번 변동 대응)
@export var follow_repath_threshold_px: float = 12.0  # 타겟 이동 문턱(미세 흔들림 무시)

# ── 셀 판정 안정화 ──────────────────────────────────────────────────
@export var cell_hysteresis_px: float = 8.0     # 셀 중심에서 이만큼 벗어나야 start_cell 갱신

# ── 내부 상태 ───────────────────────────────────────────────────────
enum Mode { IDLE, MOVE_TO, FOLLOW }
var _mode: int = Mode.IDLE

var _grid_nav: Node = null
var _overlay: Node = null
var _cell_px: Vector2 = Vector2(32, 32)         # GridNav.cell_size가 있으면 덮어씀

var _path: PackedVector2Array = []              # 월드 좌표 경유점
var _path_index: int = 0
var _goal_cell: Vector2i = Vector2i(-9999, -9999)

var _follow_target: Node2D = null
var _time_since_repath := 0.0
var _repath_cooldown_left := 0.0

var _last_start_cell: Vector2i = Vector2i(-9999, -9999)

# ────────────────────────────────────────────────────────────────────
# 수명주기

func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
		if "cell_size" in _grid_nav:
			_cell_px = _grid_nav.cell_size
		# 네비 변화 신호 연결(쿨다운만 갱신)
		if _grid_nav.has_signal("navigation_cell_changed"):
			_grid_nav.navigation_cell_changed.connect(_on_nav_changed)
		if _grid_nav.has_signal("navigation_bulk_changed"):
			_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)

	if overlay_path != NodePath() and has_node(overlay_path):
		_overlay = get_node(overlay_path)

	call_deferred("_snap_start_to_surface")

func _physics_process(delta: float) -> void:
	_repath_cooldown_left = max(_repath_cooldown_left - delta, 0.0)

	match _mode:
		Mode.IDLE:
			return

		Mode.MOVE_TO:
			_move_along_path(delta)

		Mode.FOLLOW:
			_time_since_repath += delta
			if _time_since_repath >= repath_interval_sec and _repath_cooldown_left <= 0.0:
				_time_since_repath = 0.0
				_repath_follow()
			_move_along_path(delta)

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API

## 셀 목표로 이동(목표가 공중이어도 GridNav가 표면으로 스냅한다고 가정)
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
	_time_since_repath = 9999.0  # 즉시 한 번 재탐색
	_mode = Mode.FOLLOW

## 정지
func stop() -> void:
	_mode = Mode.IDLE
	_path.clear()
	_path_index = 0
	_show_path_preview([])

# ────────────────────────────────────────────────────────────────────
# 내부: 시작 위치 스냅

func _snap_start_to_surface() -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("iter_bounds") or not _grid_nav.has_method("is_walkable"):
		return

	var b: Rect2i = _grid_nav.iter_bounds()
	var cell := _world_to_cell(global_position)
	cell.x = clamp(cell.x, b.position.x, b.position.x + b.size.x - 1)

	var found := false
	# ↓ 아래로 우선 탐색
	for y in range(cell.y, b.position.y + b.size.y):
		var c2 := Vector2i(cell.x, y)
		if _grid_nav.is_walkable(c2):
			global_position = Vector2(c2) * _cell_px + _cell_px * 0.5
			_last_start_cell = c2
			found = true
			break
	# ↑ 못 찾으면 위로
	if not found:
		for y in range(cell.y - 1, b.position.y - 1, -1):
			var c2 := Vector2i(cell.x, y)
			if _grid_nav.is_walkable(c2):
				global_position = Vector2(c2) * _cell_px + _cell_px * 0.5
				_last_start_cell = c2
				break

# ────────────────────────────────────────────────────────────────────
# 내부: 이동(오버슈트 방지 + 연속 소비)

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
			# 스냅 후 다음 경유점
			global_position = t
			_path_index += 1
			continue

		var step := move_speed * delta

		if step >= dist:
			# 이번 프레임에 도달 가능 → 스냅하고 남은 시간으로 다음 점도 처리
			global_position = t
			_path_index += 1
			delta -= dist / max(move_speed, 0.0001)
			continue

		# 아직 멀다 → 남은 거리보다 크게는 이동하지 않게
		var dir := to_target / dist
		global_position = p + dir * step
		break

	if _path_index >= _path.size():
		_finish_path()

func _finish_path() -> void:
	if _mode == Mode.MOVE_TO:
		_mode = Mode.IDLE
	_show_path_preview([])

# ────────────────────────────────────────────────────────────────────
# 내부: 경로 재생성/채택

func _rebuild_path_to(cell: Vector2i) -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("find_path"):
		return

	var start_cell := _stable_start_cell_from_world(global_position)
	var pts: PackedVector2Array = _grid_nav.find_path(start_cell, cell)  # 월드 좌표 경유점 가정
	if pts.is_empty():
		_path = []
		_path_index = 0
		_show_path_preview(_path)
		return

	# 📌 재탐색 시 과거 셀 센터로 끌려가는 현상 방지: 현재 위치 기준으로 경로를 당겨 채택
	_adopt_path_from_current_position(pts)
	_show_path_preview(_path)

func _repath_follow() -> void:
	if _follow_target == null or _grid_nav == null:
		_mode = Mode.IDLE
		return

	var target_cell := _world_to_cell(_follow_target.global_position)

	# FOLLOW 문턱: 목표 셀의 센터 간 실제 이동량이 충분히 클 때만 재탐색
	var goal_center := Vector2(_goal_cell) * _cell_px + _cell_px * 0.5
	var target_center := Vector2(target_cell) * _cell_px + _cell_px * 0.5
	var moved_far_enough := (_goal_cell == Vector2i(-9999, -9999)) \
		or (target_center - goal_center).length() >= follow_repath_threshold_px

	if (target_cell != _goal_cell and moved_far_enough) or _path.is_empty():
		_goal_cell = target_cell
		_rebuild_path_to(_goal_cell)
		_repath_cooldown_left = repath_cooldown_sec

# ────────────────────────────────────────────────────────────────────
# 내부: Nav 변경 반응(디바운스)

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

# 셀 판정 히스테리시스: 최근 start_cell 기준으로 일정 반경 벗어날 때만 갱신
func _stable_start_cell_from_world(p: Vector2) -> Vector2i:
	var raw := _world_to_cell(p)
	if _last_start_cell.x < -9998:
		_last_start_cell = raw
		return _last_start_cell

	var center := Vector2(_last_start_cell) * _cell_px + _cell_px * 0.5
	if (p - center).length() >= cell_hysteresis_px:
		_last_start_cell = raw
	return _last_start_cell

# 새 경로를 "현재 위치"에 맞춰 앞쪽으로 당겨 채택
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

# 폴리라인(연속 선분) 최근접점 계산
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

# 프리뷰 표시
func _show_path_preview(points: PackedVector2Array) -> void:
	if not show_own_path_preview:
		return
	if _overlay and _overlay.has_method("set_path_preview"):
		_overlay.call("set_path_preview", points)
