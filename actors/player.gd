extends Node2D
class_name Player

signal arrived_at_destination
signal inventory_changed(material_sid: int, mass_mg: int)  # 인벤토리 변경 신호

# ── 외부 참조 ───────────────────────────────────────────────────────
@export var grid_nav_path: NodePath
@export var overlay_path: NodePath
@export var mining_path: NodePath
@export var ground_item_registry_path: NodePath  # 추가

var _grid_nav: GridNav = null
var _overlay: Node = null
var _mining: Node = null
var _durability: DurabilityStore
var _ground_item_registry: GroundItemRegistry = null  # 추가

# ── 이동 튜닝 ───────────────────────────────────────────────────────
@export var move_speed: float = 180.0
@export var arrive_epsilon_px: float = 8.0
@export var show_path_preview: bool = true

# ── 재탐색 ──────────────────────────────────────────────────────────
@export var repath_interval_sec: float = 0.4
@export var repath_cooldown_sec: float = 0.2

var _time_since_repath := 0.0
var _repath_cooldown_left := 0.0

# ── 셀 판정 안정화 ──────────────────────────────────────────────────
@export var cell_hysteresis_px: float = 10.0

# ── 채굴 ────────────────────────────────────────────────────────────
@export var mining_reach_cells: int = 3
@export var mining_damage_per_sec: float = 5.0
@export var auto_move_to_mining_target: bool = true

var _mining_timer: float = 0.0
var _mining_interval_sec: float = 0.2
var _mining_queue: Array[Vector2i] = []

# ── 인벤토리 ────────────────────────────────────────────────────────
var _inventory_material_sid: int = -1        # -1 = 비어있음
var _inventory_mass_mg: int = 0              # mg 단위 (정수)
@export var inventory_max_capacity_mg: int = 100_000_000  # 100kg = 100,000,000mg
@export var pickup_reach_cells: int = 2      # 줍기 범위

# ── 내부 상태 ───────────────────────────────────────────────────────
enum Mode { IDLE, MOVING, MINING }
var _mode: int = Mode.IDLE

var _cell_px: Vector2 = Vector2(32, 32)
var _path: PackedVector2Array = []
var _path_index: int = 0
var _goal_cell: Vector2i = Vector2i(-9999, -9999)
var _last_start_cell: Vector2i = Vector2i(-9999, -9999)
var _mining_target_cell: Vector2i = Vector2i(-9999, -9999)

# ────────────────────────────────────────────────────────────────────
func setup(data: DataLayer) -> void:
	_durability = data.durability

func _ready() -> void:
	if grid_nav_path != NodePath() and has_node(grid_nav_path):
		_grid_nav = get_node(grid_nav_path)
		var cs: Vector2 = _grid_nav.get("cell_size")
		if cs is Vector2:
			_cell_px = cs
		
		if _grid_nav.has_signal("navigation_cell_changed"):
			_grid_nav.navigation_cell_changed.connect(_on_nav_changed)
		if _grid_nav.has_signal("navigation_bulk_changed"):
			_grid_nav.navigation_bulk_changed.connect(_on_nav_bulk_changed)
	
	if overlay_path != NodePath() and has_node(overlay_path):
		_overlay = get_node(overlay_path)
	
	if mining_path != NodePath() and has_node(mining_path):
		_mining = get_node(mining_path)
	
	# GroundItemRegistry 참조 획득
	if ground_item_registry_path != NodePath() and has_node(ground_item_registry_path):
		_ground_item_registry = get_node(ground_item_registry_path)
	
	call_deferred("_snap_start_to_surface")

func _physics_process(delta: float) -> void:
	_repath_cooldown_left = max(_repath_cooldown_left - delta, 0.0)
	
	match _mode:
		Mode.MOVING:
			_time_since_repath += delta
			
			if _time_since_repath >= repath_interval_sec and _repath_cooldown_left <= 0.0:
				_time_since_repath = 0.0
				_repath_to_goal()
			
			_move_along_path(delta)
		
		Mode.MINING:
			# 현재 타겟이 유효한지 확인
			if _mining_target_cell.x < -9998 or not _is_cell_valid_for_mining(_mining_target_cell):
				_advance_mining_queue()
				return
			
			# 거리 밖이면 자동 이동 또는 스킵
			if not _is_in_mining_range(_mining_target_cell):
				if auto_move_to_mining_target:
					move_to_cell(_mining_target_cell)
				else:
					_advance_mining_queue()
				return
			
			# 연속 채굴
			_mining_timer += delta
			if _mining_timer >= _mining_interval_sec:
				_mining_timer = 0.0
				_apply_mining_damage()
		
		Mode.IDLE:
			pass

# ════════════════════════════════════════════════════════════════════
# 인벤토리 API
# ════════════════════════════════════════════════════════════════════

