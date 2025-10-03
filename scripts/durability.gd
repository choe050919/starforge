extends Node
class_name Durability

# ─────────────────────────────────────────────────────────
# 시그널
signal hp_changed(cell: Vector2i, hp: float, max_hp: float)
signal threshold_chunk_requested(cell: Vector2i, chunk_mass_kg: float, threshold_value: float)
signal break_requested(cell: Vector2i)

# ─────────────────────────────────────────────────────────
# 외부 참조
var _data: DataLayer
var _index: GridIndex
var _grid_size: Vector2i = Vector2i.ZERO

# ─────────────────────────────────────────────────────────
# Config
## 문턱 비율(내림차순) — 기본: 80/60/40/20/0%
@export var threshold_ratios: PackedFloat32Array = PackedFloat32Array([0.8, 0.6, 0.4, 0.2, 0.0])

## 재질 경도 테이블(HP per kg). 예) {"10002":0.2, "10001":0.3, "10004":0.8, "10003":1.2}
## 키는 SID를 문자열로 넣는 걸 권장(Inspector 편의). 코드에서는 int로 변환해 사용.
@export var hardness_by_sid := {
	"0": 0.0,
	"10001": 30, # ICE
	"10002": 20, # SOIL
	"10003": 120, # URANIUM
	"10004": 80, # COPPER
}

## 디버그 로그
@export var debug_log: bool = false

## HP 비교용 epsilon
const EPS := 1e-6

# ─────────────────────────────────────────────────────────
# Per-cell state
var _hp: PackedFloat32Array = PackedFloat32Array()
var _max_hp: PackedFloat32Array = PackedFloat32Array()
var _initial_mass_kg: PackedFloat32Array = PackedFloat32Array()
var _hardness_hp_per_kg: PackedFloat32Array = PackedFloat32Array()
var _next_threshold_index: PackedInt32Array = PackedInt32Array()
var _is_initialized: PackedByteArray = PackedByteArray()

## Preprocessed thresholds (descending, clamped)
var _thresholds: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	# 정렬·정합성 보정
	var arr: Array = []
	for i in threshold_ratios.size():
		arr.append(float(threshold_ratios[i]))
	arr.sort()                # 오름차순
	arr.reverse()             # 내림차순
	# 0.0이 없다면 끝에 추가
	if arr.is_empty() or abs(arr.back() - 0.0) > EPS:
		arr.append(0.0)
	_thresholds = PackedFloat32Array(arr)
	if debug_log:
		print("[Dur] thresholds(desc) = ", _thresholds)

func _allocate_arrays(size: Vector2i) -> void:
	var total := size.x * size.y
	if debug_log:
		print("[Dur] allocate arrays: total=", total, " size=", size)
	_hp.resize(total)
	_max_hp.resize(total)
	_initial_mass_kg.resize(total)
	_hardness_hp_per_kg.resize(total)
	_next_threshold_index.resize(total)
	_is_initialized.resize(total)
	for i in total:
		_hp[i] = 0.0
		_max_hp[i] = 0.0
		_initial_mass_kg[i] = 0.0
		_hardness_hp_per_kg[i] = 0.0
		_next_threshold_index[i] = 0
		_is_initialized[i] = 0

# ─────────────────────────────────────────────────────────
# Public API

func setup(data: DataLayer) -> void:
	_data = data
	_index = data.index
	_grid_size = _index.size
	_allocate_arrays(_grid_size)
	if debug_log:
		print("[Dur] setup done. grid=", _grid_size)

## 셀 초기화/재설정: 타일 배치/교체 시 호출
## sid: 재질 식별자(int), mass_kg: 초기 질량(kg)
func reset_cell(cell: Vector2i, sid: int, mass_kg: float) -> void:
	if not _in_bounds(cell): return
	var idx := _idx(cell)

	var hardness := _get_hardness_for_sid(sid)
	_initial_mass_kg[idx] = max(0.0, mass_kg)
	_hardness_hp_per_kg[idx] = max(0.0, hardness)
	_max_hp[idx] = _initial_mass_kg[idx] * _hardness_hp_per_kg[idx]
	_hp[idx] = _max_hp[idx]
	_next_threshold_index[idx] = 0
	_is_initialized[idx] = 1
	#if debug_log and sid != 0:
		#print("[Dur] reset_cell cell=", cell, " sid=", sid, 
			#" mass_kg=", mass_kg, " hardness=", hardness, 
			#" → max_hp=", mass_kg * hardness)

	#if debug_log:
		#print("[Dur] reset_cell cell=", cell,
			#" sid=", sid,
			#" mass_kg=", _initial_mass_kg[idx],
			#" hardness=", _hardness_hp_per_kg[idx],
			#" max_hp=", _max_hp[idx])

	_emit_hp_changed(cell, idx)

