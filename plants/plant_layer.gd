extends Node
class_name PlantLayer

## 멀티셀 식물 매니저.
## - 배치/점유/성장/충돌/저장 필드를 담당.
## - "규칙은 여기" / "표현은 PlantBase" 원칙.

signal plant_added(id: int, stage_idx: int)
signal plant_stage_changed(id: int, stage_idx: int)
signal plant_removed(id: int)

@export var plant_base_scene: PackedScene    ## 표현용 베이스 프리팹(씬). 선택.
@export var cell_world_scale: Vector2 = Vector2(32, 32)  ## 셀→월드 좌표 변환(간단 스케일)

var _size: Vector2i
var _idx: GridIndex  ## 셀↔선형 인덱스 유틸

## 점유 맵: -1=비어있음, 그 외=인스턴스 ID
var _occ: PackedInt32Array

## 인스턴스 저장 구조(간단 클래스)
class PlantInstance:
	var spec: PlantSpec
	var root_cell: Vector2i
	var stage_idx: int
	var progress: float
	var growth_rate: float
	var occupied: PackedVector2Array  ## 절대좌표 footprint 캐시

	func _init(_spec: PlantSpec, _root: Vector2i, _stage_idx: int, _growth_rate: float) -> void:
		spec = _spec
		root_cell = _root
		stage_idx = _stage_idx
		progress = 0.0
		growth_rate = _growth_rate
		occupied = PackedVector2Array()

var _instances: Array  ## Array[PlantInstance?], 삭제 시 null
var _views: Dictionary = {}  ## id -> PlantBase(Node2D)

## 외부 의존: Soil 판정(하드코딩 회피). set_soil_checker 로 주입.
var _is_soil_cb: Callable = Callable()

func setup(size: Vector2i, index: GridIndex) -> void:
	_size = size
	_idx = index
	_occ = PackedInt32Array()
	_occ.resize(size.x * size.y)
	for i in _occ.size():
		_occ[i] = -1
	_instances = []

func set_soil_checker(checker: Callable) -> void:
	## checker: Callable(cell: Vector2i) -> bool
	_is_soil_cb = checker

func can_place(spec: PlantSpec, root: Vector2i) -> bool:
	if _is_soil_cb.is_null() or not bool(_is_soil_cb.call(root)):
		return false
	var cells := compute_world_footprint(spec, 0, root)
	return _can_occupy(-1, cells)  ## -1=새 배치(모두 비어야)

func place(spec: PlantSpec, root: Vector2i, rate_mult: float = 1.0) -> int:
	if not can_place(spec, root):
		_print_fail("not_placeable", root)
		return -1
	var inst := PlantInstance.new(spec, root, 0, spec.base_growth_rate * rate_mult)
	var id := _instances.size()
	_instances.append(inst)
	var cells := compute_world_footprint(spec, 0, root)
	_mark_occupied(id, cells, true)
	inst.occupied = cells
	_emit_added(id, inst.stage_idx)
	_spawn_view_for(id, inst)
	return id

func remove(id: int) -> void:
	if id < 0 or id >= _instances.size(): return
	var inst: PlantInstance = _instances[id]
	if inst == null: return
	_mark_occupied(id, inst.occupied, false)
	_instances[id] = null
	_emit_removed(id)
	_free_view(id)

func tick(dt: float) -> void:
	for id in _instances.size():
		var p: PlantInstance = _instances[id]
		if p == null: continue
		## 마지막 단계면 고정
		if p.stage_idx >= p.spec.stage_count() - 1:
			p.progress = 1.0
			continue

		p.progress += p.growth_rate * dt
		var advanced := false
		while p.progress >= 1.0:
			var next := p.stage_idx + 1
			if next >= p.spec.stage_count():
				p.progress = 1.0
				break
			var next_cells := compute_world_footprint(p.spec, next, p.root_cell)
			if _can_occupy(id, next_cells):
				_mark_occupied(id, p.occupied, false)
				p.stage_idx = next
				_mark_occupied(id, next_cells, true)
				p.occupied = next_cells
				p.progress -= 1.0
				_emit_stage_changed(id, p.stage_idx)
				_update_view_for(id, p)
				advanced = true
			else:
				## 자리 막힘 → 정지(다시 시도 가능)
				p.progress = 0.999
				break
		## 필요 시 추가 로직(예: 번식 등) 자리

## ── Utilities ─────────────────────────────────────────────────────────

func compute_world_footprint(spec: PlantSpec, stage_idx: int, root: Vector2i) -> PackedVector2Array:
	var offs := spec.get_footprint(stage_idx)
	var out := PackedVector2Array()
	out.resize(offs.size())
	for i in offs.size():
		out[i] = root + Vector2i(offs[i])
	return out

func _can_occupy(self_id: int, cells: PackedVector2Array) -> bool:
	for c in cells:
		if not _in_bounds(c):
			return false
		var li := _idx.idx(c)
		var occ := _occ[li]
		if occ != -1 and occ != self_id:
			return false
	return true

func _mark_occupied(id: int, cells: PackedVector2Array, occupy: bool) -> void:
	var val := (id if occupy else -1)
	for c in cells:
		if not _in_bounds(c): continue
		_occ[_idx.to_linear(c)] = val

func _in_bounds(c: Vector2i) -> bool:
	return (c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y)

func _emit_added(id: int, stage_idx: int) -> void:
	emit_signal("plant_added", id, stage_idx)

func _emit_stage_changed(id: int, stage_idx: int) -> void:
	emit_signal("plant_stage_changed", id, stage_idx)

func _emit_removed(id: int) -> void:
	emit_signal("plant_removed", id)

func _print_fail(reason: String, root: Vector2i) -> void:
	push_warning("[Plant] place fail: reason=%s root=(%d,%d)" % [reason, root.x, root.y])

## ── Views (표현 연결: 얇게) ──────────────────────────────────────────

func _spawn_view_for(id: int, p: PlantInstance) -> void:
	if plant_base_scene == null: return
	var node := plant_base_scene.instantiate()
	_views[id] = node
	if node.has_method("setup_from_layer"):
		node.setup_from_layer(id, p.spec.id, p.root_cell, p.stage_idx)
	## 셀→월드 좌표(간단 스케일)
	node.position = Vector2(p.root_cell) * cell_world_scale
	add_child(node)

func _update_view_for(id: int, p: PlantInstance) -> void:
	var node: PlantBase = _views.get(id, null)
	if node == null: return
	if node.has_method("set_stage"):
		node.set_stage(p.stage_idx)

func _free_view(id: int) -> void:
	var node: PlantBase = _views.get(id, null)
	if node == null: return
	if is_instance_valid(node):
		node.queue_free()
	_views.erase(id)
