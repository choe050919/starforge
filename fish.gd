extends Node2D
class_name Fish

const EDGE_AVOID_K := 0.5
const RANDOM_SKIP_RATIO := 0.3

# 8-neighborhood (no (0,0)), y+ is down in Godot
const EIGHT_DIRS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                    Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

var tick_mod := 4

## 현재 좌표
var cell: Vector2i
var update_phase := 0
var stuck_count := 0
var rng := RandomNumberGenerator.new()

# 의존성
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

func _ready():
	rng.randomize()
	update_phase = rng.randi_range(0, tick_mod - 1)

# 5번씩 이동하는 이유: int(sim_time)이, 같은 값을 5번씩 출력해서.
func _on_sim_tick(dt: float, sim_time: float):
	if int(sim_time) % tick_mod != update_phase:
		return

	if not is_water(cell):
		return  # 물이 아니면 이동 비활성화

	var moved := attempt_move()
	if moved:
		stuck_count = 0
	else:
		stuck_count += 1
		if stuck_count >= 20:
			on_stuck()

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

## 셀 좌표를 입력하면 sid가 Water인지 여부를 반환한다.
func is_water(c: Vector2i) -> bool:
	return s_store.get_is_water(c)

## 셀 좌표를 입력하면, 주변 8타일 중 Water인 셀들의 좌표를 배열로 반환한다.
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

# 동일 셀 과일 수확만 시도(8방 탐색 X: 후속 단계)
func _try_harvest_current_cell() -> void:
	if _plant == null:
		return
	# 물 위 전용 제약 없음(디자인 상). Fish가 물 셀에만 존재하더라도 여기선 제약 두지 않음.
	var ok := _plant.try_harvest_fruit_at_cell(cell)
	if ok:
		on_eat_fruit()

# 수확 성공 시 Fish 내부 처리(포만/체력/로그 등). 지금은 간단히 훅만 둔다.
func on_eat_fruit() -> void:
	# TODO: 포만도/체력 시스템 연결 시 구현
	# print("[Fish] fruit eaten at ", cell)
	pass
