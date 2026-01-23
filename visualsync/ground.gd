class_name Ground
extends TileMapLayer

# ── Constants ────────────────────────────────────────────────────────

enum Tile {
	VACUUM = 0,
	ICE = 10001,
	GROUND = 10002,
	URANIUM = 10003,
	COPPER = 10004,
	MEAT = 10005,
	GRAIN = 10006,
	BERRY = 10007,
}

# ── Export ───────────────────────────────────────────────────────────

# 현재 프로젝트의 타일 매핑
@export var sid: int = 0

@export_group("Placeholder")
@export var atlas_placeholder := Vector2i(4, 1)
@export var alt_placeholder := 0

@export_group("Tile Atlas")
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

# ── Lifecycle ────────────────────────────────────────────────────────

func _ready() -> void:
	if tile_set == null:
		Debug.error(self, "TileSet missing."); return

# ── API ──────────────────────────────────────────────────────────────

## tile들의 Array를 받아서 적용한다.
## 전체 맵 초기화 용도로 사용.
func apply_tiles(tile_types: PackedInt32Array, size: Vector2i) -> void:
	clear()
	for y in size.y:
		for x in size.x:
			var idx := y * size.x + x
			var tile_type := tile_types[idx]
			if tile_type == Tile.VACUUM:
				continue
			_set_tile(Vector2i(x, y), tile_type)

## cell 좌표를 받아서 적용한다.
func apply_cell_change(cell: Vector2i, tile_type: int) -> void:
	if tile_type == Tile.VACUUM:
		erase_cell(cell)
		return
	_set_tile(cell, tile_type)

# ── Internal ─────────────────────────────────────────────────────────

const _NO_TILE := []

func _set_tile(cell: Vector2i, tile_type: int) -> void:
	var tile_data := _map_tile_to_atlas(tile_type)
	if tile_data.is_empty():
		set_cell(cell, sid, atlas_placeholder, alt_placeholder)
	else:
		set_cell(cell, sid, tile_data[0], tile_data[1])

## 타일 타입을 atlas와 alt 값으로 매핑한다.
## 반환값: [atlas: Vector2i, alt: int] 또는 빈 배열 (VACCUM/미정의 타일)
func _map_tile_to_atlas(tile_type: int) -> Array:
	match tile_type:
		Tile.GROUND:
			return [atlas_ground, alt_ground]
		Tile.ICE:
			return [atlas_ice, alt_ice]
		Tile.URANIUM:
			return [atlas_uranium, alt_uranium]
		Tile.COPPER:
			return [atlas_copper, alt_copper]
		Tile.GRAIN:
			return [atlas_grain, alt_grain]
		Tile.BERRY:
			return [atlas_berry, alt_berry]
		_:
			return _NO_TILE
