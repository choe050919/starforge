extends TileMapLayer
class_name Ground

# 현재 프로젝트의 타일 매핑 (인스펙터에서 조정 가능)
@export var sid: int = 2

@export var atlas_ice: Vector2i = Vector2i(0, 0)
@export var alt_ice: int = 0

@export var atlas_ground: Vector2i = Vector2i(1, 0)
@export var alt_ground: int = 0

@export var atlas_uranium: Vector2i = Vector2i(2, 0)
@export var alt_uranium: int = 0

@export var atlas_copper: Vector2i = Vector2i(4, 0)
@export var alt_copper: int = 0

const TILE_VACCUM: int = 0
const TILE_ICE: int = 10001
const TILE_GROUND: int = 10002
const TILE_URANIUM: int = 10003
const TILE_COPPER: int = 10004

## tile들의 Array를 받아서 적용한다.
func apply_tiles(tile_types: PackedInt32Array, size: Vector2i) -> void:
	if tile_set == null:
		push_error("[Ground.apply_tiles] Ground/TileSet missing."); return

	clear()

	for y in size.y:
		for x in size.x:
			var idx:int = y * size.x + x
			var t:int = tile_types[idx]
			if t == TILE_GROUND:
				set_cell(Vector2i(x, y), sid, atlas_ground, alt_ground)
			elif t == TILE_ICE:
				set_cell(Vector2i(x, y), sid, atlas_ice, alt_ice)
			elif t == TILE_URANIUM:
				set_cell(Vector2i(x, y), sid, atlas_uranium, alt_uranium)
			elif t == TILE_COPPER:
				set_cell(Vector2i(x, y), sid, atlas_copper, alt_copper)
			else:
				pass # 공기는 비워두기

## cell 좌표를 받아서 적용한다.
func apply_cell_change(cell: Vector2i, tile_type: int) -> void:
	match tile_type:
		TILE_GROUND:
			set_cell(cell, sid, atlas_ground, alt_ground)
		TILE_ICE:
			set_cell(cell, sid, atlas_ice, alt_ice)
		TILE_URANIUM:
			set_cell(cell, sid, atlas_uranium, alt_uranium)
		_:
			# VACCUM 또는 미정의 → 지우기
			erase_cell(cell)
