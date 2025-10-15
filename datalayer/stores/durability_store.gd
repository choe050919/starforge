## DurabilityStore
## 
## 셀별 HP(내구도) 데이터를 저장하는 Store.
## HP는 자주 변경되므로 더블 버퍼링을 사용하고,
## max_hp, hardness 등 초기화 후 불변인 값들은 단일 버퍼로 관리.
##
## [b]더블 버퍼:[/b] _hp (채굴 피해로 자주 변경)
## [b]단일 버퍼:[/b] max_hp, initial_mass_kg, hardness, threshold_index (초기화 후 거의 불변)
extends BaseStore
class_name DurabilityStore

signal hp_changed(cell: Vector2i, hp: float, max_hp: float)

# ── HP: 더블 버퍼 ──────────────────────────────────────────
var _hp_read: PackedFloat32Array = PackedFloat32Array()
var _hp_write: PackedFloat32Array = PackedFloat32Array()

# ── 나머지: 단일 버퍼 ──────────────────────────────────────
var _max_hp: PackedFloat32Array = PackedFloat32Array()
var _initial_mass_kg: PackedFloat32Array = PackedFloat32Array()
var _hardness_hp_per_kg: PackedFloat32Array = PackedFloat32Array()
var _next_threshold_index: PackedInt32Array = PackedInt32Array()
var _is_initialized: PackedByteArray = PackedByteArray()

# ── 설정 ───────────────────────────────────────────────────
## 재질별 경도 테이블 (HP per kg)
# TODO 임시 처리!!
var hardness_by_sid := {
	"0": 0.0,       # VACUUM (채굴 불가)
	"10001": 30.0,  # ICE
	"10002": 20.0,  # SOIL
	"10003": 120.0, # URANIUM
	"10004": 80.0,  # COPPER
	"50001": 10.0,  # LADDER (쉽게 제거 가능)
}

# ── 상수 ───────────────────────────────────────────────────
const EPS := 1e-6

# ══════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)
	
	var n := index.size.x * index.size.y
	
	# HP 더블 버퍼 초기화
	_hp_read.resize(n)
	_hp_read.fill(0.0)
	_hp_write = PackedFloat32Array(_hp_read)
	
	# 나머지 단일 버퍼 초기화
	_max_hp.resize(n)
	_max_hp.fill(0.0)
	
	_initial_mass_kg.resize(n)
	_initial_mass_kg.fill(0.0)
	
	_hardness_hp_per_kg.resize(n)
	_hardness_hp_per_kg.fill(0.0)
	
	_next_threshold_index.resize(n)
	_next_threshold_index.fill(0)
	
	_is_initialized.resize(n)
	_is_initialized.fill(0)

func begin_write() -> void:
	super.begin_write()
	
	# HP만 복사
	_hp_write.resize(0)
	_hp_write.append_array(_hp_read)

func commit() -> void:
	if not _is_writing:
		push_warning("[DurabilityStore.commit] not in writing state (ignored)")
		return
	
	# HP 버퍼 스왑
	var tmp := _hp_read
	_hp_read = _hp_write
	_hp_write = tmp
	
	super.commit()

# ══════════════════════════════════════════════════════════════
# Read API
# ══════════════════════════════════════════════════════════════

func get_hp_by_index(i: int) -> float:
	if not _index.in_bounds_index(i):
		return 0.0
	return _hp_read[i]

func get_hp(cell: Vector2i) -> float:
	if not _index.in_bounds_cell(cell):
		return 0.0
	return _hp_read[_index.idx(cell)]

func get_max_hp(cell: Vector2i) -> float:
	if not _index.in_bounds_cell(cell):
		return 0.0
	return _max_hp[_index.idx(cell)]

func get_hp_ratio(cell: Vector2i) -> float:
	if not _index.in_bounds_cell(cell):
		return 0.0
	var idx := _index.idx(cell)
	if _max_hp[idx] <= EPS:
		return 0.0
	return clamp(_hp_read[idx] / _max_hp[idx], 0.0, 1.0)

func get_initial_mass_kg(cell: Vector2i) -> float:
	if not _index.in_bounds_cell(cell):
		return 0.0
	return _initial_mass_kg[_index.idx(cell)]

