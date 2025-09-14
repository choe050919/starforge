extends Resource
class_name PlantSpec

## 식물 종류의 "설계도".
## - 단계별 footprint(로컬 오프셋), 비주얼 키, 기본 성장속도 포함.

@export var id: StringName
@export var base_growth_rate: float = 0.04  ## progress/sec. 1.0에 도달하면 다음 단계.

## 단계 정의(같은 인덱스로 정렬/동일 길이 유지)
@export var stage_names: PackedStringArray = ["seed", "sprout", "adult"]
@export var footprints: Array[PackedVector2Array] = [PackedVector2Array([Vector2i(0,0)]), PackedVector2Array([Vector2i(0,0)]), PackedVector2Array([Vector2i(0,0), Vector2i(0,-1), Vector2i(1,-1)])]
@export var sprite_keys: PackedStringArray = ["plant/amp/seed", "plant/amp/sprout", "plant/amp/adult"]

func stage_count() -> int:
	return stage_names.size()

func get_footprint(stage_idx: int) -> PackedVector2Array:
	if stage_idx < 0 or stage_idx >= footprints.size():
		return PackedVector2Array()
	return footprints[stage_idx]

func get_sprite_key(stage_idx: int) -> StringName:
	if stage_idx < 0 or stage_idx >= sprite_keys.size():
		return &""
	return StringName(sprite_keys[stage_idx])
