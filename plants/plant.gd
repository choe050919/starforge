## 식물 담당 매니저.
## - 배치/점유/성장/충돌/저장 필드를 담당.
## - "규칙은 여기" / "표현은 PlantView" 원칙.
extends Node
class_name Plant

const Part = preload("res://plants/plant_part.gd")

## ── Debug logging ────────────────────────────────────────────────────
@export var debug_enabled: bool = false              ## 로그 on/off
@export var debug_progress_log_sec: float = 0.0     ## >0이면 진행도 주기 로그 (예: 1.0)
var _debug_accum: float = 0.0

func _log(msg: String, args: Array = []):
	if not debug_enabled: return
	if args.is_empty():
		print("[Plant] ", msg)
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

## 인스턴스 저장 구조(간단 클래스)
class PlantInstance:
	var spec: PlantSpec
	var root_cell: Vector2i        ## root 셀의 Grid 좌표
	var stage_idx: int             ## 생장 단계 (0에서 시작)
	var progress: float            ## 현재 생장률 저장
	var growth_rate: float         ## 초당 생장률
	var occupied: Array[Vector2i]  ## 절대좌표 footprint 캐시
	var tags_base: PackedInt32Array ## occupied와 index를 공유
	var fruit_maturity: PackedFloat32Array ## 열매 성숙도(0.0~1.0), 비-FRUIT는 -1.0
	var fruit_present: PackedByteArray ## 열매 존재(0/1). 비-FRUIT는 0
	var leaf_indices: PackedInt32Array ## 현재 stage에서 LEAF 파트의 인덱스 캐시(샘플링 최적화)

	func _init(_spec: PlantSpec, _root: Vector2i, _stage_idx: int, _growth_rate: float) -> void:
		spec = _spec
		root_cell = _root
		stage_idx = _stage_idx
		progress = 0.0
		growth_rate = _growth_rate
		occupied = []
		leaf_indices = PackedInt32Array()

## 식물 객체들의 참조를 보관하는 레지스트리. 
var _instances: Array[PlantInstance]
var _views: Dictionary = {}  ## id: int -> value: PlantView(Node2D)

## 외부 의존: Soil 판정(하드코딩 회피). set_soil_checker 로 주입.
var _is_soil_cb: Callable = Callable()

## 외부 의존: Light 샘플링(주입식). set_light_sampler 로 주입.
var _light_sampler: Callable = Callable()

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

## sampler: Callable(cell: Vector2i) -> float (W/m²)
func set_light_sampler(sampler: Callable) -> void:
	_light_sampler = sampler

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
	# FRUIT 초기화
	_init_stage_state(inst)
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

# ── Tick ──────────────────────────────────────────────────────────────

func tick(dt: float) -> void:
	if debug_progress_log_sec > 0.0:
		_debug_accum += dt

	# PlantInstance 순회
	for id in _instances.size():
		var p: PlantInstance = _instances[id]
		if p == null:
			continue

		var prev_progress := p.progress
		var advanced := _advance_growth_for_instance(id, p, dt)
		var fruit_changed := _update_fruit_for_instance(p, dt)

		# 열매 시각 반영이 필요하면 뷰 갱신
		if fruit_changed:
			_update_view_for(id, p)

		if debug_progress_log_sec > 0.0 and _debug_accum >= debug_progress_log_sec and not advanced:
			_log("progress id=%d stage=%d prog=%.3f (+%.3f)", [
				id, p.stage_idx, p.progress, p.progress - prev_progress
			])

	if debug_progress_log_sec > 0.0 and _debug_accum >= debug_progress_log_sec:
		_debug_accum = 0.0

## 성장률 누적 + 스테이지 전환까지 담당.
## 반환값: 이번 tick 동안 스테이지가 1회 이상 전진했는지
func _advance_growth_for_instance(id: int, p: PlantInstance, dt: float) -> bool:
	var advanced := false

	# 마지막 스테이지면 고정, 성장 계산 종료
	if p.stage_idx >= p.spec.stage_count() - 1:
		p.progress = 1.0
		return false

	# 빛 비례 factor 계산 (샘플러가 없으면 1.0로 처리해 기존 동작 유지)
	var factor := _compute_light_factor_for(p)
	if factor <= 0.0:
		# (옵션) 디버그 간격 로깅에 잡히도록 그대로 두고, 누적만 생략
		# if debug_progress_log_sec > 0.0: _log("light_block id=%d stage=%d", [id, p.stage_idx])
		pass
	else:
		p.progress += (p.growth_rate * factor) * dt

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
			_init_stage_state(p)  # 스테이지 전환에 따른 FRUIT 초기화
			p.progress -= 1.0
			_emit_stage_changed(id, p.stage_idx)
			_update_view_for(id, p)
			advanced = true
			_log("stage_advanced id=%d -> stage=%d progress=%.3f",
				[id, p.stage_idx, p.progress])
		else:
			# 자리 막힘 → 정지(다시 시도 가능)
			p.progress = 0.999
			_log("blocked id=%d at stage=%d (footprint occupied)", [id, p.stage_idx])
			break

	return advanced

