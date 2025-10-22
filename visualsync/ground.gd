extends TileMapLayer
class_name Ground

# 현재 프로젝트의 타일 매핑 (인스펙터에서 조정 가능)
@export var sid: int = 1

@export var atlas_ice: Vector2i = Vector2i(0, 0)
@export var alt_ice: int = 0

@export var atlas_ground: Vector2i = Vector2i(1, 0)
@export var alt_ground: int = 0

@export var atlas_uranium: Vector2i = Vector2i(2, 0)
@export var alt_uranium: int = 0

@export var atlas_copper: Vector2i = Vector2i(4, 0)
@export var alt_copper: int = 0

@export var atlas_grain: Vector2i = Vector2i(0, 1)
@export var alt_grain: int = 0

@export var atlas_berry: Vector2i = Vector2i(1, 1)
@export var alt_berry: int = 0

const TILE_VACCUM: int = 0
const TILE_ICE: int = 10001
const TILE_GROUND: int = 10002
const TILE_URANIUM: int = 10003
const TILE_COPPER: int = 10004
const TILE_MEAT: int = 10005
const TILE_GRAIN: int = 10006
const TILE_BERRY: int = 10007

func _ready() -> void:
	if tile_set == null:
		push_error("[Ground] Ground/TileSet missing."); return

# API

## tile들의 Array를 받아서 적용한다.
## 전체 맵 초기화 용도로 사용.
func apply_tiles(tile_types: PackedInt32Array, size: Vector2i) -> void:
	clear()

	for y in size.y:
		for x in size.x:
			var idx := y * size.x + x
			var tile_type := tile_types[idx]
			var tile_data := _map_tile_to_atlas(tile_type)
			
			if tile_data.is_empty():
				continue # VACCUM or not defined in tileset
			
			set_cell(Vector2i(x, y), sid, tile_data[0], tile_data[1])

## cell 좌표를 받아서 적용한다.
func apply_cell_change(cell: Vector2i, tile_type: int) -> void:
	var tile_data := _map_tile_to_atlas(tile_type)

	if tile_data.is_empty():
		erase_cell(cell) # VACCUM or not defined in tileset
	else:
		set_cell(cell, sid, tile_data[0], tile_data[1])

# 내부 헬퍼

## 타일 타입을 atlas와 alt 값으로 매핑한다.
## 반환값: [atlas: Vector2i, alt: int] 또는 빈 배열 (VACCUM/미정의 타일)
func _map_tile_to_atlas(tile_type: int) -> Array:
	match tile_type:
		TILE_GROUND:
			return [atlas_ground, alt_ground]
		TILE_ICE:
			return [atlas_ice, alt_ice]
		TILE_URANIUM:
			return [atlas_uranium, alt_uranium]
		TILE_COPPER:
			return [atlas_copper, alt_copper]
		TILE_GRAIN:
			return [atlas_grain, alt_grain]
		TILE_BERRY:
			return [atlas_berry, alt_berry]
		_:
			return []
