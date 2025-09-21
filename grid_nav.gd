extends Node
class_name GridNav

signal navigation_cell_changed(cell: Vector2i)
signal navigation_bulk_changed(rect: Rect2i)

var _grid_index: GridIndex
var _phase: PhaseStore

var cell_size := Vector2(32, 32)

# 내부 그래프: 플랫폼 규칙을 위한 수동 그래프
var _astar := AStar2D.new()

# 셀<->노드ID 매핑
var _id_from_cell: Dictionary = {}         # Vector2i -> int
var _cell_from_id: Dictionary = {}         # int -> Vector2i
var _next_id := 1

func setup(data: DataLayer) -> void:
	_grid_index = data.index
	_phase = data.phase
	_rebuild_surface_graph()

func _on_phase_changed(cell: Vector2i) -> void:
	# 정확성 우선: 전체 리빌드 (추후 부분 리빌드 최적화 가능)
	_rebuild_surface_graph()
	navigation_cell_changed.emit(cell)

# ────────────────────────────────────────────────────────────────────
# 내부: 표면 그래프 생성 (표면만 노드로 등록, 플랫폼 규칙 간선 연결)
func _rebuild_surface_graph() -> void:
	_astar.clear()
	_id_from_cell.clear()
	_cell_from_id.clear()
	_next_id = 1

	var w := _grid_index.size.x
	var h := _grid_index.size.y

	# 1) 표면 셀만 노드로 추가
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			if _is_surface(c):
				_add_node(c)

	# 2) 간선 연결: 좌/우 평지 + 한 칸 오르기/내리기 (옆 칸 공기 가드)
	#    표면이 아닌 곳은 아예 노드가 없으므로 연결도 없음
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			if not _id_from_cell.has(c):
				continue

			for dir_x in [-1, 1]:
				# 평지: (x±1, y)가 표면이면 연결
				var n_flat := Vector2i(x + dir_x, y)
				if _id_from_cell.has(n_flat):
					_connect(c, n_flat)

				# 한 칸 오르기: 목표 (x±1, y-1)가 표면이고, 옆칸 공기이면 연결
				var n_up := Vector2i(x + dir_x, y - 1)
				if _id_from_cell.has(n_up) and _is_air(Vector2i(x + dir_x, y)):
					_connect(c, n_up)

				# 한 칸 내리기: 목표 (x±1, y+1)가 표면이고, 옆칸 공기이면 연결
				var n_down := Vector2i(x + dir_x, y + 1)
				if _id_from_cell.has(n_down) and _is_air(Vector2i(x + dir_x, y)):
					_connect(c, n_down)

# 노드/간선 유틸
func _add_node(cell: Vector2i) -> void:
	var id := _next_id
	_next_id += 1
	_id_from_cell[cell] = id
	_cell_from_id[id] = cell
	# 위치는 월드 좌표로 등록 (AStar2D는 가중치 추정에 좌표 사용)
	var world_pos := Vector2(cell) * cell_size + cell_size * 0.5
	_astar.add_point(id, world_pos)

func _connect(a: Vector2i, b: Vector2i) -> void:
	var id_a: int = _id_from_cell.get(a, 0)
	var id_b: int = _id_from_cell.get(b, 0)
	if id_a == 0 or id_b == 0: return
	if not _astar.are_points_connected(id_a, id_b):
		_astar.connect_points(id_a, id_b, true) # ← bidirectional = true 로!

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API (기존 시그니처 유지)

func set_walkable(cell: Vector2i, walkable: bool) -> void:
	# 플랫폼 규칙에서는 "walkable = 표면 여부"와 같음 → 부분 리빌드 미구현
	# 우선 전체 리빌드로 일관성 유지
	if not _grid_index.in_bounds_cell(cell):
		push_warning("[GridNav.set_walkable] not in bounds")
	_rebuild_surface_graph()
	navigation_cell_changed.emit(cell)

func find_path(start_cell: Vector2i, goal_cell: Vector2i) -> PackedVector2Array:
	if not _grid_index.in_bounds_cell(start_cell):
		push_warning("[GridNav.find_path] start_cell not in bounds")
	if not _grid_index.in_bounds_cell(goal_cell):
		push_warning("[GridNav.find_path] goal_cell not in bounds")

	# 시작/목표가 표면이 아닐 수 있음 → 가장 가까운 표면으로 스냅 시도
	var sid := _ensure_node_for_or_near_surface(start_cell)
	var gid := _ensure_node_for_or_near_surface(goal_cell)
	if sid == 0 or gid == 0:
		return []

	var pts := _astar.get_point_path(sid, gid)
	# 이미 월드 좌표로 저장되어 있으므로 그대로 반환
	var arr := PackedVector2Array()
	for p in pts:
		arr.push_back(p)
	return arr

func mark_region_rebuilt(rect: Rect2i) -> void:
	navigation_bulk_changed.emit(rect)

func is_walkable(cell: Vector2i) -> bool:
	# “walkable = 표면” 정의에 맞춰 반환
	return _is_surface(cell)

func iter_bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, _grid_index.size)

# ────────────────────────────────────────────────────────────────────
# 헬퍼

func _is_solid(c: Vector2i) -> bool:
	return _phase != null and _phase.get_phase(c) == PhaseStore.Phase.SOLID

func _is_air(c: Vector2i) -> bool:
	return not _is_solid(c)

func _is_surface(c: Vector2i) -> bool:
	# 공기인 타일이고, 그 아래가 솔리드면 “표면”
	return _is_air(c) and _grid_index.in_bounds_cell(c + Vector2i(0, 1)) and _is_solid(c + Vector2i(0, 1))

# 시작/목표가 표면이 아닐 때: 같은 열에서 가장 가까운 표면을 탐색해 스냅
func _ensure_node_for_or_near_surface(c: Vector2i) -> int:
	if _id_from_cell.has(c):
		return _id_from_cell[c]

	# 위로 스캔(머리 위로 올라간 케이스)
	for dy in range(0, 4):
		var up := c - Vector2i(0, dy)
		if _id_from_cell.has(up):
			return _id_from_cell[up]

	# 아래로 스캔(바닥 아래로 떨어진 케이스)
	for dy in range(1, 6):
		var down := c + Vector2i(0, dy)
		if _id_from_cell.has(down):
			return _id_from_cell[down]

	return 0

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var id: int = _id_from_cell.get(cell, 0)
	if id == 0:
		return out
	for nid in _astar.get_point_connections(id):
		out.append(_cell_from_id[nid])
	return out