## 타일 교체 시 편의용(외부 TileChange에서 호출 가능)
func on_tile_replaced(cell: Vector2i, _from_sid: int, to_sid: int, new_mass_kg: float, _reason: StringName = &"") -> void:
	if debug_log:
		print("[Dur] on_tile_replaced cell=", cell,
			" from=", _from_sid, " to=", to_sid,
			" mass_kg=", new_mass_kg, " reason=", _reason)
	reset_cell(cell, to_sid, new_mass_kg)

## 채굴/피해 적용(HP 단위)
func apply_damage(cell: Vector2i, amount_hp: float) -> void:
	if amount_hp <= 0.0: return
	if not _in_bounds(cell): return
	var idx := _idx(cell)
	if _is_initialized[idx] == 0:
		if debug_log:
			print("[Dur] apply_damage ignored: not initialized cell=", cell)
		return # 초기화 안 된 셀 무시
	if _max_hp[idx] <= EPS:
		if debug_log:
			print("[Dur] apply_damage ignored: max_hp≈0 cell=", cell)
		return       # 채굴 불가(경도=0 또는 질량=0)

	var hp_prev := _hp[idx]
	var hp_new: float = max(0.0, hp_prev - amount_hp)
	_hp[idx] = hp_new

	if debug_log:
		print("[Dur] dmg cell=", cell,
			" amount=", amount_hp,
			" hp ", hp_prev, "→", hp_new, " / max=", _max_hp[idx])

	# HP 변경 방송
	_emit_hp_changed(cell, idx)

	# 문턱 처리
	_process_threshold_cross(cell, idx, hp_prev, hp_new)

	# 파괴 처리
	if _hp[idx] <= EPS:
		if debug_log:
			print("[Dur] break emit cell=", cell)
		break_requested.emit(cell)

## UI/디버깅용 Getter
func get_hp(cell: Vector2i) -> float:
	if not _in_bounds(cell): return 0.0
	return _hp[_idx(cell)]

func get_max_hp(cell: Vector2i) -> float:
	if not _in_bounds(cell): return 0.0
	return _max_hp[_idx(cell)]

func get_hp_ratio(cell: Vector2i) -> float:
	if not _in_bounds(cell): return 0.0
	var idx := _idx(cell)
	if _max_hp[idx] <= EPS: return 0.0
	return clamp(_hp[idx] / _max_hp[idx], 0.0, 1.0)

# ─────────────────────────────────────────────────────────
# Internal

func _emit_hp_changed(cell: Vector2i, idx: int) -> void:
	hp_changed.emit(cell, _hp[idx], _max_hp[idx])

func _process_threshold_cross(cell: Vector2i, idx: int, hp_prev: float, hp_new: float) -> void:
	if _max_hp[idx] <= EPS:
		return

	var ratio_prev: float = clamp(hp_prev / _max_hp[idx], 0.0, 1.0)
	var ratio_new: float = clamp(hp_new / _max_hp[idx], 0.0, 1.0)
	var next_i := _next_threshold_index[idx]

	# 문턱은 내림차순으로 저장되어 있음.
	# 현재 next_i가 가리키는 문턱 값 이하로 내려갔으면,
	# 그 문턱 구간에 해당하는 '드롭 쿼터'를 순차적으로 요청한다.
	while next_i < _thresholds.size():
		var t := _thresholds[next_i]
		# ratio_new가 문턱(t) 이하로 내려갔는가?
		if ratio_new <= t + EPS:
			# 이전 문턱은 (next_i == 0 ? 1.0 : _thresholds[next_i - 1])
			var t_prev := 1.0 if next_i == 0 else _thresholds[next_i - 1]
			var quota_ratio: float = max(0.0, t_prev - t) # 이 구간에 할당된 질량 비율
			var chunk_mass := _initial_mass_kg[idx] * quota_ratio
			if chunk_mass > 0.0:
				if debug_log:
					print("[Dur] threshold cell=", cell,
						" t=", t, " t_prev=", t_prev,
						" quota_ratio=", quota_ratio,
						" chunk_mass_kg=", chunk_mass)
				threshold_chunk_requested.emit(cell, chunk_mass, t)
			next_i += 1
			_next_threshold_index[idx] = next_i
			# 다음 문턱도 동시에 뛰어넘었을 수 있으므로 루프 지속
		else:
			break

func _get_hardness_for_sid(sid: int) -> float:
	# Inspector에서 키를 문자열로 넣는 걸 권장했으므로 우선 문자열 키 조회
	var k := str(sid)
	if hardness_by_sid.has(k):
		return float(hardness_by_sid[k])
	# 정수 키로도 시도(개발자가 코드에서 직접 넣었을 수도 있음)
	if hardness_by_sid.has(sid):
		return float(hardness_by_sid[sid])
	# 미정이면 0(채굴 불가)
	return 0.0

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y

func _idx(cell: Vector2i) -> int:
	return cell.y * _grid_size.x + cell.x
