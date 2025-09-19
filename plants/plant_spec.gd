## 식물 설계도: 단계별 footprint(셀 오프셋) + 스프라이트 키 + 성장속도
extends Resource
class_name PlantSpec

const Part = preload("res://plants/plant_part.gd")

@export var id: StringName
@export var base_growth_rate: float = 0.04  ## progress/sec. 1.0에 도달하면 다음 단계.

## 단계 정의(같은 인덱스로 정렬/동일 길이 유지)
@export var stage_names: PackedStringArray = ["seed", "sprout", "adult"]

## 각 스테이지의 로컬 오프셋 목록(셀 좌표).
## 중첩 익스포트는 Array[Array]까지만. 내부는 Vector2i로 '약속'하고 getter에서 정규화
@export var footprints: Array[Array] = [
	[Vector2i(0, 0)],                                  # seed
	[Vector2i(0, 0), Vector2i(0, -1)],                 # sprout
	[Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, -2)] # adult
]

# 각 stage의 footprint 길이와 동일한 태그 배열
@export var part_tags: Array[PackedInt32Array] = [
	PackedInt32Array([Part.PlantPart.ROOT]),                          # seed
	PackedInt32Array([Part.PlantPart.ROOT, Part.PlantPart.LEAF]),     # sprout
	PackedInt32Array([Part.PlantPart.ROOT, Part.PlantPart.LEAF, Part.PlantPart.FRUIT]) # adult
]

# 빛 요구/튜닝 필드 (기본값은 기존 동작을 최대한 보존)
@export var required_light_wm2: float = 0.0   # L_min: 이 값 이하면 성장률 0
@export var optimal_light_wm2: float = 1000.0 # L_opt: 이 값에서 성장률 100%
@export var fruit_light_coupled: bool = true  # true면 과일 성숙도도 빛 비례

@export var fruit_growth_rate: float = 0.02
@export var fruit_initial_maturity: float = 0.0

@export var sprite_keys: PackedStringArray = ["plant/amp/seed", "plant/amp/sprout", "plant/amp/adult"]

func stage_count() -> int:
	return stage_names.size()

# 항상 Array[Vector2i]로 정규화해서 반환 (에디터에서 Vector2로 들어와도 안전)
func get_footprint(stage_idx: int) -> Array[Vector2i]:
	if stage_idx < 0 or stage_idx >= footprints.size():
		return []
	var src: Array = footprints[stage_idx]
	var out: Array[Vector2i] = []
	out.resize(src.size())
	for i in src.size():
		out[i] = Vector2i(src[i])
	return out

func get_sprite_key(stage_idx: int) -> StringName:
	if stage_idx < 0 or stage_idx >= sprite_keys.size():
		return &""
	return StringName(sprite_keys[stage_idx])

func get_part_tags(stage_idx: int) -> PackedInt32Array:
	if stage_idx < 0 or stage_idx >= part_tags.size():
		return PackedInt32Array()
	return part_tags[stage_idx]

# 간단 검증
func validate_stage(stage_idx: int) -> void:
	var f := footprints[stage_idx]
	var t := part_tags[stage_idx]
	if f.size() != t.size():
		push_error("[PlantSpec] stage %d: footprints=%d, part_tags=%d 길이 불일치" % [stage_idx, f.size(), t.size()])
