extends Node
class_name GridNav

signal navigation_cell_changed(cell: Vector2i)
signal navigation_bulk_changed(rect: Rect2i)

var _grid_index: GridIndex
var _phase: PhaseStore
var _data: DataLayer

@export var cell_size := Vector2(32, 32)

# 내부 그래프: 플랫폼 규칙을 위한 수동 그래프
var _astar := AStar2D.new()

# 셀<->노드ID 매핑
var _id_from_cell: Dictionary = {}         # Vector2i -> int
var _cell_from_id: Dictionary = {}         # int -> Vector2i
var _next_id := 1

# ── 리빌드 제어(① 레이트 리미트 + 디바운스) ────────────────────────────
const REBUILD_MIN_INTERVAL_MS := 100         # 최대 10Hz
var _rebuild_pending := false
var _last_rebuild_msec := 0
var _rate_timer: SceneTreeTimer = null

# ── 변경 범위 축소 알림용(② BBox 누적) ─────────────────────────────────
const BBOX_PAD := 1
var _pending_bbox := Rect2i()
var _has_pending_bbox := false

# ── 부분 패치용 대기열 ─────────────────────────────────────────────────
var _pending_candidates: Dictionary = {}     # key=Vector2i, value=true
var _force_full_scan := false

# ── 풀빌드 분할 처리 옵션 ─────────────────────────────────────────────
@export var chunk_rows_per_frame_full := 64  # 0이면 한 프레임에 전부 처리(기존 방식)

enum _FullStage { NONE, SCAN_SURFACE, ADD_NODES, CONNECT_EDGES, COMMIT_MAPS, DONE }
var _full_stage: int = _FullStage.NONE
var _full_y: int = 0
var _full_surface: PackedByteArray
var _full_id_from_index: PackedInt32Array
var _full_w := 0
var _full_h := 0

func _ready() -> void:
	set_process(true)

# ── 인덱스 유틸 ────────────────────────────────────────────────────────
func _index_of(c: Vector2i) -> int:
	return c.x + c.y * _grid_index.size.x

func _in_bounds(c: Vector2i) -> bool:
	return _grid_index.in_bounds_cell(c)

# ──────────────────────────────────────────────────────────────────────
func setup(data: DataLayer) -> void:
	# 기존 연결 해제
	if _data and _data.tiles_changed.is_connected(_on_tiles_changed):
		_data.tiles_changed.disconnect(_on_tiles_changed)

	_data = data
	_grid_index = data.index
	_phase = data.phase

	# DataLayer 단일 이벤트로 수신 (지연 연결로 재진입 방지)
	_data.tiles_changed.connect(_on_tiles_changed, CONNECT_DEFERRED)

	# 초기: 전체 리빌드 예약 + 전체 범위 알림
	_accumulate_bbox_full()
	_force_full_scan = true
	_schedule_rebuild()

# ──────────────────────────────────────────────────────────────────────
# DataLayer 통합 이벤트 수신
func _on_tiles_changed(changed_indices: PackedInt32Array, reason: StringName, payload: Dictionary) -> void:
	var phase_changed := bool(payload.get("phase_changed", false))
	var full_refresh := bool(payload.get("full_refresh", false))

	if not phase_changed and not full_refresh:
		return

	# 알림용 BBox 누적
	if full_refresh or changed_indices.is_empty():
		_accumulate_bbox_full()
	else:
		_accumulate_bbox_from_indices(changed_indices)

	# 패치 후보 대기열 누적
	if full_refresh:
		_force_full_scan = true
	else:
		_queue_patch_candidates_from_indices(changed_indices)

	_schedule_rebuild()

# ── 디바운스 + 레이트 리미트 ──────────────────────────────────────────
func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_maybe_rebuild")

func _maybe_rebuild() -> void:
	var now_ms := Time.get_ticks_msec()
	var elapsed := now_ms - _last_rebuild_msec
	if elapsed >= REBUILD_MIN_INTERVAL_MS:
		_do_rebuild()
		return

	var wait_sec := float(REBUILD_MIN_INTERVAL_MS - elapsed) / 1000.0
	if _rate_timer == null:
		_rate_timer = get_tree().create_timer(wait_sec)
		_rate_timer.timeout.connect(_on_rate_timer_timeout)

