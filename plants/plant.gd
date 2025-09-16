## 식물 담당 매니저.
## - 배치/점유/성장/충돌/저장 필드를 담당.
## - "규칙은 여기" / "표현은 PlantView" 원칙.
extends Node
class_name Plant

## ── Debug logging ────────────────────────────────────────────────────
@export var debug_enabled: bool = false              ## 로그 on/off
@export var debug_progress_log_sec: float = 0.0     ## >0이면 진행도 주기 로그 (예: 1.0)
var _debug_accum: float = 0.0

func _log(msg: String, args: Array = []):
	if not debug_enabled: return
	if args.is_empty():
		print("[Plant]", msg)
	else:
		print("[Plant] " + msg % args)

signal plant_added(id: int, stage_idx: int)
signal plant_stage_changed(id: int, stage_idx: int)
signal plant_removed(id: int)

@export var plant_base_scene: PackedScene ## 표현용 베이스 프리팹(씬). 선택.
@export var cell_world_scale: Vector2 = Vector2(32, 32) ## 셀→월드 좌표 변환(간단 스케일)

var _size: Vector2i # 프로젝트 공통 기준값.
var _grid: GridIndex

## 점유 맵: -1=비어있음, 그 외=인스턴스 ID
var _occupancy: PackedInt32Array
const OCCUPANCY_EMPTY := -1
# TODO 스크립트의 -1이 OCCUPANCY_EMPTY를 의미하는지 확인하고, 교체 필요.

## 인스턴스 저장 구조(간단 클래스)
class PlantInstance:
	var spec: PlantSpec
	var root_cell: Vector2i        ## root 셀의 Grid 좌표
	var stage_idx: int             ## 생장 단계 (0에서 시작)
	var progress: float            ## 현재 생장률 저장
	var growth_rate: float         ## 초당 생장률
	var occupied: Array[Vector2i]  ## 절대좌표 footprint 캐시

	func _init(_spec: PlantSpec, _root: Vector2i, _stage_idx: int, _growth_rate: float) -> void:
		spec = _spec
		root_cell = _root
		stage_idx = _stage_idx
		progress = 0.0
		growth_rate = _growth_rate
		occupied = []

## 식물 객체들의 참조를 보관하는 레지스트리. 
var _instances: Array[PlantInstance]
var _views: Dictionary = {}  ## id: int -> value: PlantView(Node2D)

## 외부 의존: Soil 판정(하드코딩 회피). set_soil_checker 로 주입.
var _is_soil_cb: Callable = Callable()

func setup(index: GridIndex) -> void:
	_grid = index
	_size = _grid.size
	_occupancy = PackedInt32Array()
	_occupancy.resize(_size.x * _size.y)
	for i in _occupancy.size():
		_occupancy[i] = OCCUPANCY_EMPTY
	_instances = []

## checker: Callable(cell: Vector2i) -> bool
func set_soil_checker(checker: Callable) -> void:
	_is_soil_cb = checker

## 식물의 spec을 보고 root의 좌표에 place할 수 있는지 여부를 반환한다.
## 검사 단계:
## 1. root 좌표가 soil인지.
## 2. 생장 단계 0에서 점유해야 하는 좌표들에 대해 점유가 가능한지.
func can_place(spec: PlantSpec, root: Vector2i) -> bool:
	# soil checker가 null이면 경고한다.
	if _is_soil_cb.is_null():
		push_warning("[Plant.can_place] soil checker is null")
		return false
	# root 좌표가 soil이 아니라면 false를 출력한다.
	if not bool(_is_soil_cb.call(root)):
		return false
	# spec 기준 생장 단계 0(기본값)에서 점유하는 절대 좌표를 가져온다.
	var cells := compute_world_footprint(spec, 0, root)
	return _can_occupy(-1, cells) # -1=새 배치(모두 비어야)

## 새로운 식물 객체를 만들어 등록하고 ID를 반환한다.
## 0. 배치가 가능한지 검사
## 1. 식물 객체를 생성해서 레지스트리 배열에 추가
## 2. 점유 위치를 계산하고 점유 맵에 기록
## 3. plant_added 시그널을 발행
## 4. _spawn_view_for
## 5. ID 반환
func place(spec: PlantSpec, root: Vector2i, rate_mult: float = 1.0) -> int:
	# 배치가 가능한지 검사한다.
	if not can_place(spec, root):
		_print_fail("not_placeable", root)
		return -1
	# 객체를 생성하고 새 id를 할당한다.
	var inst := PlantInstance.new(spec, root, 0, spec.base_growth_rate * rate_mult)
	var id := _instances.size()
	# 레지스트리 배열에 추가한다.
	_instances.append(inst)
	# 점유 위치를 계산하고 점유 맵에 기록한다.
	var cells := compute_world_footprint(spec, 0, root)
	_mark_occupied(id, cells, true)
	inst.occupied = cells
	# 시그널 발행
	_emit_added(id, inst.stage_idx)
	#
	_spawn_view_for(id, inst)
	_log("placed id=%d spec=%s root=(%d,%d) rate=%.3f", [id, String(inst.spec.id), root.x, root.y, inst.growth_rate])
	return id