## 지정된 셀에서 아이템 줍기
func pickup_item_at_cell(cell: Vector2i) -> bool:
	if _ground_item_registry == null:
		push_warning("[Player.pickup] GroundItemRegistry not assigned")
		return false
	
	# 범위 체크
	if not _is_in_pickup_range(cell):
		print("[Player.pickup] Out of range: cell=", cell)
		return false
	
	# 해당 셀의 스택 조회
	var stacks: Array = _ground_item_registry.get_stacks_in_cell(cell)
	if stacks.is_empty():
		print("[Player.pickup] No items at cell=", cell)
		return false
	
	# 첫 번째 스택만 줍기 (단순화)
	var stack: Dictionary = stacks[0]
	var sid: int = int(stack.get("material_sid", -1))
	var mass_kg: float = float(stack.get("mass_kg", 0.0))
	var temp_K: float = float(stack.get("temperature_K", 293.15))
	
	if sid < 0 or mass_kg <= 0.0:
		return false
	
	var mass_mg: int = _kg_to_mg(mass_kg)
	
	# 인벤토리가 비어있는 경우
	if _inventory_material_sid < 0:
		var take_mg: int = min(mass_mg, inventory_max_capacity_mg)
		_inventory_material_sid = sid
		_inventory_mass_mg = take_mg
		
		# 레지스트리에서 제거
		_ground_item_registry.remove_mass(cell, 0, _mg_to_kg(take_mg))
		
		print("[Player.pickup] Picked up: sid=", sid, " amount=", take_mg, "mg (", _mg_to_kg(take_mg), "kg)")
		inventory_changed.emit(_inventory_material_sid, _inventory_mass_mg)
		return true
	
	# 같은 재료인 경우 병합
	if _inventory_material_sid == sid:
		var capacity_left_mg: int = inventory_max_capacity_mg - _inventory_mass_mg
		if capacity_left_mg <= 0:
			print("[Player.pickup] Inventory full")
			return false
		
		var take_mg: int = min(mass_mg, capacity_left_mg)
		_inventory_mass_mg += take_mg
		
		# 레지스트리에서 제거
		_ground_item_registry.remove_mass(cell, 0, _mg_to_kg(take_mg))
		
		print("[Player.pickup] Merged: amount=", take_mg, "mg, total=", _inventory_mass_mg, "mg")
		inventory_changed.emit(_inventory_material_sid, _inventory_mass_mg)
		return true
	
	# 다른 재료인 경우 교체
	print("[Player.pickup] Different material - dropping current inventory first")
	drop_all_inventory()
	
	# 재귀 호출로 다시 줍기
	return pickup_item_at_cell(cell)

## 재료 소비 (건설 등에 사용)
func consume_material(amount_mg: int) -> bool:
	if _inventory_material_sid < 0:
		return false
	
	if _inventory_mass_mg < amount_mg:
		return false
	
	_inventory_mass_mg -= amount_mg
	
	# 다 써서 0이 되면 초기화
	if _inventory_mass_mg <= 0:
		_inventory_material_sid = -1
		_inventory_mass_mg = 0
	
	print("[Player.consume] Consumed: ", amount_mg, "mg, remaining=", _inventory_mass_mg, "mg")
	inventory_changed.emit(_inventory_material_sid, _inventory_mass_mg)
	return true

## 전부 버리기 (현재 위치에 드롭)
func drop_all_inventory() -> void:
	if _inventory_material_sid < 0 or _inventory_mass_mg <= 0:
		return
	
	if _ground_item_registry == null:
		push_warning("[Player.drop] GroundItemRegistry not assigned")
		return
	
	var current_cell := _world_to_cell(global_position)
	var mass_kg := _mg_to_kg(_inventory_mass_mg)
	
	# 임시 온도 (나중에 인벤토리에 온도도 저장할 수 있음)
	var temp_K: float = 293.15
	
	_ground_item_registry.add_or_merge(
		current_cell, 
		str(_inventory_material_sid), 
		mass_kg, 
		temp_K
	)
	
	print("[Player.drop] Dropped: sid=", _inventory_material_sid, " amount=", mass_kg, "kg at cell=", current_cell)
	
	# 인벤토리 초기화
	_inventory_material_sid = -1
	_inventory_mass_mg = 0
	inventory_changed.emit(_inventory_material_sid, _inventory_mass_mg)

## 건설 가능 여부 확인 (재료 & 양 체크)
func can_afford_material(sid: int, amount_mg: int) -> bool:
	if _inventory_material_sid != sid:
		return false
	return _inventory_mass_mg >= amount_mg

## UI용 Getter
func get_inventory_material_sid() -> int:
	return _inventory_material_sid

func get_inventory_mass_mg() -> int:
	return _inventory_mass_mg

