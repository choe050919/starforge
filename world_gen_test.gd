extends Node2D

@export var world_gen_path: NodePath

var world_gen: WorldGen

func _ready() -> void:
	world_gen = get_node(world_gen_path)
	world_gen.generated.connect(_on_world_generated)
	world_gen.generate()

## [signal WorldGen.generated] 신호 핸들러.
## 생성된 데이터를 받아 월드 상태를 구성하고 시뮬레이션을 시작한다.
func _on_world_generated(
		size: Vector2i,
		substances: PackedInt32Array,
		phases: PackedByteArray,
		mass: PackedInt64Array,
		temperatures: PackedInt32Array,
		tiles: PackedInt32Array,
		springs: PackedVector2Array
) -> void:
	pass
