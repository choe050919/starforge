extends Node2D
class_name NavigationOverlay

@export var grid_nav_path: NodePath
@export var cost_provider_path: NodePath    # 선택(없으면 코스트 히트맵 비활성)

# ── 표시 옵션 ───────────────────────────────────────────────────────
@export var show_cells: bool = true          # 셀 배경: 통행가능/차단 or 코스트 히트맵
@export var show_edges: bool = true          # 셀 센터 ↔ 이웃 센터 간선
@export var show_path_preview: bool = true   # 경로 프리뷰

@export var show_only_in_view: bool = true
@export var cell_alpha: float = 0.30
@export var draw_cell_border: bool = false   # 성능을 위해 기본 false 권장
@export var edge_width: float = 1.0
@export var edge_color: Color = Color(0.15, 0.85, 1.0, 0.65)
@export var path_width: float = 2.0
@export var path_color: Color = Color(0.20, 0.70, 1.0, 0.90)

# ── 성능/가독성 트레이드오프 ────────────────────────────────────────
@export var edge_stride: int = 1             # 2~3 권장(넓은 뷰에서 간선 간격 샘플링)
@export var max_edge_draw_area: int = 8000   # 더티 영역 셀 개수가 이 값 초과면 간선 생략

var tile_px: Vector2i = Vector2i(32, 32)     ## 타일 픽셀(외부에서 세팅 권장)

var _grid_nav: Node = null
var _cost_provider: Node = null

var _dirty_rects: Array[Rect2i] = []
var _full_redraw := true

# Path 프리뷰는 Line2D로 분리(프레임당 draw 호출 최소화)
var _path_line: Line2D

# ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
	# GridNav 시그널 연결(있을 때만)
	if _grid_nav and _grid_nav.has_signal("navigation_cell_changed"):
		_grid_nav.navigation_cell_changed.connect(_on_nav_cell_changed)
	if _grid_nav and _grid_nav.has_signal("navigation_bulk_changed"):
		_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)

	if cost_provider_path != NodePath() and has_node(cost_provider_path):
		_cost_provider = get_node(cost_provider_path)

	# Path 프리뷰용 Line2D 생성
	_path_line = Line2D.new()
	_path_line.width = path_width
	_path_line.default_color = path_color
	_path_line.visible = show_path_preview
	_path_line.texture_mode = Line2D.LINE_TEXTURE_NONE
	add_child(_path_line)

	_full_redraw = true
	queue_redraw()

# ── 외부 API ────────────────────────────────────────────────────────
func set_path_preview(world_points: PackedVector2Array) -> void:
	# Line2D로 직접 반영(프레임당 draw 없음; points 갱신시에만 비용)
	_path_line.points = world_points
	_path_line.visible = show_path_preview

func clear_path_preview() -> void:
	_path_line.clear_points()
	_path_line.visible = show_path_preview

# ── GridNav 이벤트 수신 ─────────────────────────────────────────────
func _on_nav_cell_changed(cell: Vector2i) -> void:
	_dirty_rects.append(Rect2i(cell, Vector2i.ONE))
	queue_redraw()

func _on_nav_bulk_changed(rect: Rect2i) -> void:
	_dirty_rects.append(rect)
	queue_redraw()