func get_hardness(cell: Vector2i) -> float:
	if not _index.in_bounds_cell(cell):
		return 0.0
	return _hardness_hp_per_kg[_index.idx(cell)]

func get_next_threshold_index(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		return 0
	return _next_threshold_index[_index.idx(cell)]

func is_initialized(cell: Vector2i) -> bool:
	if not _index.in_bounds_cell(cell):
		return false
	return _is_initialized[_index.idx(cell)] != 0

func get_raw_hp_read() -> PackedFloat32Array:
	return _hp_read

func get_raw_hp_write() -> PackedFloat32Array:
	return _hp_write

# ══════════════════════════════════════════════════════════════
# Write API
# ══════════════════════════════════════════════════════════════

func set_hp_by_index(i: int, hp: float) -> void:
	if not _is_writing:
		push_warning("[DurabilityStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_index(i):
		return
	
	_hp_write[i] = max(0.0, hp)
	hp_changed.emit(_index.cell(i), _hp_write[i], _max_hp[i])

func set_hp(cell: Vector2i, hp: float) -> void:
	if not _index.in_bounds_cell(cell):
		return
	set_hp_by_index(_index.idx(cell), hp)

func add_hp_damage(cell: Vector2i, damage: float) -> void:
	if not _index.in_bounds_cell(cell):
		return
	var idx := _index.idx(cell)
	set_hp_by_index(idx, _hp_read[idx] - damage)

func set_next_threshold_index(cell: Vector2i, index: int) -> void:
	if not _index.in_bounds_cell(cell):
		return
	_next_threshold_index[_index.idx(cell)] = index

func increment_threshold_index(cell: Vector2i) -> void:
	if not _index.in_bounds_cell(cell):
		return
	var idx := _index.idx(cell)
	_next_threshold_index[idx] += 1

# ══════════════════════════════════════════════════════════════
# Cell Initialization
# ══════════════════════════════════════════════════════════════

## 셀 초기화: 새 타일 배치 시 호출
func reset_cell(cell: Vector2i, sid: int, mass_kg: float, hardness: float = -1.0) -> void:
	if not _index.in_bounds_cell(cell):
		return
	
	# hardness가 -1이면 테이블에서 조회
	var h := hardness
	if h < 0.0:
		h = _get_hardness_for_sid(sid)
	
	var idx := _index.idx(cell)
	
	_initial_mass_kg[idx] = max(0.0, mass_kg)
	_hardness_hp_per_kg[idx] = max(0.0, h)
	_max_hp[idx] = _initial_mass_kg[idx] * _hardness_hp_per_kg[idx]
	
	# HP는 더블 버퍼 고려
	if _is_writing:
		_hp_write[idx] = _max_hp[idx]
	else:
		_hp_read[idx] = _max_hp[idx]
	
	_next_threshold_index[idx] = 0
	_is_initialized[idx] = 1
	
	hp_changed.emit(cell, _max_hp[idx], _max_hp[idx])

## 셀 초기화 해제: 타일 파괴 시 호출
func clear_cell(cell: Vector2i) -> void:
	if not _index.in_bounds_cell(cell):
		return
	
	var idx := _index.idx(cell)
	
	_initial_mass_kg[idx] = 0.0
	_hardness_hp_per_kg[idx] = 0.0
	_max_hp[idx] = 0.0
	
	# HP는 더블 버퍼 고려
	if _is_writing:
		_hp_write[idx] = 0.0
	else:
		_hp_read[idx] = 0.0
	
	_next_threshold_index[idx] = 0
	_is_initialized[idx] = 0
	
	hp_changed.emit(cell, 0.0, 0.0)

# ══════════════════════════════════════════════════════════════
# Internal Helpers
# ══════════════════════════════════════════════════════════════

func _get_hardness_for_sid(sid: int) -> float:
	# 문자열 키로 조회
	var k := str(sid)
	if hardness_by_sid.has(k):
		return float(hardness_by_sid[k])
	# 정수 키로도 시도
	if hardness_by_sid.has(sid):
		return float(hardness_by_sid[sid])
	# 미등록이면 0 (채굴 불가)
	return 0.0

func bind_hardness_table(table: Dictionary) -> void:
	hardness_by_sid = table
