## TileChange # (Refactored, no TileStore/EventQueue)
## - DataLayer에 직접 접근하여 타일을 동기 배치로 변경
## - Terrain 적용 & 시그널 발행만 담당
## - 최소 책임: 경계검사, 타일 타입 쓰기, 가시화 반영, 시그널
extends Node
class_name TileChange

signal tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName)
signal tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName)
signal cells_changed() # 필요 시 AABB/리스트로 확장, 아직 연결 X. TODO

# 외부 참조
@export_node_path("Node") var terrain_node_path: NodePath # Terrain 노드 경로
var _terrain: Terrain

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

func _ready() -> void:
	if terrain_node_path != NodePath():
		_terrain = get_node(terrain_node_path) as Terrain

func setup(data: DataLayer) -> void:
	_data = data
	_index = _data.index
	_size = _index.size
	if _terrain == null and terrain_node_path != NodePath():
		_terrain = get_node_or_null(terrain_node_path) as Terrain

## 편의: 단일 셀 교체
func replace_cell(cell: Vector2i, to_tile: int, reason: StringName = &"") -> void:
	apply_replacements([cell], to_tile, reason)

## 편의: 파괴(= VACUUM으로 교체)
func destroy_cell(cell: Vector2i, reason: StringName = &"destroy") -> void:
	_data.apply_cells_with_spec([cell], { "sid" : 0 }, reason)

## 핵심: 동기 배치 적용 (큐 없이)
func apply_replacements(cells: Array, to_tile: int, reason: StringName = &"") -> void:
	if _data == null or _size == Vector2i.ZERO:
		push_warning("[TileChange] setup() not ready.")
		return
	if cells.is_empty():
		return

	# 1) 경계 내 셀만 수집 + 중복 제거
	var unique: Array[Vector2i] = []
	var seen := {}
	for c in cells:
		var cell := Vector2i(c)
		if not _index.in_bounds_cell(cell):
			continue
		var key := _key(cell)
		if not seen.has(key):
			seen[key] = true
			unique.append(cell)
	if unique.is_empty():
		return

	# 2) 이전 값 조회
	var from_tiles: Array[int] = []
	from_tiles.resize(unique.size())
	for i in unique.size():
		from_tiles[i] = _get_tile_id(unique[i])

	# 3) 변경 필요 없는 셀 제거(from == to)
	var write_cells: Array[Vector2i] = []
	var write_from_tiles: Array[int] = []
	for i in unique.size():
		if from_tiles[i] == to_tile:
			continue
		write_cells.append(unique[i])
		write_from_tiles.append(from_tiles[i])

	if write_cells.is_empty():
		return

	# 시그널 발행, World로 연결
	for i in write_cells.size():
		var cell := write_cells[i]
		var from_tile := write_from_tiles[i]

		if _terrain != null:
			_terrain.apply_cell_change(cell, to_tile)

		if to_tile == TILE_VACUUM:
			emit_signal("tile_destroyed", cell, from_tile, reason)
		emit_signal("tile_replaced", cell, from_tile, to_tile, reason)

	emit_signal("cells_changed")

# ── 내부 유틸 ────────────────────────────────────────────────────────────────
static func _key(cell: Vector2i) -> int:
	return (cell.y << 16) | (cell.x & 0xFFFF)

# 아래 4개 메서드는 DataLayer의 실제 TileType Store API에 맞춰 연결.
func _begin_tile_write() -> void:
	_data.substance.begin_write()

	if _data and _data.tile_types and _data.tile_types.has_method("begin_write"):
		_data.tile_types.begin_write()

func _commit_tile_write() -> void:
	if _data and _data.tile_types and _data.tile_types.has_method("end_write"):
		_data.tile_types.end_write()

func _get_tile_id(cell: Vector2i) -> int:
	return _data.substance.get_by_cell(cell)

func _set_tile(cell: Vector2i, tile_id: int) -> void:
	if _data and _data.tile_types and _data.tile_types.has_method("set_by_cell"):
		_data.tile_types.set_by_cell(cell, tile_id); return
	if _data and _data.tile_types and _data.tile_types.has_method("set_by_index"):
		_data.tile_types.set_by_index(_index.idx(cell), tile_id); return
	push_warning("[TileChange] _set_tile: tile_types API not found. Write skipped.")
