## "표현 전용" 베이스. 규칙/점유 계산은 PlantLayer가 담당.
## 여기서는 스프라이트 교체/애니메이션 등만 처리.
extends Node2D
class_name PlantBase

#@onready var _sprite: Sprite2D

var plant_id: int
var spec_id: StringName
var root_cell: Vector2i
var stage_idx: int = 0

var _cell_size := Vector2i(32, 32)
var _sprites: Array[Sprite2D] = []
var _ph_tex: Texture2D = null  # placeholder 캐시

func _ready() -> void:
	#_ensure_sprite_ready()
	pass

func setup_from_layer(id: int, _spec_id: StringName, _root: Vector2i, _stage: int) -> void:
	plant_id = id
	spec_id = _spec_id
	root_cell = _root
	stage_idx = _stage

func set_stage(v: int) -> void:
	stage_idx = v
	_apply_style_to_all()

func _placeholder_tex() -> Texture2D:
	if _ph_tex: return _ph_tex
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))  # 흰색 작은 정사각형
	var tex := ImageTexture.create_from_image(img)
	_ph_tex = tex
	return _ph_tex

## 핵심: 스테이지 + 셀 목록 + 셀 스케일을 받아 footprint 전부 표현
func set_stage_and_cells(v: int, cells: Array[Vector2i], cell_world_scale: Vector2) -> void:
	stage_idx = v
	_cell_size = cell_world_scale
	_sync_cells(cells)
	_apply_style_to_all()

func _sync_cells(cells: Array[Vector2i]) -> void:
	# 루트 노드 자체는 root_cell 타일의 좌상단(또는 원점)에 둘 필요 없음.
	# 각 자식 스프라이트를 (cell - root_cell) * cell_size 만큼 상대 배치.
	var need := cells.size()

	# 개수 맞추기
	while _sprites.size() < need:
		var s := Sprite2D.new()
		s.texture = _placeholder_tex()
		s.centered = false
		s.offset = Vector2(16,16)
		add_child(s)
		_sprites.append(s)
	while _sprites.size() > need:
		var last: Sprite2D = _sprites.pop_back()
		if is_instance_valid(last):
			last.queue_free()

	# 위치 갱신
	for i in need:
		var s := _sprites[i]
		var rel := cells[i] - root_cell
		s.position = Vector2i(rel) * _cell_size

func _apply_style_to_all() -> void:
	var scale_v := Vector2.ONE
	var tint := Color(1, 1, 1)

	match stage_idx:
		0:
			scale_v = Vector2(0.6, 0.6)
			tint = Color(0.8, 1.0, 0.8)
		1:
			scale_v = Vector2(0.8, 0.8)
			tint = Color(0.7, 1.0, 0.7)
		_:
			scale_v = Vector2(1.0, 1.0)
			tint = Color(0.6, 1.0, 0.6)

	for s in _sprites:
		s.scale = scale_v
		s.modulate = tint