func get_inventory_display_kg() -> float:
	return _mg_to_kg(_inventory_mass_mg)

func get_inventory_capacity_ratio() -> float:
	if inventory_max_capacity_mg <= 0:
		return 0.0
	return float(_inventory_mass_mg) / float(inventory_max_capacity_mg)

# ════════════════════════════════════════════════════════════════════
# 인벤토리 내부 유틸
# ════════════════════════════════════════════════════════════════════

func _is_in_pickup_range(cell: Vector2i) -> bool:
	var player_cell := _world_to_cell(global_position)
	var dx: int = abs(cell.x - player_cell.x)
	var dy: int = abs(cell.y - player_cell.y)
	var dist: int = max(dx, dy)
	return dist <= pickup_reach_cells

static func _kg_to_mg(kg: float) -> int:
	return int(round(kg * 1_000_000.0))

static func _mg_to_kg(mg: int) -> float:
	return float(mg) / 1_000_000.0

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API: 이동

func move_to_world(world_pos: Vector2) -> void:
	var target_cell := _world_to_cell(world_pos)
	move_to_cell(target_cell)

func move_to_cell(cell: Vector2i) -> void:
	# 이동 시작하면 채굴은 일시 중단 (큐는 유지)
	if _mode == Mode.MINING:
		_mode = Mode.MOVING
	
	_goal_cell = cell
	_rebuild_path_to(cell)
	_mode = (Mode.MOVING if _path.size() >= 2 else Mode.IDLE)

func stop() -> void:
	stop_mining()
	_mode = Mode.IDLE
	_path.clear()
	_path_index = 0
	_show_path_preview([])

# ────────────────────────────────────────────────────────────────────
# 퍼블릭 API: 채굴

func add_mining_target(cell: Vector2i) -> void:
	# 이미 큐에 있으면 무시
	if cell in _mining_queue:
		return
	
	_mining_queue.append(cell)
	
	# 현재 채굴 중이 아니면 즉시 시작
	if _mode != Mode.MINING:
		_start_next_mining_task()

func start_mining(cell: Vector2i) -> void:
	# 기존 큐를 비우고 새로 시작
	_mining_queue.clear()
	add_mining_target(cell)

func stop_mining() -> void:
	_mining_queue.clear()
	_mining_target_cell = Vector2i(-9999, -9999)
	_mining_timer = 0.0
	if _mode == Mode.MINING:
		_mode = Mode.IDLE

func clear_mining_queue() -> void:
	_mining_queue.clear()
	if _mode == Mode.MINING:
		stop_mining()

func is_mining() -> bool:
	return _mode == Mode.MINING

func get_mining_target() -> Vector2i:
	return _mining_target_cell if _mode == Mode.MINING else Vector2i(-9999, -9999)

func get_mining_queue() -> Array[Vector2i]:
	return _mining_queue.duplicate()

# ────────────────────────────────────────────────────────────────────
# 내부: 시작 위치 스냅

func _snap_start_to_surface() -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("iter_bounds") or not _grid_nav.has_method("is_walkable_player"):
		return
	
	var b: Rect2i = _grid_nav.iter_bounds()
	var cell := _world_to_cell(global_position)
	cell.x = clamp(cell.x, b.position.x, b.position.x + b.size.x - 1)
	
	for y in range(cell.y, b.position.y + b.size.y):
		var c := Vector2i(cell.x, y)
		if _grid_nav.is_walkable_player(c):
			global_position = Vector2(c) * _cell_px + _cell_px * 0.5
			_last_start_cell = c
			return
	
	for y in range(cell.y - 1, b.position.y - 1, -1):
		var c := Vector2i(cell.x, y)
		if _grid_nav.is_walkable_player(c):
			global_position = Vector2(c) * _cell_px + _cell_px * 0.5
			_last_start_cell = c
			return

# ────────────────────────────────────────────────────────────────────
# 내부: 이동

func _move_along_path(delta: float) -> void:
	if _path.is_empty():
		_mode = Mode.IDLE
		return
	
	var eps: float = max(arrive_epsilon_px, 0.001)
	
	while delta > 0.0 and _path_index < _path.size():
		var p := global_position
		var t := _path[_path_index]
		var to_target := t - p
		var dist := to_target.length()
		
		if dist <= eps:
			global_position = t
			_path_index += 1
			continue
		
		var step := move_speed * delta
		
		if step >= dist:
			global_position = t
			_path_index += 1
			delta -= dist / max(move_speed, 0.0001)
			continue
		
		var dir := to_target / dist
		global_position = p + dir * step
		break
	
	if _path_index >= _path.size():
		_finish_path()

func _finish_path() -> void:
	if _mode == Mode.MOVING:
		_mode = Mode.IDLE
		_show_path_preview([])
		arrived_at_destination.emit()
		
		# 이동 완료 후 채굴 큐가 있으면 재개
		if not _mining_queue.is_empty():
			_start_next_mining_task()

