extends Node2D
class_name CritterBreaker

@export_node_path("Node") var durability_path: NodePath	 # Durability
@export_node_path("TileMapLayer") var ground_layer_path: NodePath  # Terrain/Ground

@export var scan_radius: int = 6		  # 주변 몇 칸에서 찾을지
@export var think_interval: float = 0.6	  # 몇 초마다 한 번 타겟 갱신
@export var break_power: float = 5.0	  # 초당 피해량

var _t: float = 0.0
var _durability: Durability
var _ground: TileMapLayer
var _rng := RandomNumberGenerator.new()
var _target: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	_rng.randomize()
	if durability_path != NodePath():
		_durability = get_node(durability_path) as Durability
	if ground_layer_path != NodePath():
		_ground = get_node(ground_layer_path) as TileMapLayer

func _process(dt: float) -> void:
	if _durability == null or _ground == null:
		return
	_t += dt
	if _target == Vector2i(-1, -1) or _durability.get_max_hp(_target) <= 0.0:
		_target = Vector2i(-1, -1)
	if _t >= think_interval and _target == Vector2i(-1, -1):
		_t = 0.0
		_target = _find_target_cell()
	if _target != Vector2i(-1, -1):
		_durability.apply_damage(_target, break_power * dt)

func _find_target_cell() -> Vector2i:
	var center: Vector2i = _world_to_cell(global_position)
	var attempts := 20
	var s := _durability.size
	while attempts > 0:
		attempts -= 1
		var dx: int = _rng.randi_range(-scan_radius, scan_radius)
		var dy: int = _rng.randi_range(-scan_radius, scan_radius)
		var cell := Vector2i(center.x + dx, center.y + dy)
		if cell.x < 0 or cell.y < 0 or cell.x >= s.x or cell.y >= s.y:
			continue
		if _durability.get_max_hp(cell) <= 0.0:
			continue
		return cell
	return Vector2i(-1, -1)

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = _ground.to_local(world_pos)
	return _ground.local_to_map(local)

func set_dependencies(dur: Durability, ground: TileMapLayer) -> void:
	_durability = dur
	_ground = ground

func warp_to_cell(cell: Vector2i) -> void:
	if _ground == null:
		return
	var local_origin: Vector2 = _ground.map_to_local(cell)
	var ts: TileSet = _ground.tile_set
	var half: Vector2 = Vector2(ts.tile_size.x * 0.5, ts.tile_size.y * 0.5)
	global_position = _ground.to_global(local_origin + half)
