extends Node2D
class_name Terrain

@onready var ground: TileMapLayer = get_node("Ground")

# 현재 프로젝트의 타일 매핑 (인스펙터에서 조정 가능)
@export var sid_ground: int = 3
@export var atlas_ground: Vector2i = Vector2i(1, 0)
@export var alt_ground: int = 0

@export var sid_ice: int = 3
@export var atlas_ice: Vector2i = Vector2i(0, 0)
@export var alt_ice: int = 0

const TILE_AIR: int = 0
const TILE_ICE: int = 1
const TILE_GROUND: int = 2

func apply_tiles(tile_types: PackedInt32Array, size: Vector2i) -> void:
	if ground == null or ground.tile_set == null:
		push_error("[Terrain] Ground/TileSet missing."); return

	ground.clear()

	for y in size.y:
		for x in size.x:
			var idx:int = y * size.x + x
			var t:int = tile_types[idx]
			if t == TILE_GROUND:
				ground.set_cell(Vector2i(x, y), sid_ground, atlas_ground, alt_ground)
			elif t == TILE_ICE:
				ground.set_cell(Vector2i(x, y), sid_ice, atlas_ice, alt_ice)
			else:
				# 공기는 비워두기
				pass