## 열매 성숙 처리.
## 반환값: 성숙도 변화가 실제로 있었는지 (뷰 갱신 힌트)
func _update_fruit_for_instance(p: PlantInstance, dt: float) -> bool:
	var rate := p.spec.fruit_growth_rate
	if rate == 0.0:
		return false

	# 과일도 빛 비례 옵션
	if p.spec.fruit_light_coupled:
		var f := _compute_light_factor_for(p)
		if f <= 0.0:
			return false
		rate *= f

	var changed := false
	var n := p.occupied.size()

	for i in n:
		# 이미 열매가 존재하는 셀은 스킵
		if p.fruit_present[i] == 1:
			continue
		# 열매가 아닌 파트면 스킵
		if (int(p.tags_base[i]) & Part.PlantPart.FRUIT) == 0:
			continue
		# 성숙도 증가
		var before := p.fruit_maturity[i]
		var after: float = clamp(before + rate * dt, 0.0, 1.0)
		if after != before:
			p.fruit_maturity[i] = after
			if after == 1.0:
				p.fruit_present[i] = 1
				_log("열매가 완전히 성숙했습니다.")
			changed = true

	return changed


# ── Utilities ─────────────────────────────────────────────────────────

# [_init_stage_state]
# 특정 PlantInstance의 "현재 stage"에 맞춰
# - 정적 태그(tags_base)
# - 열매 성숙도(fruit_maturity)
# - 열매 존재 여부(fruit_present)
# 배열을 초기화한다.
#
# 호출 타이밍:
#   • place() 직후 (최초 배치)
#   • stage advance 직후 (성장 단계 전환)
#
# 처리 내용:
#   1) PlantSpec에서 현재 stage의 part_tags를 복사 → tags_base로 저장
#   2) occupied 크기(n)에 맞춰 fruit_maturity / fruit_present 배열 생성
#   3) 각 셀을 순회:
#        - FRUIT 태그가 있으면:
#            fruit_maturity = spec의 초기값 (보통 0.0)
#            fruit_present  = 0 (보통 성숙도 0에서 시작하므로 없음)
#        - FRUIT 태그가 없으면:
#            fruit_maturity = -1.0 (센티널, 열매 없음)
#            fruit_present  = 0
#
# 결과적으로, PlantInstance는
# "이 stage에서 어떤 셀에 열매가 달려 있고,
#   성숙도가 어디까지 차 있는지"를
# 깔끔하게 새로 세팅하게 된다.
# ─────────────────────────────────────────────────────────────
func _init_stage_state(p: PlantInstance) -> void:
	var tags := p.spec.get_part_tags(p.stage_idx)
	p.tags_base = tags.duplicate()

	var n := p.occupied.size()
	p.fruit_maturity = PackedFloat32Array(); p.fruit_maturity.resize(n)
	p.fruit_present  = PackedByteArray();    p.fruit_present.resize(n)

	var init_m := p.spec.fruit_initial_maturity
	for i in n:
		var is_fruit := (int(p.tags_base[i]) & Part.PlantPart.FRUIT) != 0
		if is_fruit:
			p.fruit_maturity[i] = init_m
			p.fruit_present[i] = 0
		else:
			p.fruit_maturity[i] = -1.0
			p.fruit_present[i] = 0

	# LEAF 인덱스 캐시 생성 (스테이지 전환 시 1회 계산)
	var leafs := PackedInt32Array()
	for i in n:
		if (int(p.tags_base[i]) & Part.PlantPart.LEAF) != 0:
			leafs.push_back(i)
	p.leaf_indices = leafs

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
		if occ != OCCUPANCY_EMPTY and occ != self_id:
			return false
	return true

func _mark_occupied(id: int, cells: Array[Vector2i], occupy: bool) -> void:
	var val := (id if occupy else OCCUPANCY_EMPTY)
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
	if node.has_method("set_part_tags_and_fruit"):
		node.set_part_tags_and_fruit(p.tags_base, p.fruit_present, p.fruit_maturity)

func _update_view_for(id: int, p: PlantInstance) -> void:
	var node: PlantView = _views.get(id, null)
	if node == null: return
	if node.has_method("set_stage_and_cells"):
		node.set_stage_and_cells(p.stage_idx, p.occupied, cell_world_scale)
	if node.has_method("set_part_tags_and_fruit"):
		node.set_part_tags_and_fruit(p.tags_base, p.fruit_present, p.fruit_maturity)

func _free_view(id: int) -> void:
	var node: PlantView = _views.get(id, null)
	if node == null: return
	if is_instance_valid(node):
		node.queue_free()
	_views.erase(id)

