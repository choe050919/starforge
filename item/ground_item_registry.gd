## GroundItemRegistry.gd
## - 셀 위의 지상 드롭(아이템 스택) 레지스트리 (MVP)
## - 데이터/신호만 관리, 뷰/스폰은 외부가 구독
extends Node
class_name GroundItemRegistry

# ── 시그널 ───────────────────────────────────────────────────────────────────
signal stack_created(cell: Vector2i, stack_index: int, material_sid: int, mass_kg: float, temperature_K: float)
signal stack_updated(cell: Vector2i, stack_index: int, material_sid: int, mass_kg: float, temperature_K: float)
signal stack_removed(cell: Vector2i, stack_index: int, material_sid: int)

# ── 설정 ─────────────────────────────────────────────────────────────────────
@export var default_merge_temperature_tolerance_K: float = 5.0
@export var max_mass_per_stack_kg: float = 1e12
@export var debug_enabled: bool = false

const MASS_SNAP_KG := 1e-6 # 1 mg

# ── 내부 상태 ────────────────────────────────────────────────────────────────
# 셀 키(int) → Array[Dictionary]
# stack schema: {"material_sid": int, "mass_kg": float, "temperature_K": float}
var _stacks_by_cell: Dictionary = {}

# ── 퍼블릭 API ───────────────────────────────────────────────────────────────
## Mining.gd에서 호출
func add_or_merge(cell: Vector2i, material_sid_v: Variant, mass_kg: float, temperature_K: float, tolerance_K: float = -1.0) -> void:
	if mass_kg <= 0.0:
		return
	var sid := _coerce_sid(material_sid_v)
	if sid < 0:
		push_warning("[GroundItemRegistry] invalid material sid: %s" % [material_sid_v])
		return
	var tol := default_merge_temperature_tolerance_K if tolerance_K < 0.0 else tolerance_K
	var k := _key(cell)

	var stacks: Array = _stacks_by_cell.get(k, [])
	var match_i := _find_merge_candidate_index(stacks, sid, temperature_K, tol)

	if match_i >= 0:
		# 병합
		var s: Dictionary = stacks[match_i]
		var old_mass := float(s.get("mass_kg", 0.0))
		var new_mass := _snap_mass_kg(old_mass + mass_kg)
		var new_temp := _mass_weighted_temperature(
			float(s.get("temperature_K", temperature_K)), old_mass,
			temperature_K, mass_kg
		)

		s["mass_kg"] = new_mass
		s["temperature_K"] = new_temp

		# 필요 시 스택 분할
		if new_mass > max_mass_per_stack_kg:
			var overflow := new_mass - max_mass_per_stack_kg
			s["mass_kg"] = max_mass_per_stack_kg
			var new_stack := {
				"material_sid": sid,
				"mass_kg": _snap_mass_kg(overflow),
				"temperature_K": new_temp,
			}
			stacks.append(new_stack)
			Debug.log(self, "stack split: cell=%s sid=%s base=%s overflow=%s", [cell, sid, s["mass_kg"], overflow])

		# 배열에 다시 반영(참조형이지만 명시적으로 대입)
		stacks[match_i] = s
		_stacks_by_cell[k] = stacks

		if debug_enabled:
			print("[GroundItemRegistry] merged cell=", cell, " sid=", sid, " mass=", s["mass_kg"], " temp=", s["temperature_K"])
		stack_updated.emit(cell, match_i, sid, float(s["mass_kg"]), float(s["temperature_K"]))
	else:
		# 새 스택
		var s := {
			"material_sid": sid,
			"mass_kg": _snap_mass_kg(mass_kg),
			"temperature_K": float(temperature_K),
		}
		if stacks.is_empty():
			_stacks_by_cell[k] = [s]
			match_i = 0
		else:
			stacks.append(s)
			_stacks_by_cell[k] = stacks
			match_i = stacks.size() - 1

		if debug_enabled:
			print("[GroundItemRegistry] created cell=", cell, " sid=", sid, " mass=", s["mass_kg"], " temp=", s["temperature_K"])
		stack_created.emit(cell, match_i, sid, float(s["mass_kg"]), float(s["temperature_K"]))