# ── 그리기 ──────────────────────────────────────────────────────────
func _draw() -> void:
	if _grid_nav == null:
		return

	# 0) 필수 값/메서드 참조 캐싱 (리플렉션 비용 제거)
	var iter_bounds: Rect2i = _iter_bounds()
	var has_neighbors := _grid_nav.has_method("neighbors")
	var neighbors_fn = _grid_nav.neighbors if has_neighbors else null

	var is_walkable_fn = (
		func(c: Vector2i) -> bool:
			return not _grid_nav.is_point_solid(c)
	) if _grid_nav.has_method("is_point_solid") else (
		_grid_nav.is_walkable if _grid_nav.has_method("is_walkable") else func(_c: Vector2i) -> bool: return true
	)

	var using_cost := _cost_provider != null and _cost_provider.has_method("movement_cost")
	var movement_cost_fn = _cost_provider.movement_cost if using_cost else null

	# 1) 더티 합치기 + 뷰 제한
	var rect_to_draw: Rect2i = (iter_bounds if _full_redraw else _merge_dirty(_dirty_rects))
	_full_redraw = false
	_dirty_rects.clear()

	if show_only_in_view:
		rect_to_draw = rect_to_draw.intersection(_visible_cells_rect(iter_bounds))
	else:
		rect_to_draw = rect_to_draw.intersection(iter_bounds)

	if rect_to_draw.size.x <= 0 or rect_to_draw.size.y <= 0:
		return

	var cs: Vector2 = tile_px
	var x0 := rect_to_draw.position.x
	var y0 := rect_to_draw.position.y
	var x1 := x0 + rect_to_draw.size.x
	var y1 := y0 + rect_to_draw.size.y
	var area := rect_to_draw.size.x * rect_to_draw.size.y

	# 2) 셀 배경
	if show_cells:
		for y in range(y0, y1):
			for x in range(x0, x1):
				var c := Vector2i(x, y)
				var rect := _cell_rect(c, cs)
				var col: Color
				if using_cost:
					var v := float(movement_cost_fn.call(c))
					col = _cost_to_color(v, cell_alpha)
				else:
					var walk: bool = bool(is_walkable_fn.call(c))
					col = (Color(0.15, 0.9, 0.3, cell_alpha) if walk else Color(0.95, 0.2, 0.2, cell_alpha))
				draw_rect(rect, col, true)
				if draw_cell_border:
					draw_rect(rect, Color(0,0,0,0.18), false, 1.0)

	# 3) 간선(큰 더티 영역은 생략하여 스파이크 방지)
	var draw_edges_now := show_edges and (area <= max_edge_draw_area)
	if draw_edges_now and has_neighbors:
		var stride: int = max(1, edge_stride)
		for y in range(y0, y1):
			if stride > 1 and (y % stride != 0): 
				continue
			for x in range(x0, x1):
				if stride > 1 and (x % stride != 0):
					continue
				var c := Vector2i(x, y)
				if not bool(is_walkable_fn.call(c)):
					continue
				var p := _cell_center(c, cs)

				# 실제 그래프 간선을 사용. 중복 방지를 위해 사전식 순서로 필터
				var neighs: Array = neighbors_fn.call(c)
				for n in neighs:
					if not _in_bounds(n, iter_bounds):
						continue
					# (x,y) < (nx,ny) 일 때만 그리기 → 중복 라인 제거
					if n.y > c.y or (n.y == c.y and n.x > c.x):
						draw_line(p, _cell_center(n, cs), edge_color, edge_width, true)

	# Path 프리뷰는 Line2D가 담당(여기서 따로 draw 안 함)

# ── 유틸 ────────────────────────────────────────────────────────────
func _iter_bounds() -> Rect2i:
	return _grid_nav.iter_bounds() if _grid_nav and _grid_nav.has_method("iter_bounds") \
		else Rect2i(Vector2i.ZERO, Vector2i(128, 72)) # 안전 기본값

func _in_bounds(cell: Vector2i, bounds: Rect2i) -> bool:
	return cell.x >= bounds.position.x and cell.y >= bounds.position.y \
		and cell.x < bounds.position.x + bounds.size.x and cell.y < bounds.position.y + bounds.size.y

func _cell_rect(cell: Vector2i, cs: Vector2) -> Rect2:
	var origin := Vector2(cell.x * cs.x, cell.y * cs.y)
	return Rect2(origin, cs)

func _cell_center(cell: Vector2i, cs: Vector2) -> Vector2:
	return Vector2(cell.x * cs.x + cs.x * 0.5, cell.y * cs.y + cs.y * 0.5)

func _merge_dirty(list: Array[Rect2i]) -> Rect2i:
	if list.is_empty():
		return _iter_bounds()
	var minx := list[0].position.x
	var miny := list[0].position.y
	var maxx := list[0].position.x + list[0].size.x
	var maxy := list[0].position.y + list[0].size.y
	for r in list:
		minx = min(minx, r.position.x)
		miny = min(miny, r.position.y)
		maxx = max(maxx, r.position.x + r.size.x)
		maxy = max(maxy, r.position.y + r.size.y)
	return Rect2i(Vector2i(minx, miny), Vector2i(maxx - minx, maxy - miny))

func _visible_cells_rect(bounds: Rect2i) -> Rect2i:
	var cs := tile_px
	var cam := get_viewport().get_camera_2d()
	if cam:
		# 화면 크기(픽셀) → 카메라 줌을 고려해 월드 Half-Extents로 변환
		var vp_size := get_viewport_rect().size
		var half := (vp_size * 0.5) / cam.zoom
		# 카메라의 화면 중앙 월드 좌표
		var center := cam.get_screen_center_position()
		var tl := center - half   # 월드 좌상
		var br := center + half   # 월드 우하

		var top_left := Vector2i(floor(tl.x / cs.x), floor(tl.y / cs.y))
		var bottom_right := Vector2i(ceil(br.x / cs.x), ceil(br.y / cs.y))

		# 경계 버퍼(스크롤 시 깜빡임 방지)
		top_left -= Vector2i.ONE
		bottom_right += Vector2i.ONE

		var rect := Rect2i(top_left, bottom_right - top_left)
		return rect.intersection(bounds)

	# 카메라가 없으면 전체
	return bounds

# 코스트 → 색 변환 헬퍼(선형 blue→yellow 스케일)
func _cost_to_color(v: float, a: float) -> Color:
	var t: float = clamp(v / 100.0, 0.0, 1.0)  # 필요시 100.0을 max로 익스포트 변수화
	if t < 0.5:
		var k := t * 2.0
		return Color(0.0 + k, 0.0 + k, 1.0 - k, a)
	else:
		var k2 := (t - 0.5) * 2.0
		return Color(1.0, 1.0 - k2, 0.0, a)
