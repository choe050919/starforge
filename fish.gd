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

@export var tick_mod := 4
@export var world: World

## 현재 좌표
var cell: Vector2i
var update_phase := 0
var stuck_count := 0
var rng := RandomNumberGenerator.new()
var sim_tick := 0

# 의존성
var _data: DataLayer
var index: GridIndex
var s_store: SubstanceStore

func setup(data: DataLayer):
	_data = data
	index = _data.index
	s_store = _data.substance

func _ready():
	rng.randomize()
	update_phase = rng.randi_range(0, tick_mod - 1)

func _on_sim_tick(dt: float):
	sim_tick += 1
	if sim_tick % tick_mod != update_phase:
		return

	print("dd")
	if not is_water(cell):
		return  # 물이 아니면 이동 비활성화

	print("ddd")
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
	cell = new_cell
	global_position = (cell)

func on_stuck():
	# 20회 연속 못 움직이면 호출될 추가 기능
	pass
