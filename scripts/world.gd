extends Node2D

@onready var terrain: Terrain = get_node("Terrain")
@onready var worldgen: WorldGen = get_node("Systems/WorldGen")

func _ready() -> void:
	if worldgen == null:
		push_error("[World] Systems/WorldGen 노드를 찾지 못했습니다."); return
	if terrain == null:
		push_error("[World] Terrain 노드를 찾지 못했습니다."); return

	worldgen.generated.connect(_on_world_generated)
	worldgen.generate()

func _on_world_generated(tiles: PackedInt32Array, size: Vector2i) -> void:
	terrain.apply_tiles(tiles, size)

	# 카메라 중앙으로
	if has_node("Camera2D") and terrain.ground != null and terrain.ground.tile_set != null:
		var ts: TileSet = terrain.ground.tile_set
		var map_px: Vector2 = Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		$Camera2D.position = map_px * 0.5
