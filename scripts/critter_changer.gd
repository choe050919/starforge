extends Node2D
class_name CritterChanger

@export_node_path("Node") var tile_change_path: NodePath  # TileChange
@export_node_path("TileMapLayer") var ground_layer_path: NodePath  # Terrain/Ground

@export var scan_radius: int = 6          # 주변 몇 칸에서 찾을지
@export var think_interval: float = 0.6   # 몇 초마다 한 번 시도할지
@export var destroy_ratio: float = 1.0    # 1.0이면 파괴만, 향후 다른 치환에 응용 가능

var _t: float = 0.0
var _sys: TileChange
var _ground: TileMapLayer
var _rng := RandomNumberGenerator.new()

const TILE_AIR: int = 0

func _ready() -> void:
	_rng.randomize()
	if tile_change_path != NodePath():
		_sys = get_node(tile_change_path) as TileChange
	if ground_layer_path != NodePath():
		_ground = get_node(ground_layer_path) as TileMapLayer

func _process(dt: float) -> void:
	_t += dt
	if _t >= think_interval:
		_t = 0.0
		_try_change_random_cell()

func _try_change_random_cell() -> void:
	if _sys == null or _ground == null:
		return

	# 현재 위치 기준 중심 셀
	var center_cell: Vector2i = _world_to_cell(global_position)
	var tiles := _sys.get_tiles()
	var size: Vector2i = _sys.size

	# 여러 번 시도해서 고체 셀 하나 찾기
	var attempts: int = 20
	while attempts > 0:
		attempts -= 1
		var dx: int = _rng.randi_range(-scan_radius, scan_radius)
		var dy: int = _rng.randi_range(-scan_radius, scan_radius)
		var cell := Vector2i(center_cell.x + dx, center_cell.y + dy)

		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue

		var idx: int = cell.y * size.x + cell.x
		if tiles.is_empty():
			return

		var current: int = tiles[idx]
		if current == TILE_AIR:
			continue  # 공기는 패스(이미 비어 있음)

		# 지금은 단순 파괴만 시행(AIR로)
		_sys.queue_destroy(cell, &"critter")
		break

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	# 월드→로컬→맵 좌표
	var local: Vector2 = _ground.to_local(world_pos)
	return _ground.local_to_map(local)

func set_dependencies(sys: TileChange, ground: TileMapLayer) -> void:
	_sys = sys
	_ground = ground

func warp_to_cell(cell: Vector2i) -> void:
	if _ground == null:
		return
	var local_origin: Vector2 = _ground.map_to_local(cell)
	var ts: TileSet = _ground.tile_set
	var half: Vector2 = Vector2(ts.tile_size.x * 0.5, ts.tile_size.y * 0.5)
	global_position = _ground.to_global(local_origin + half)