func _on_rate_timer_timeout() -> void:
	_rate_timer = null
	if _rebuild_pending:
		_do_rebuild()

func _do_rebuild() -> void:
	_rebuild_pending = false
	_last_rebuild_msec = Time.get_ticks_msec()

	# 분할 풀빌드가 이미 진행 중이면 계속 진행하도록 두고, 추가로 강제 풀스캔 요청만 갱신
	if _full_stage != _FullStage.NONE and _full_stage != _FullStage.DONE:
		# 이미 진행 중 → 끝나면 누적 bbox만 한 번 더 내보내면 됨
		return

	if _force_full_scan:
		if chunk_rows_per_frame_full > 0:
			_start_full_rebuild_incremental()
		else:
			_rebuild_surface_graph_full()  # 한방 풀빌드
			# 알림은 누적된 BBox만 1회 발송
			if _has_pending_bbox:
				navigation_bulk_changed.emit(_pending_bbox)
				_has_pending_bbox = false
				_pending_bbox = Rect2i()
		_force_full_scan = false
	else:
		_apply_partial_patches()
		if _has_pending_bbox:
			navigation_bulk_changed.emit(_pending_bbox)
			_has_pending_bbox = false
			_pending_bbox = Rect2i()

# ── 분할 풀빌드 메인 루프 ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	# 분할 풀빌드가 진행 중이면 일을 조금씩 처리
	if _full_stage != _FullStage.NONE and _full_stage != _FullStage.DONE:
		_step_full_rebuild_chunk()
		# 끝난 시점에만 한 번 알림
		if _full_stage == _FullStage.DONE:
			_finish_full_rebuild_emit()

func _finish_full_rebuild_emit() -> void:
	_full_stage = _FullStage.NONE
	if _has_pending_bbox:
		navigation_bulk_changed.emit(_pending_bbox)
		_has_pending_bbox = false
		_pending_bbox = Rect2i()

# ── 분할 풀빌드: 시작/스텝 ────────────────────────────────────────────
func _start_full_rebuild_incremental() -> void:
	_astar.clear()
	_id_from_cell.clear()
	_cell_from_id.clear()
	_next_id = 1

	_full_w = _grid_index.size.x
	_full_h = _grid_index.size.y

	var wh := _full_w * _full_h
	_full_surface = PackedByteArray(); _full_surface.resize(wh); _full_surface.fill(0)
	_full_id_from_index = PackedInt32Array(); _full_id_from_index.resize(wh)
	for i in range(wh):
		_full_id_from_index[i] = 0

	_full_stage = _FullStage.SCAN_SURFACE
	_full_y = 0

