## 식물 설계도: 단계별 footprint(셀 오프셋) + 스프라이트 키 + 성장속도
extends Resource
class_name PlantSpec

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