# [추가] 빛 샘플링 → 비례 factor 계산
func _compute_light_factor_for(p: PlantInstance) -> float:
	# ── 스테이지-0(씨앗) 면제: 빛과 무관하게 100% 성장 ──
	if p.stage_idx == 0:
		return 1.0

	# 샘플러 미주입 → 기존 동작 유지(성장 100%)
	if _light_sampler.is_null():
		return 1.0

	var L_min: float = max(p.spec.required_light_wm2, 0.0)
	var L_opt: float = max(p.spec.optimal_light_wm2, 0.0)

	# 샘플 셀 목록: LEAF가 있으면 LEAF만, 없으면 root 1셀
	var sum := 0.0
	var cnt := 0

	if p.leaf_indices.size() > 0:
		for i in p.leaf_indices:
			if i >= 0 and i < p.occupied.size():
				var cell := p.occupied[i]
				var L := float(_light_sampler.call(cell))
				if L > 0.0:
					sum += L
				cnt += 1
	else:
		var Lr := float(_light_sampler.call(p.root_cell))
		if Lr > 0.0:
			sum += Lr
		cnt = 1

	if cnt <= 0:
		return 0.0

	var L_avg := sum / float(cnt)

	# 선형 비례: factor = clamp((L - L_min) / (L_opt - L_min), 0..1)
	var denom: float = max(L_opt - L_min, 0.000001)
	var factor: float = (L_avg - L_min) / denom
	if factor < 0.0: factor = 0.0
	elif factor > 1.0: factor = 1.0
	return factor


# ── Public API: Plant-Fish 상호작용용 조회/행동 ───────────────────────
# 외부에서 Plant 상태를 읽고/요청하기 위한 최소 인터페이스.
# 배열에 직접 접근 금지: 반드시 아래 행동 메서드를 통해 변경할 것.

## 해당 셀을 점유 중인 식물 인스턴스 id 반환. 없으면 -1.
func get_plant_id_at_cell(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return OCCUPANCY_EMPTY
	return _occupancy[_grid.idx(cell)]

## 셀 단위 파트 정보 조회.
## 반환 예:
## { "found": true, "plant_id": 0, "part_index": 1, "tags": 8, "fruit_present": true, "fruit_maturity": 1.0 }
func get_part_info_at_cell(cell: Vector2i) -> Dictionary:
	var out := {
		"found": false,
		"plant_id": OCCUPANCY_EMPTY,
		"part_index": -1,
		"tags": 0,
		"fruit_present": false,
		"fruit_maturity": -1.0,
	}
	if not _in_bounds(cell):
		return out

	var id := _occupancy[_grid.idx(cell)]
	if id == OCCUPANCY_EMPTY:
		return out

	# 인스턴스 확인
	if id < 0 or id >= _instances.size():
		return out
	var p: PlantInstance = _instances[id]
	if p == null:
		return out

	# 안전성: 길이 일치 검사(디버깅 도움)
	if p.occupied.size() != p.tags_base.size():
		push_warning("[Plant.get_part_info_at_cell] size mismatch: occ=%d tags=%d"
			% [p.occupied.size(), p.tags_base.size()])

	# 동일 셀의 파트 인덱스 찾기(초기엔 선형검색으로 충분)
	var part_idx := -1
	for i in p.occupied.size():
		if p.occupied[i] == cell:
			part_idx = i
			break
	if part_idx == -1:
		return out

	out.found = true
	out.plant_id = id
	out.part_index = part_idx
	out.tags = int(p.tags_base[part_idx])
	out.fruit_present = (p.fruit_present[part_idx] == 1)
	out.fruit_maturity = p.fruit_maturity[part_idx]
	return out

## 동일 셀 수확: 해당 셀이 "익은 과일"이면 수확하고 true 반환. 아니면 false.
## - 성공 시: fruit_present=0, fruit_maturity=fruit_initial_maturity 로 리셋 후 뷰 갱신.
## - 향후 확장 여지:
##   • 8방/가까운 과일 탐색 헬퍼 추가
##   • 수확 시 인벤토리/아이템 스폰 훅
func try_harvest_fruit_at_cell(cell: Vector2i) -> bool:
	var info := get_part_info_at_cell(cell)
	if not info.found:
		return false

	# FRUIT 태그 확인
	if (info.tags & Part.PlantPart.FRUIT) == 0:
		return false

	# 현재 과일 존재해야 함(present==1). 성숙도 체크는 정책에 따라: present면 충분.
	if not info.fruit_present:
		return false

	# 상태 갱신
	var id := int(info.plant_id)
	var idx := int(info.part_index)
	var p: PlantInstance = _instances[id]
	if p == null:
		return false

	p.fruit_present[idx] = 0
	p.fruit_maturity[idx] = p.spec.fruit_initial_maturity

	# 뷰 갱신
	_update_view_for(id, p)

	if debug_enabled:
		_log("fruit_harvested id=%d part_idx=%d", [id, idx])

	return true