func _step_full_rebuild_chunk() -> void:
	var rows := chunk_rows_per_frame_full
	if rows <= 0:
		rows = _full_h  # safety

	match _full_stage:
		_FullStage.SCAN_SURFACE:
			var y_end: int = min(_full_y + rows, _full_h)
			var getp = _phase.get_phase if _phase != null else null
			for y in range(_full_y, y_end):
				for x in range(_full_w):
					var c := Vector2i(x, y)
					var below := Vector2i(x, y + 1)
					var air := false
					var solid_below := false
					if getp != null:
						air = getp.call(c) != PhaseStore.Phase.SOLID
						solid_below = (below.y < _full_h) and getp.call(below) == PhaseStore.Phase.SOLID
					if air and solid_below:
						_full_surface[_index_of(c)] = 1
			_full_y = y_end
			if _full_y >= _full_h:
				_full_stage = _FullStage.ADD_NODES
				_full_y = 0

		_FullStage.ADD_NODES:
			var y_end2: int = min(_full_y + rows, _full_h)
			for y in range(_full_y, y_end2):
				for x in range(_full_w):
					var c := Vector2i(x, y)
					var idx := _index_of(c)
					if _full_surface[idx] == 0:
						continue
					var id := _next_id; _next_id += 1
					_full_id_from_index[idx] = id
					var world_pos := Vector2(c) * cell_size + cell_size * 0.5
					_astar.add_point(id, world_pos)
			_full_y = y_end2
			if _full_y >= _full_h:
				_full_stage = _FullStage.CONNECT_EDGES
				_full_y = 0

		_FullStage.CONNECT_EDGES:
			var y_end3: int = min(_full_y + rows, _full_h)
			var getp2 = _phase.get_phase if _phase != null else null
			for y in range(_full_y, y_end3):
				for x in range(_full_w):
					var c := Vector2i(x, y)
					var idx_c := _index_of(c)
					var id_c := _full_id_from_index[idx_c]
					if id_c == 0:
						continue

					var rx := x + 1
					if rx < _full_w:
						var right := Vector2i(rx, y)
						var idx_r := _index_of(right)
						var id_r := _full_id_from_index[idx_r]
						if id_r != 0:
							_astar.connect_points(id_c, id_r, true)

						# 한 칸 오르기(↗): up 표면 + side(right) SOLID
						var uy := y - 1
						if uy >= 0:
							var up := Vector2i(rx, uy)
							var idx_up := _index_of(up)
							var id_up := _full_id_from_index[idx_up]
							if id_up != 0 and getp2 != null and getp2.call(right) == PhaseStore.Phase.SOLID:
								_astar.connect_points(id_c, id_up, true)

						# 한 칸 내리기(↘): down 표면 + side(right) AIR
						var dy := y + 1
						if dy < _full_h:
							var down := Vector2i(rx, dy)
							var idx_down := _index_of(down)
							var id_down := _full_id_from_index[idx_down]
							if id_down != 0 and getp2 != null and getp2.call(right) != PhaseStore.Phase.SOLID:
								_astar.connect_points(id_c, id_down, true)
			_full_y = y_end3
			if _full_y >= _full_h:
				_full_stage = _FullStage.COMMIT_MAPS
				_full_y = 0

		_FullStage.COMMIT_MAPS:
			var y_end4: int = min(_full_y + rows, _full_h)
			for y in range(_full_y, y_end4):
				for x in range(_full_w):
					var c := Vector2i(x, y)
					var idx := _index_of(c)
					var id := _full_id_from_index[idx]
					if id == 0:
						continue
					_id_from_cell[c] = id
					_cell_from_id[id] = c
			_full_y = y_end4
			if _full_y >= _full_h:
				_full_stage = _FullStage.DONE

# ──────────────────────────────────────────────────────────────────────
# (FULL) 내부: 표면 그래프 전체 생성 — 한방(비분할) 최적화 버전
func _rebuild_surface_graph_full() -> void:
	_force_full_scan = false

	# 0) 초기화
	_astar.clear()
	_id_from_cell.clear()
	_cell_from_id.clear()
	_next_id = 1

	var w := _grid_index.size.x
	var h := _grid_index.size.y
	if w <= 0 or h <= 0:
		return
	var wh := w * h

	# 1) 표면 캐시(한 번만 판정)
	var surface := PackedByteArray()
	surface.resize(wh)
	surface.fill(0)
	var getp = _phase.get_phase if _phase != null else null

	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			var below := Vector2i(x, y + 1)
			var air := false
			var solid_below := false
			if getp != null:
				air = getp.call(c) != PhaseStore.Phase.SOLID
				solid_below = (below.y < h) and getp.call(below) == PhaseStore.Phase.SOLID
			if air and solid_below:
				surface[_index_of(c)] = 1

	# 2) id_from_index + AStar 노드 생성
	var id_from_index := PackedInt32Array()
	id_from_index.resize(wh)
	for i in range(wh):
		id_from_index[i] = 0

	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			var idx := _index_of(c)
			if surface[idx] == 0:
				continue
			var id := _next_id
			_next_id += 1
			id_from_index[idx] = id
			var world_pos := Vector2(c) * cell_size + cell_size * 0.5
			_astar.add_point(id, world_pos)

	# 3) 간선 연결(중복 없는 방향만)
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			var idx_c := _index_of(c)
			var id_c := id_from_index[idx_c]
			if id_c == 0:
				continue

			var rx := x + 1
			if rx < w:
				var right := Vector2i(rx, y)
				var idx_r := _index_of(right)
				var id_r := id_from_index[idx_r]
				if id_r != 0:
					_astar.connect_points(id_c, id_r, true)

				# up(↗): up 표면 + side(right) SOLID
				var uy := y - 1
				if uy >= 0:
					var up := Vector2i(rx, uy)
					var idx_up := _index_of(up)
					var id_up := id_from_index[idx_up]
					if id_up != 0 and getp != null and getp.call(right) == PhaseStore.Phase.SOLID:
						_astar.connect_points(id_c, id_up, true)

				# down(↘): down 표면 + side(right) AIR
				var dy := y + 1
				if dy < h:
					var down := Vector2i(rx, dy)
					var idx_down := _index_of(down)
					var id_down := id_from_index[idx_down]
					if id_down != 0 and getp != null and getp.call(right) != PhaseStore.Phase.SOLID:
						_astar.connect_points(id_c, id_down, true)

	# 4) 딕셔너리 테이블 채우기(퍼블릭 API 호환)
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			var idx := _index_of(c)
			var id := id_from_index[idx]
			if id == 0:
				continue
			_id_from_cell[c] = id
			_cell_from_id[id] = c

