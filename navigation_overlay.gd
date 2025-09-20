extends Node2D
class_name NavigationOverlay

@export var grid_nav_path: NodePath
@export var cost_provider_path: NodePath    # 선택(없으면 코스트 히트맵 비활성)

# ── 설정값 ─────────────────────────────────────────────────────────
@export var show_cells: bool = true         # 셀 배경: 통행가능/차단 또는 코스트 히트맵
@export var show_edges: bool = true         # 셀 센터 ↔ 이웃 센터 간선
@export var show_path_preview: bool = true  # 경로 프리뷰 선

@export var show_only_in_view: bool = true
@export var cell_alpha: float = 0.30
@export var edge_width: float = 1.0
@export var edge_color: Color = Color(0.15, 0.85, 1.0, 0.65)
@export var path_width: float = 2.0
@export var path_color: Color = Color(0.20, 0.70, 1.0, 0.90)

var tile_px: Vector2i = Vector2i(32, 32)  ## 타일 픽셀(외부에서 세팅 권장)

var _grid_nav: Node = null
var _cost_provider: Node = null

var _dirty_rects: Array[Rect2i] = []
var _full_redraw := true
var _path_preview: PackedVector2Array = []

func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
	# 신호 연결(선택): GridNav가 제공한다면 연결
	if _grid_nav and _grid_nav.has_signal("navigation_cell_changed"):
		_grid_nav.navigation_cell_changed.connect(_on_nav_cell_changed)
	if _grid_nav and _grid_nav.has_signal("navigation_bulk_changed"):
		_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)

	if cost_provider_path != NodePath() and has_node(cost_provider_path):
		_cost_provider = get_node(cost_provider_path)

	_full_redraw = true
	queue_redraw()

func set_path_preview(world_points: PackedVector2Array) -> void:
	_path_preview = world_points
	if show_path_preview:
		queue_redraw()

func clear_path_preview() -> void:
	_path_preview = []
	if show_path_preview:
		queue_redraw()

func _on_nav_cell_changed(cell: Vector2i) -> void:
	_dirty_rects.append(Rect2i(cell, Vector2i.ONE))
	queue_redraw()

func _on_nav_bulk_changed(rect: Rect2i) -> void:
	_dirty_rects.append(rect)
	queue_redraw()

func _draw() -> void:
	if _grid_nav == null:
		return

	var rect_to_draw: Rect2i
	if _full_redraw:
		rect_to_draw = _iter_bounds()
		_full_redraw = false
	else:
		rect_to_draw = _merge_dirty(_dirty_rects)
	_dirty_rects.clear()

	if show_only_in_view:
		rect_to_draw = rect_to_draw.intersection(_visible_cells_rect())


	var cs: Vector2 = tile_px

	# ── 1) 셀 배경 (통행/차단 또는 코스트) ─────────────────────
	if show_cells:
		var using_cost := _cost_provider != null and _cost_provider.has_method("movement_cost")
		for y in range(rect_to_draw.position.y, rect_to_draw.position.y + rect_to_draw.size.y):
			for x in range(rect_to_draw.position.x, rect_to_draw.position.x + rect_to_draw.size.x):
				var c := Vector2i(x, y)
				var rect := _cell_rect(c, cs)
				var col := Color(0,0,0,0)
				if using_cost:
					var v := float(_cost_provider.call("movement_cost", c))
					col = _cost_to_color(v, cell_alpha)
				else:
					var walk := _is_walkable(c)
					col = (Color(0.15, 0.9, 0.3, cell_alpha) if walk else Color(0.95, 0.2, 0.2, cell_alpha))
				draw_rect(rect, col, true)
				draw_rect(rect, Color(0,0,0,0.18), false, 1.0)

	# ── 2) 간선(오른쪽/아래 이웃만) ─────────────────────────────
	if show_edges:
		for y in range(rect_to_draw.position.y, rect_to_draw.position.y + rect_to_draw.size.y):
			for x in range(rect_to_draw.position.x, rect_to_draw.position.x + rect_to_draw.size.x):
				var c := Vector2i(x, y)
				if not _is_walkable(c): continue
				var p := _cell_center(c, cs)
				var r := c + Vector2i(1, 0)
				if _in_bounds(r) and _is_walkable(r):
					draw_line(p, _cell_center(r, cs), edge_color, edge_width, true)
				var d := c + Vector2i(0, 1)
				if _in_bounds(d) and _is_walkable(d):
					draw_line(p, _cell_center(d, cs), edge_color, edge_width, true)

	# ── 3) 경로 프리뷰 ───────────────────────────────────────────
	if show_path_preview and _path_preview.size() >= 2:
		for i in range(0, _path_preview.size() - 1):
			draw_line(_path_preview[i], _path_preview[i+1], path_color, path_width, true)

# ── 유틸 ──────────────────────────────────────────────────────────
func _is_walkable(cell: Vector2i) -> bool:
	return not _grid_nav.is_point_solid(cell) if _grid_nav.has_method("is_point_solid") \
		else (_grid_nav.is_walkable(cell) if _grid_nav.has_method("is_walkable") else true)

func _iter_bounds() -> Rect2i:
	return _grid_nav.iter_bounds() if _grid_nav and _grid_nav.has_method("iter_bounds") \
		else Rect2i(Vector2i.ZERO, Vector2i(128, 72)) # 안전 기본값

func _in_bounds(cell: Vector2i) -> bool:
	var b := _iter_bounds()
	return cell.x >= b.position.x and cell.y >= b.position.y \
		and cell.x < b.position.x + b.size.x and cell.y < b.position.y + b.size.y

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

func _visible_cells_rect() -> Rect2i:
	var cs := tile_px
	var vp := get_viewport_rect()
	var tl := to_local(vp.position)
	var br := to_local(vp.position + vp.size)
	var top_left := Vector2i(floor(tl.x / cs.x), floor(tl.y / cs.y))
	var bottom_right := Vector2i(ceil(br.x / cs.x), ceil(br.y / cs.y))
	return Rect2i(top_left, bottom_right - top_left)

func _cost_to_color(v: float, a: float) -> Color:
	# 0 → 파랑, 중간 → 노랑, 높음 → 빨강
	var t: float = clamp(v / 100.0, 0.0, 1.0)
	if t < 0.5:
		var k := t * 2.0
		return Color(0.0 + k, 0.0 + k, 1.0 - k, a)
	else:
		var k2 := (t - 0.5) * 2.0
		return Color(1.0, 1.0 - k2, 0.0, a)