# ────────────────────────────────────────────────────────────────────
# 내부: 경로 재생성

func _rebuild_path_to(cell: Vector2i) -> void:
	if _grid_nav == null:
		return
	if not _grid_nav.has_method("find_path_player"):
		push_warning("[Player] GridNav doesn't have find_path_player method")
		return
	
	var start_cell := _stable_start_cell_from_world(global_position)
	var pts: PackedVector2Array = _grid_nav.find_path_player(start_cell, cell)
	
	if pts.is_empty():
		_path = []
		_path_index = 0
		_show_path_preview(_path)
		return
	
	_adopt_path_from_current_position(pts)
	_show_path_preview(_path)

func _repath_to_goal() -> void:
	if _goal_cell.x < -9998:
		return
	_rebuild_path_to(_goal_cell)
	_repath_cooldown_left = repath_cooldown_sec

# ────────────────────────────────────────────────────────────────────
# 내부: Nav 변경 반응

func _on_nav_changed(_cell: Vector2i) -> void:
	if _mode != Mode.IDLE:
		_repath_cooldown_left = repath_cooldown_sec

func _on_nav_bulk_changed(_rect: Rect2i) -> void:
	if _mode != Mode.IDLE:
		_repath_cooldown_left = repath_cooldown_sec

# ────────────────────────────────────────────────────────────────────
# 내부: 채굴

func _start_next_mining_task() -> void:
	if _mining_queue.is_empty():
		if _mode == Mode.MINING:
			_mode = Mode.IDLE
		_mining_target_cell = Vector2i(-9999, -9999)
		return
	
	_mining_target_cell = _mining_queue[0]
	_mode = Mode.MINING
	_mining_timer = 0.0

func _advance_mining_queue() -> void:
	if not _mining_queue.is_empty():
		_mining_queue.pop_front()
	_start_next_mining_task()

func _apply_mining_damage() -> void:
	if _mining == null or _mining_target_cell.x < -9998:
		_advance_mining_queue()
		return
	
	if _mining.has_method("_on_tool_manager_request_mine"):
		_mining._on_tool_manager_request_mine(_mining_target_cell)

func _is_cell_valid_for_mining(cell: Vector2i) -> bool:
	if _durability == null:
		return false
	
	# Durability가 초기화되어 있고 HP가 남아있는지 확인
	if not _durability.has_method("get_max_hp"):
		return false
	
	var max_hp = _durability.get_max_hp(cell)
	if max_hp <= 0.0:
		return false  # 초기화 안 됨 또는 파괴됨
	return true

func _is_in_mining_range(cell: Vector2i) -> bool:
	var player_cell := _world_to_cell(global_position)
	var dx: int = abs(cell.x - player_cell.x)
	var dy: int = abs(cell.y - player_cell.y)
	var dist: int = max(dx, dy)
	return dist <= mining_reach_cells

# ────────────────────────────────────────────────────────────────────
# 내부: 유틸

func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / _cell_px.x), floor(p.y / _cell_px.y))

func _stable_start_cell_from_world(p: Vector2) -> Vector2i:
	var raw := _world_to_cell(p)
	if _last_start_cell.x < -9998:
		_last_start_cell = raw
		return _last_start_cell
	
	var center := Vector2(_last_start_cell) * _cell_px + _cell_px * 0.5
	if (p - center).length() >= cell_hysteresis_px:
		_last_start_cell = raw
	return _last_start_cell

func _adopt_path_from_current_position(pts: PackedVector2Array) -> void:
	if pts.is_empty():
		_path = []
		_path_index = 0
		return
	
	if pts.size() == 1:
		_path = PackedVector2Array([pts[0]])
		_path_index = 0
		return
	
	var near := _nearest_point_on_polyline(global_position, pts)
	var new_path := PackedVector2Array()
	new_path.append(near.point)
	for i in range(near.seg_idx + 1, pts.size()):
		new_path.append(pts[i])
	
	_path = new_path
	_path_index = 0

func _nearest_point_on_polyline(p: Vector2, pts: PackedVector2Array) -> Dictionary:
	var best_d2 := INF
	var best_idx := 0
	var best_point := pts[0]
	
	for i in range(0, pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		var t := 0.0
		if ab_len2 > 0.0:
			t = clamp(((p - a).dot(ab)) / ab_len2, 0.0, 1.0)
		var proj := a + ab * t
		var d2 := (p - proj).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
			best_point = proj
	
	return {"seg_idx": best_idx, "point": best_point}

func _show_path_preview(points: PackedVector2Array) -> void:
	if not show_path_preview:
		return
	if _overlay and _overlay.has_method("set_path_preview"):
		_overlay.call("set_path_preview", points)
