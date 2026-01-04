## 채굴 큐 시각화: 대기 중인 채굴 대상 셀에 코너 브라켓 + 번호 표시
class_name MiningQueueVisual
extends Node2D

# ── 의존성 ───────────────────────────────────────────────────
@export var player_path: NodePath
@export var ground_path: NodePath

var _player: Player = null
var _ground: TileMapLayer = null

# ── 설정 ───────────────────────────────────────────────────
@export var include_current_target: bool = true  ## 현재 채굴 중인 타겟도 표시할지
@export var bracket_color: Color = Color(1.0, 0.5, 0.1, 0.9)  # 주황색 (reachable)
@export var bracket_color_unreachable: Color = Color(0.5, 0.3, 0.1, 0.6)  # 어두운 주황 (unreachable)
@export var bracket_bg_color: Color = Color.BLACK
@export var bracket_width_fg: float = 2.0
@export var bracket_width_bg: float = 4.0

@export var show_numbers: bool = true
@export var number_color: Color = Color.WHITE
@export var number_outline_color: Color = Color.BLACK
@export var font_size: int = 14

# ── 상태 ───────────────────────────────────────────────────
var _tile_px: Vector2 = Vector2(32, 32)
var _font: Font = null

# ── 생명주기 ───────────────────────────────────────────────────
func _ready() -> void:
	_bind_dependencies()
	_cache_tile_size()
	_font = ThemeDB.fallback_font

func _bind_dependencies() -> void:
	if player_path != NodePath() and has_node(player_path):
		_player = get_node(player_path)
	
	if ground_path != NodePath() and has_node(ground_path):
		_ground = get_node(ground_path)

func _cache_tile_size() -> void:
	if _ground and _ground.tile_set:
		_tile_px = Vector2(_ground.tile_set.tile_size)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _player == null:
		return
	
	var queue: Array[Vector2i] = _player.get_mining_queue()
	var reachable := _player.get_mining_reachable()
	
	if queue.is_empty():
		return
	
	# include_current_target에 따라 시작 인덱스 결정
	var start_idx := 0 if include_current_target else 1
	
	for i in range(start_idx, queue.size()):
		var cell := queue[i]
		var is_reachable := cell in reachable
		_draw_cell_highlight(cell, i + 1, is_reachable)

# ── 셀 하이라이트 ───────────────────────────────────────────
func _draw_cell_highlight(cell: Vector2i, number: int, is_reachable: bool) -> void:
	var color := bracket_color if is_reachable else bracket_color_unreachable
	var top_left := _cell_to_local(cell)
	var w := _tile_px.x
	var h := _tile_px.y
	var length := w * 0.25  # 브라켓 길이
	
	# 코너 브라켓 그리기
	# 좌상단 ┌
	_draw_bracket(top_left + Vector2.ZERO, Vector2(length, 0), Vector2(0, length), color)
	# 우상단 ┐
	_draw_bracket(top_left + Vector2(w, 0), Vector2(-length, 0), Vector2(0, length), color)
	# 좌하단 └
	_draw_bracket(top_left + Vector2(0, h), Vector2(length, 0), Vector2(0, -length), color)
	# 우하단 ┘
	_draw_bracket(top_left + Vector2(w, h), Vector2(-length, 0), Vector2(0, -length), color)
	
	# 번호 표시
	if show_numbers and _font:
		var text := str(number)
		var center := top_left + _tile_px * 0.5
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := center - text_size * 0.5 + Vector2(0, text_size.y * 0.35)
		
		# 외곽선 (8방향)
		for offset in [Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1),
					   Vector2(-1, 0),                Vector2(1, 0),
					   Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
			draw_string(_font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, number_outline_color)
		
		# 본문
		draw_string(_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, number_color)

func _draw_bracket(corner: Vector2, dir1: Vector2, dir2: Vector2, color: Color) -> void:
	draw_line(corner, corner + dir1, bracket_bg_color, bracket_width_bg, true)
	draw_line(corner, corner + dir2, bracket_bg_color, bracket_width_bg, true)
	draw_line(corner, corner + dir1, color, bracket_width_fg, true)
	draw_line(corner, corner + dir2, color, bracket_width_fg, true)

# ── 유틸 ───────────────────────────────────────────────────
func _cell_to_local(cell: Vector2i) -> Vector2:
	if _ground:
		var world_pos := _ground.to_global(_ground.map_to_local(cell)) - _tile_px * 0.5
		return to_local(world_pos)
	else:
		return Vector2(cell) * _tile_px