## 드롭 줍기/소비: 스택에서 질량 제거(0이면 삭제)
func remove_mass(cell: Vector2i, stack_index: int, take_mass_kg: float) -> void:
	if take_mass_kg <= 0.0: 
		return
	var k := _key(cell)
	if not _stacks_by_cell.has(k): 
		return
	var stacks: Array = _stacks_by_cell[k]
	if stack_index < 0 or stack_index >= stacks.size(): 
		return

	var s: Dictionary = stacks[stack_index]
	var new_mass := _snap_mass_kg(max(0.0, float(s.get("mass_kg", 0.0)) - take_mass_kg))
	s["mass_kg"] = new_mass
	stacks[stack_index] = s

	if new_mass > 0.0:
		if debug_enabled:
			print("[GroundItemRegistry] take mass cell=", cell, " idx=", stack_index, " rest=", new_mass)
		stack_updated.emit(cell, stack_index, int(s.get("material_sid", -1)), float(s["mass_kg"]), float(s.get("temperature_K", 0.0)))
	else:
		var sid := int(s.get("material_sid", -1))
		stacks.remove_at(stack_index)
		if stacks.is_empty():
			_stacks_by_cell.erase(k)
		else:
			_stacks_by_cell[k] = stacks
		if debug_enabled:
			print("[GroundItemRegistry] stack removed cell=", cell, " idx=", stack_index)
		stack_removed.emit(cell, stack_index, sid)

## 읽기 전용 복사본
func get_stacks_in_cell(cell: Vector2i) -> Array:
	var k := _key(cell)
	if not _stacks_by_cell.has(k): 
		return []
	var out: Array = []
	for s in _stacks_by_cell[k]:
		out.append((s as Dictionary).duplicate(true))
	return out

## 비우기(디버그)
func clear_cell(cell: Vector2i) -> void:
	var k := _key(cell)
	if not _stacks_by_cell.has(k): 
		return
	var stacks: Array = _stacks_by_cell[k]
	for i in range(stacks.size() - 1, -1, -1):
		var sid := int((stacks[i] as Dictionary).get("material_sid", -1))
		stack_removed.emit(cell, i, sid)
	_stacks_by_cell.erase(k)
	if debug_enabled:
		print("[GroundItemRegistry] cleared cell=", cell)

func clear_all() -> void:
	_stacks_by_cell.clear()
	if debug_enabled:
		print("[GroundItemRegistry] cleared all")

# ── 내부 유틸 ────────────────────────────────────────────────────────────────
static func _key(cell: Vector2i) -> int:
	return (cell.y << 16) | (cell.x & 0xFFFF)

static func _snap_mass_kg(x: float) -> float:
	return floor((x / MASS_SNAP_KG) + 0.5) * MASS_SNAP_KG

static func _coerce_sid(v: Variant) -> int:
	if v is int:
		return v
	return int(str(v))

static func _mass_weighted_temperature(t1: float, m1: float, t2: float, m2: float) -> float:
	var tot := m1 + m2
	if tot <= 0.0:
		return 0.0
	return (t1 * m1 + t2 * m2) / tot

## 🔧 누락됐던 함수: 병합 후보 탐색(같은 SID + 온도 차 허용 범위)
func _find_merge_candidate_index(stacks: Array, sid: int, temperature_K: float, tolerance_K: float) -> int:
	var best_i := -1
	var best_diff := 1.0e30
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		if int(s.get("material_sid", -1)) != sid:
			continue
		var t := float(s.get("temperature_K", temperature_K))
		var diff := absf(t - temperature_K)
		if diff <= tolerance_K and diff < best_diff:
			best_diff = diff
			best_i = i
	return best_i