# ──────────────────────────────────────────────────────────────────────
# (PARTIAL) 변경된 주변만 로컬 패치 — 기존 방식 유지
func _apply_partial_patches() -> void:
	if _pending_candidates.is_empty():
		return

	# 후보 목록 스냅샷 & 큐 비우기
	var cells: Array = _pending_candidates.keys()
	_pending_candidates.clear()

	# 1) 표면 상태 동기화 (노드 추가/삭제)
	for c in cells:
		var was_surface := _was_surface(c)
		var now_surface := _is_surface(c)
		if was_surface and (not now_surface):
			_remove_node(c)
		elif (not was_surface) and now_surface:
			_add_node(c)

	# 2) 간선 재구축 (후보들만)
	for c in cells:
		if _id_from_cell.has(c):
			_rebuild_links_for(c)

# ──────────────────────────────────────────────────────────────────────
# 퍼블릭 API (기존 시그니처 유지)

func set_walkable(cell: Vector2i, walkable: bool) -> void:
	# 현재 규칙상 외부에서 직접 walkable을 강제하지 않고,
	# Phase 변화로 표면 판정을 유도한다고 가정. 여기서는 "변경 후보"와 "알림"만 처리.
	if not _grid_index.in_bounds_cell(cell):
		push_warning("[GridNav.set_walkable] not in bounds")
	_accumulate_bbox_from_cells([cell])
	_queue_patch_candidates_from_cells([cell])
	_schedule_rebuild()
	navigation_cell_changed.emit(cell)

func find_path(start_cell: Vector2i, goal_cell: Vector2i) -> PackedVector2Array:
	if not _grid_index.in_bounds_cell(start_cell):
		push_warning("[GridNav.find_path] start_cell not in bounds")
	if not _grid_index.in_bounds_cell(goal_cell):
		push_warning("[GridNav.find_path] goal_cell not in bounds")

	var sid := _ensure_node_for_or_near_surface(start_cell)
	var gid := _ensure_node_for_or_near_surface(goal_cell)
	if sid == 0 or gid == 0:
		return []

	var pts := _astar.get_point_path(sid, gid)
	var arr := PackedVector2Array()
	for p in pts:
		arr.push_back(p)
	return arr

func mark_region_rebuilt(rect: Rect2i) -> void:
	_accumulate_bbox(rect)
	_schedule_rebuild()

func is_walkable(cell: Vector2i) -> bool:
	return _is_surface(cell)

func iter_bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, _grid_index.size)

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var id: int = _id_from_cell.get(cell, 0)
	if id == 0:
		return out
	for nid in _astar.get_point_connections(id):
		out.append(_cell_from_id[nid])
	return out

# ──────────────────────────────────────────────────────────────────────
# 표면/공기/솔리드 헬퍼

func _is_solid_safe(c: Vector2i) -> bool:
	if not _grid_index.in_bounds_cell(c):
		return false
	return _phase != null and _phase.get_phase(c) == PhaseStore.Phase.SOLID

func _is_air_safe(c: Vector2i) -> bool:
	if not _grid_index.in_bounds_cell(c):
		return false
	return not _is_solid_safe(c)