func remove(id: int) -> void:
	if id < 0 or id >= _instances.size(): return
	var inst: PlantInstance = _instances[id]
	if inst == null: return
	_mark_occupied(id, inst.occupied, false)
	_instances[id] = null
	_emit_removed(id)
	_free_view(id)
	_log("removed id=%d", [id])

func tick(dt: float) -> void:
	# 선택적 주기 로그용 누산
	if debug_progress_log_sec > 0.0:
		_debug_accum += dt

	for id in _instances.size():
		var p: PlantInstance = _instances[id]
		if p == null: continue
		## 마지막 단계면 고정
		if p.stage_idx >= p.spec.stage_count() - 1:
			p.progress = 1.0
			continue

		var prev_stage := p.stage_idx
		var prev_progress := p.progress

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

				#var rel_next := p.spec.get_footprint(p.stage_idx)            # 상대
				#var abs_next := compute_world_footprint(p.spec, p.stage_idx, p.root_cell)  # 절대
				#print_rich("[Plant] advanced id=", id,
					#" stage=", p.stage_idx,
					#"\n  rel=", rel_next,
					#"\n  abs=", abs_next)

				_log(
					"stage_advanced id=%d -> stage=%d progress=%.3f", [id, p.stage_idx, p.progress]
				)
			else:
				## 자리 막힘 → 정지(다시 시도 가능)
				p.progress = 0.999
				_log(
					"blocked id=%d at stage=%d (footprint occupied)", [id, p.stage_idx]
				)
				break
		## 필요 시 추가 로직(예: 번식 등) 자리

		# 선택적 주기 로그 (진행도 스냅샷)
		if debug_progress_log_sec > 0.0 and _debug_accum >= debug_progress_log_sec and not advanced:
			_log("progress id=%d stage=%d prog=%.3f (+%.3f)", [id, p.stage_idx, p.progress, p.progress - prev_progress])

	if debug_progress_log_sec > 0.0 and _debug_accum >= debug_progress_log_sec:
		_debug_accum = 0.0

# ── Utilities ─────────────────────────────────────────────────────────
## 입력: spec, 생장 단계 값, root 좌표
## 출력: 점유하는 타일의 절대 좌표의 배열
func compute_world_footprint(spec: PlantSpec, stage_idx: int, root: Vector2i) -> Array[Vector2i]:
	var offs: Array[Vector2i] = spec.get_footprint(stage_idx)
	var out: Array[Vector2i] = []
	out.resize(offs.size())
	for i in offs.size():
		out[i] = root + offs[i]
	return out

func _can_occupy(self_id: int, cells: Array[Vector2i]) -> bool:
	for c in cells:
		if not _in_bounds(c):
			return false
		var li := _grid.idx(c)
		var occ := _occupancy[li]
		if occ != -1 and occ != self_id:
			return false
	return true

func _mark_occupied(id: int, cells: Array[Vector2i], occupy: bool) -> void:
	var val := (id if occupy else -1)
	for c in cells:
		if not _in_bounds(c): continue
		_occupancy[_grid.idx(c)] = val

func _in_bounds(c: Vector2i) -> bool:
	return (c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y)

func _emit_added(id: int, stage_idx: int) -> void:
	plant_added.emit(id, stage_idx)

func _emit_stage_changed(id: int, stage_idx: int) -> void:
	plant_stage_changed.emit(id, stage_idx)

func _emit_removed(id: int) -> void:
	plant_removed.emit(id)

func _print_fail(reason: String, root: Vector2i) -> void:
	push_warning("[Plant] place fail: reason=%s root=(%d,%d)" % [reason, root.x, root.y])

# ── Views (표현 연결: 얇게) ──────────────────────────────────────────

func _spawn_view_for(id: int, p: PlantInstance) -> void:
	if plant_base_scene == null: return
	var node := plant_base_scene.instantiate()
	_views[id] = node
	if node.has_method("setup_from_layer"):
		node.setup_from_layer(id, p.spec.id, p.root_cell, p.stage_idx)
	node.position = Vector2(p.root_cell) * cell_world_scale
	add_child(node)
	if node.has_method("set_stage_and_cells"):
		node.set_stage_and_cells(p.stage_idx, p.occupied, cell_world_scale)

func _update_view_for(id: int, p: PlantInstance) -> void:
	var node: PlantView = _views.get(id, null)
	if node == null: return
	if node.has_method("set_stage_and_cells"):
		node.set_stage_and_cells(p.stage_idx, p.occupied, cell_world_scale)

func _free_view(id: int) -> void:
	var node: PlantView = _views.get(id, null)
	if node == null: return
	if is_instance_valid(node):
		node.queue_free()
	_views.erase(id)
