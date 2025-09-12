## TileChange
## - DataLayer에 직접 접근하여 타일을 동기 배치로 변경
## - Terrain 적용 & 시그널 발행만 담당
## - 최소 책임: 경계검사, 타일 타입 쓰기, 가시화 반영, 시그널
extends Node
class_name TileChange

signal tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName)
signal tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName)
signal cells_changed() # 필요 시 AABB/리스트로 확장, 아직 연결 X. TODO

var _data: DataLayer
var _index: GridIndex
var _size: Vector2i = Vector2i.ZERO

# ── 타일/물질 ID 매핑 ────────────────────────────────────────────────────────
# JSON 스키마 기준
const TILE_ICE:     int = 10001
const TILE_SOIL:    int = 10002
const TILE_URANIUM: int = 10003
const TILE_COPPER:  int = 10004
const TILE_WATER:   int = 20001
const TILE_STEAM:   int = 30001
const TILE_VACUUM:  int = 0


func setup(data: DataLayer) -> void:
	_data = data
	_index = _data.index
	_size = _index.size

## 편의: 단일 셀 교체
func replace_cell(cell: Vector2i, to_tile: int, reason: StringName = &"") -> void:
	# TODO to_tile을 적용할 필요.
	_data.apply_cells_with_spec([cell], { "sid" : 0 }, reason)

## 편의: 파괴(= VACUUM으로 교체)
func destroy_cell(cell: Vector2i, reason: StringName = &"destroy") -> void:
	_data.set_cell_with_spec(cell, { "sid" : 0 , "phase" : 0 , "mass" : 0 , "temp" : 0 }, reason)
	#_data.apply_cells_with_spec([cell], { "sid" : 0 }, reason)

# ── 내부 유틸 ────────────────────────────────────────────────────────────────
static func _key(cell: Vector2i) -> int:
	return (cell.y << 16) | (cell.x & 0xFFFF)