func _is_solid(c: Vector2i) -> bool:
	return _is_solid_safe(c)

func _is_air(c: Vector2i) -> bool:
	return _is_air_safe(c)

func _is_surface(c: Vector2i) -> bool:
	if not _grid_index.in_bounds_cell(c):
		return false
	var below := c + Vector2i(0, 1)
	return _is_air_safe(c) and _is_solid_safe(below)

func _was_surface(c: Vector2i) -> bool:
	return _id_from_cell.has(c)

# 시작/목표가 표면이 아닐 때: 같은 열에서 가장 가까운 표면을 탐색해 스냅
func _ensure_node_for_or_near_surface(c: Vector2i) -> int:
	if _id_from_cell.has(c):
		return _id_from_cell[c]

	# 위로 스캔(0~3칸)
	for dy in range(0, 4):
		var up := c - Vector2i(0, dy)
		if _id_from_cell.has(up):
			return _id_from_cell[up]

	# 아래로 스캔(1~5칸)
	for dy in range(1, 6):
		var down := c + Vector2i(0, dy)
		if _id_from_cell.has(down):
			return _id_from_cell[down]

	return 0

# ──────────────────────────────────────────────────────────────────────
# 노드/간선 유틸

func _add_node(cell: Vector2i) -> void:
	if _id_from_cell.has(cell):
		return
	var id := _next_id
	_next_id += 1
	_id_from_cell[cell] = id
	_cell_from_id[id] = cell
	var world_pos := Vector2(cell) * cell_size + cell_size * 0.5
	_astar.add_point(id, world_pos)

func _remove_node(cell: Vector2i) -> void:
	if not _id_from_cell.has(cell):
		return
	var id: int = _id_from_cell[cell]
	_astar.remove_point(id)  # 연결도 함께 제거됨
	_id_from_cell.erase(cell)
	_cell_from_id.erase(id)

func _node_id(cell: Vector2i) -> int:
	return int(_id_from_cell.get(cell, 0))

# 간선 규칙 재구성: 좌/우 평지 + 한 칸 오르기/내리기 (옆 칸 공기/솔리드 가드)
func _rebuild_links_for(c: Vector2i) -> void:
	var id_c := _node_id(c)
	if id_c == 0:
		return

	for dir_x in [-1, 1]:
		var side := c + Vector2i(dir_x, 0)
		var up := c + Vector2i(dir_x, -1)
		var down := c + Vector2i(dir_x, 1)

		# 평지
		_connect_if(id_c, _node_id(side), _can_step_flat(c, dir_x))

		# 한 칸 오르기 (↗/↖) — side는 '솔리드'여야 함
		_connect_if(id_c, _node_id(up), _can_step_up(c, dir_x))

		# 한 칸 내리기 (↘/↙) — side는 '공기'여야 함
		_connect_if(id_c, _node_id(down), _can_step_down(c, dir_x))

func _can_step_flat(from: Vector2i, dir_x: int) -> bool:
	var to := from + Vector2i(dir_x, 0)
	return _id_from_cell.has(from) and _id_from_cell.has(to)

func _can_step_up(from: Vector2i, dir_x: int) -> bool:
	var side := from + Vector2i(dir_x, 0)
	var up := from + Vector2i(dir_x, -1)
	return _id_from_cell.has(from) \
		and _id_from_cell.has(up) \
		and _is_solid_safe(side)

func _can_step_down(from: Vector2i, dir_x: int) -> bool:
	var side := from + Vector2i(dir_x, 0)
	var down := from + Vector2i(dir_x, 1)
	return _id_from_cell.has(from) \
		and _id_from_cell.has(down) \
		and _is_air_safe(side)

func _connect_if(a_id: int, b_id: int, cond: bool) -> void:
	if a_id == 0 or b_id == 0:
		return
	var connected := _astar.are_points_connected(a_id, b_id)
	if cond:
		if not connected:
			_astar.connect_points(a_id, b_id, true)
	else:
		if connected:
			_astar.disconnect_points(a_id, b_id)

# ──────────────────────────────────────────────────────────────────────
# BBox 유틸(② 변경 범위 축소 알림)

func _accumulate_bbox_full() -> void:
	_accumulate_bbox(iter_bounds())

