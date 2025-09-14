## "표현 전용" 베이스. 규칙/점유 계산은 PlantLayer가 담당.
## 여기서는 스프라이트 교체/애니메이션 등만 처리.
extends Node2D
class_name PlantBase


@onready var _sprite: Sprite2D = _ensure_sprite()

var plant_id: int
var spec_id: StringName
var root_cell: Vector2i
var stage_idx: int:
	set(value):
		stage_idx = value
		apply_stage(value)

func setup_from_layer(id: int, _spec_id: StringName, _root: Vector2i, _stage: int) -> void:
	plant_id = id
	spec_id = _spec_id
	root_cell = _root
	stage_idx = _stage
	apply_stage(stage_idx)

func set_stage(v: int) -> void:
	stage_idx = v
	apply_stage(v)

func apply_stage(idx: int) -> void:
	## 실제 프로젝트에선 VisualDB/Theme에서 텍스처를 꺼내와 바인딩하세요.
	## MVP에선 간단히 크기/모듈레이션으로 단계 차이만 표현.
	match idx:
		0:
			_sprite.scale = Vector2(0.6, 0.6)
			_sprite.modulate = Color(0.8, 1.0, 0.8)
		1:
			_sprite.scale = Vector2(0.8, 0.8)
			_sprite.modulate = Color(0.7, 1.0, 0.7)
		_:
			_sprite.scale = Vector2(1.0, 1.0)
			_sprite.modulate = Color(0.6, 1.0, 0.6)

func _ensure_sprite() -> Sprite2D:
	if has_node("Sprite2D"):
		return $Sprite2D
	var s := Sprite2D.new()
	add_child(s)
	## 플레이스홀더 사각형 텍스처(없으면 그냥 빈 스프라이트도 OK)
	## 여기선 텍스처 없이 색상만으로 구분.
	return s
