## "표현 전용" 베이스. 규칙/점유 계산은 Plant가 담당.
## 여기서는 스프라이트 교체/애니메이션 등만 처리.
extends Node2D
class_name PlantView

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

# FRUIT 비트(PlantPart.FRUIT). View는 규칙을 모르는 "표현 전용"이라
# 외부 enum 의존을 피하려고 여기서 상수로만 씀. (1<<3 과 스펙의 FRUIT가 동일해야 함)
const _FRUIT_BIT := 1 << 3

# 내부 캐시(선택): 최근 전달값을 보관해 후속 갱신에서 참조 가능
var _tags_base_cache: PackedInt32Array
var _fruit_present_cache: PackedByteArray
var _fruit_maturity_cache: PackedFloat32Array

# 역할 태그와 열매 상태를 받아 셀별 비주얼을 갱신한다.
# - tags_base[i] : 정적 역할 태그 비트셋 (FRUIT 여부 판정)
# - fruit_present[i] : 0/1 (수확 등으로 열매 존재 여부)
# - fruit_maturity[i] : 0.0~1.0 (성숙도), 비-FRUIT 셀은 -1.0 센티널
func set_part_tags_and_fruit(
	tags_base: PackedInt32Array,
	fruit_present: PackedByteArray,
	fruit_maturity: PackedFloat32Array
) -> void:
	# 방어: 길이 불일치 시 안전 탈출(개발 중 경고)
	var n := _sprites.size()
	if tags_base.size() != n or fruit_present.size() != n or fruit_maturity.size() != n:
		push_warning("[PlantView] set_part_tags_and_fruit: size mismatch sprites=%d tags=%d present=%d maturity=%d"
			% [n, tags_base.size(), fruit_present.size(), fruit_maturity.size()])
		return

	# 캐시(선택)
	_tags_base_cache = tags_base.duplicate()
	_fruit_present_cache = fruit_present.duplicate()
	_fruit_maturity_cache = fruit_maturity.duplicate()

	# 우선 스테이지 공통 스타일을 반영(크기/기본 틴트)
	_apply_style_to_all()

	# 셀별로 과일 표현 레이어를 얹는다.
	for i in n:
		var s: Sprite2D = _sprites[i]
		var is_fruit := (int(tags_base[i]) & _FRUIT_BIT) != 0

		if not is_fruit:
			# FRUIT가 아닌 셀은 스테이지 공통 스타일만 유지
			# 필요시: 잎/줄기/뿌리별 색 분기도 가능(여기선 최소 구현)
			continue

		# FRUIT 셀: 존재/성숙도에 따라 비주얼 변조
		var present := fruit_present[i] == 1
		var m := fruit_maturity[i]

		if not present:
			# 수확되어 열매가 없음 → 살짝 투명/탈색
			s.modulate.a = 0.35
			# 크기를 소폭 축소하여 ‘없음’ 느낌을 추가로 부여(선택)
			s.scale = s.scale * 0.9
			continue

		# 열매가 존재함: 성숙도 기반 색/스케일 연출 (0.0=초록 → 1.0=노란빛)
		var t: float = clamp(m, 0.0, 1.0)
		var unripe := Color(0.55, 0.85, 0.55) # 덜 익음(초록 기)
		var ripe   := Color(1.0, 0.388, 0.278, 1.0) # 잘 익음, CSS 색상 "tomato"
		var c := _lerp_color(unripe, ripe, t)

		# 스테이지 공통 틴트 위에 곱해지므로, 살짝 강조하려고 알파는 유지
		var base := s.modulate
		s.modulate = Color(base.r * c.r, base.g * c.g, base.b * c.b, base.a)

		# 성숙도에 따라 약간 크게(익을수록 통통해 보이도록)
		var base_scale := s.scale
		var bump: float = 1.0 + (0.08 * t)  # +0% ~ +8%
		s.scale = Vector2(base_scale.x * bump, base_scale.y * bump)

		# (선택) 히트박스/툴팁용 메타데이터 부여
		s.set_meta("local_index", i)
		s.set_meta("is_fruit", true)
		s.set_meta("maturity", t)
		s.set_meta("present", present)

# 간단한 색 보간 헬퍼(HSV가 더 자연스럽지만, 최소 구현으로 RGB lerp)
func _lerp_color(a: Color, b: Color, t: float) -> Color:
	var k: float = clamp(t, 0.0, 1.0)
	return Color(
		a.r + (b.r - a.r) * k,
		a.g + (b.g - a.g) * k,
		a.b + (b.b - a.b) * k,
		a.a + (b.a - a.a) * k
	)

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