func _accumulate_bbox_from_indices(indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var w := _grid_index.size.x
	var h := _grid_index.size.y
	var minx := 0x7fffffff
	var miny := 0x7fffffff
	var maxx := -0x7fffffff
	var maxy := -0x7fffffff
	for i in indices:
		var cx := int(i) % w
		var cy := int(i) / w
		if cx < minx: minx = cx
		if cy < miny: miny = cy
		if cx > maxx: maxx = cx
		if cy > maxy: maxy = cy
	if minx > maxx or miny > maxy:
		return
	# 패딩 적용 + 경계 클램프
	minx = clamp(minx - BBOX_PAD, 0, w - 1)
	miny = clamp(miny - BBOX_PAD, 0, h - 1)
	maxx = clamp(maxx + BBOX_PAD, 0, w - 1)
	maxy = clamp(maxy + BBOX_PAD, 0, h - 1)
	var rect := Rect2i(Vector2i(minx, miny), Vector2i(maxx - minx + 1, maxy - miny + 1))
	_accumulate_bbox(rect)

func _accumulate_bbox_from_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var w := _grid_index.size.x
	var h := _grid_index.size.y
	var minx := 0x7fffffff
	var miny := 0x7fffffff
	var maxx := -0x7fffffff
	var maxy := -0x7fffffff
	for c in cells:
		if not _grid_index.in_bounds_cell(c):
			continue
		if c.x < minx: minx = c.x
		if c.y < miny: miny = c.y
		if c.x > maxx: maxx = c.x
		if c.y > maxy: maxy = c.y
	if minx > maxx or miny > maxy:
		return
	minx = clamp(minx - BBOX_PAD, 0, w - 1)
	miny = clamp(miny - BBOX_PAD, 0, h - 1)
	maxx = clamp(maxx + BBOX_PAD, 0, w - 1)
	maxy = clamp(maxy + BBOX_PAD, 0, h - 1)
	var rect := Rect2i(Vector2i(minx, miny), Vector2i(maxx - minx + 1, maxy - miny + 1))
	_accumulate_bbox(rect)

func _accumulate_bbox(rect: Rect2i) -> void:
	if not _has_pending_bbox:
		_pending_bbox = rect
		_has_pending_bbox = true
		return
	# union
	var a := _pending_bbox
	var minx: int = min(a.position.x, rect.position.x)
	var miny: int = min(a.position.y, rect.position.y)
	var maxx: int = max(a.position.x + a.size.x - 1, rect.position.x + rect.size.x - 1)
	var maxy: int = max(a.position.y + a.size.y - 1, rect.position.y + rect.size.y - 1)
	_pending_bbox = Rect2i(Vector2i(minx, miny), Vector2i(maxx - minx + 1, maxy - miny + 1))

# ──────────────────────────────────────────────────────────────────────
# 부분 패치: 후보 큐잉 유틸

func _queue_patch_candidates_from_indices(indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var w := _grid_index.size.x
	for i in indices:
		var x := int(i) % w
		var y := int(i) / w
		_queue_patch_candidates_from_cells([Vector2i(x, y)])

func _queue_patch_candidates_from_rect(rect: Rect2i) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := x0 + rect.size.x - 1
	var y1 := y0 + rect.size.y - 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_queue_patch_candidates_from_cells([Vector2i(x, y)])

func _queue_patch_candidates_from_cells(cells: Array[Vector2i]) -> void:
	for c in cells:
		if not _grid_index.in_bounds_cell(c):
			continue
		# 핵심 후보: c, c±(0,1)
		_mark_candidate(c)
		_mark_candidate(c + Vector2i(0, -1))
		_mark_candidate(c + Vector2i(0,  1))

		# 간선 검사용: 좌우 및 그들의 위/아래
		for dir_x in [-1, 1]:
			var side := c + Vector2i(dir_x, 0)
			_mark_candidate(side)
			_mark_candidate(side + Vector2i(0, -1))
			_mark_candidate(side + Vector2i(0,  1))

func _mark_candidate(c: Vector2i) -> void:
	if _grid_index.in_bounds_cell(c):
		_pending_candidates[c] = true
