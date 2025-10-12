extends Node2D
class_name Fish

signal died(fish_id: int, world_pos: Vector2, reason: StringName)

const EDGE_AVOID_K := 0.5
const RANDOM_SKIP_RATIO := 0.3

# 8-neighborhood (no (0,0)), y+ is down in Godot
const EIGHT_DIRS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                    Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

@export var tick_mod := 4

## 위치·상태
var cell: Vector2i
var update_phase := 0
var stuck_count := 0
var rng := RandomNumberGenerator.new()

# ── 의존성 ───────────────────────────────────────────────────────────
var _data: DataLayer
var index: GridIndex
var s_store: SubstanceStore
var _ground: Ground
var _plant: Plant

func setup(data: DataLayer, ground: Ground, plant: Plant) -> void:
	_data = data
	index = _data.index
	s_store = _data.substance
	_ground = ground
	_plant = plant

# ── 생애 주기 ────────────────────────────────────────────────────────
@export var fish_id: int = 0
@export var lifespan_sec := 600.0
@export var lifespan_jitter_sec := 120.0
var age_sec := 0.0
var _lifespan_target_sec := 0.0

@export var fish_corpse_scene: PackedScene
@export var corpse_mass_g := 120.0
@export var corpse_nutrition_j := 5000.0

func _ready():
	rng.randomize()
	update_phase = rng.randi_range(0, max(1, tick_mod) - 1)
	var jitter := rng.randf_range(-lifespan_jitter_sec, lifespan_jitter_sec)
	_lifespan_target_sec = max(1.0, lifespan_sec + jitter)

# ── 시뮬 틱 진입 ────────────────────────────────────────────────────
func _on_sim_tick(dt: float, sim_time: float):
	_last_sim_time = sim_time
	if eligible_at_simtime < 0.0:
		eligible_at_simtime = sim_time + reproduction_cooldown_sec

	# 나이 증가 및 사망 판정
	age_sec += dt
	if age_sec >= _lifespan_target_sec:
		_die("lifespan")
		return

	# 이동 주기 제어
	if int(sim_time) % tick_mod != update_phase:
		return
	if not is_water(cell):
		return

	var moved := attempt_move()
	if moved:
		stuck_count = 0
	else:
		stuck_count += 1
		if stuck_count >= 20:
			on_stuck()

# ── 이동 로직 ───────────────────────────────────────────────────────
func attempt_move() -> bool:
	var water_cells := get_adjacent_water_cells(cell)
	if water_cells.is_empty():
		return false

	var use_weight := rng.randf() > RANDOM_SKIP_RATIO
	var target_cell: Vector2i
	if use_weight:
		var weights := []
		for c in water_cells:
			var nearby := get_adjacent_water_count(c)
			weights.append(1.0 + EDGE_AVOID_K * nearby)
		target_cell = weighted_random(water_cells, weights)
	else:
		target_cell = water_cells[rng.randi_range(0, water_cells.size() - 1)]

	if target_cell == cell:
		return false

	move_to_cell(target_cell)
	return true

func is_water(c: Vector2i) -> bool:
	return s_store.get_is_water(c)

func get_adjacent_water_cells(c: Vector2i) -> Array:
	var result := []
	for dir in EIGHT_DIRS:
		var nc := c + dir
		if is_water(nc):
			result.append(nc)
	return result

func get_adjacent_water_count(c: Vector2i) -> int:
	var count := 0
	for dir in EIGHT_DIRS:
		if is_water(c + dir):
			count += 1
	return count

func weighted_random(cells: Array, weights: Array) -> Vector2i:
	var sum := 0.0
	for w in weights:
		sum += w
	var r := rng.randf() * sum
	var acc := 0.0
	for i in range(cells.size()):
		acc += weights[i]
		if r <= acc:
			return cells[i]
	return cells[0]

func move_to_cell(new_cell: Vector2i):
	warp_to_cell(new_cell)
	_try_harvest_current_cell()

func on_stuck():
	# 20회 연속 못 움직이면 호출될 추가 기능
	pass

func warp_to_cell(_cell: Vector2i) -> void:
	if _ground == null:
		return
	var local_origin: Vector2 = _ground.map_to_local(_cell)
	var ts: TileSet = _ground.tile_set
	var half: Vector2 = Vector2(ts.tile_size.x * 0.5, ts.tile_size.y * 0.5)
	global_position = _ground.to_global(local_origin + half)
	cell = _cell

# ── 섭식/번식 ───────────────────────────────────────────────────────
func _try_harvest_current_cell() -> void:
	if _plant == null:
		return
	if _last_sim_time < eligible_at_simtime:
		return
	var ok := _plant.try_harvest_fruit_at_cell(cell)
	if ok:
		on_eat_fruit()

func on_eat_fruit() -> void:
	if _spawn_fish_cb.is_valid():
		_spawn_fish_cb.call(cell)

@export var reproduction_cooldown_sec: float = 5.0
var eligible_at_simtime: float = -1.0
var _last_sim_time: float = 0.0
var _spawn_fish_cb: Callable = Callable()

func set_spawn_fish_callable(cb: Callable) -> void:
	_spawn_fish_cb = cb

# ── 사망 처리 ───────────────────────────────────────────────────────
func _die(reason: StringName) -> void:
	emit_signal("died", fish_id, global_position, reason)
	_spawn_corpse()
	queue_free()

func _spawn_corpse() -> void:
	if fish_corpse_scene == null:
		return
	var corpse := fish_corpse_scene.instantiate()
	if corpse == null:
		return
	if corpse.has_method("set_stats"):
		corpse.call("set_stats", corpse_mass_g, corpse_nutrition_j)
	elif "mass_g" in corpse and "nutrition_j" in corpse:
		corpse.mass_g = corpse_mass_g
		corpse.nutrition_j = corpse_nutrition_j
	corpse.global_position = global_position

	var parent := _resolve_corpse_parent()
	parent.add_child(corpse)

func _resolve_corpse_parent() -> Node:
	var tree := get_tree()

	# 1) 그룹으로 Actors 찾기
	var actors := tree.get_first_node_in_group("actors_root")
	if actors == null:
		if not tree.has_meta("actors_root_missing_warned"):
			tree.set_meta("actors_root_missing_warned", true)
			push_warning("[Fish] Group 'actors_root' not found. Falling back to local parent for corpses.")
		return get_parent()

	# 2) Actors/Corpses 사용 또는 생성
	var cc := actors.get_node_or_null("Corpses")
	if cc:
		return cc

	var new_cc := Node.new()
	new_cc.name = "Corpses"
	actors.add_child(new_cc)

	if not tree.has_meta("corpses_autocreated_info"):
		tree.set_meta("corpses_autocreated_info", true)
		print("[Fish] Created 'Actors/Corpses' container at runtime.")

	return new_cc
