## 셀 단위 질량 저장소 (더블 버퍼)
## 단위: milligram(㎎). 내부 저장/연산은 int64(mg) 기준.
extends BaseStore
class_name MassStore

signal mass_changed(cell: Vector2i)

const MG_PER_G  := 1_000
const MG_PER_KG := 1_000_000

var _read: PackedInt64Array = PackedInt64Array()
var _write: PackedInt64Array = PackedInt64Array()

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedInt64Array and initial.size() == n:
		_read = PackedInt64Array(initial)
	else:
		if initial is PackedInt64Array:
			push_error("[MassStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[MassStore.setup] initial type mismatch (%s). PackedInt64Array required; allocating empty buffer." % typeof(initial))
		_read = PackedInt64Array(); _read.resize(n); _read.fill(0)

	_write = PackedInt64Array(_read)

func begin_write() -> void:
	super.begin_write()

	_write.resize(0)
	_write.append_array(_read)

# ===== 커밋 =====
func commit() -> void: # read 버전을 write 버전으로 최신화(참조 스왑)
	if not _is_writing:
		push_warning("[MassStore.commit] not in writing state (ignored)")
		return

	# 1) 음수 보정
	_clamp_negatives_on_write()

	# 2) 합계 보존 검증(정수 mg → Δ는 0이어야 정상)
	var sum_r := _safe_sum(_read)
	var sum_w := _safe_sum(_write)
	var delta := sum_w - sum_r
	if delta != 0:
		push_warning("[MassStore] conservation violated: Δ=%d mg (r=%d, w=%d)" % [delta, sum_r, sum_w])

	# 3) 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp

	super.commit()

# ===== 쓰기 경로 =====
func add(i: int, dm_mg: int) -> void:
	if not _is_writing:
		push_warning("[MassStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_index(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return
	_write[i] += dm_mg
	emit_signal("mass_changed", _index.cell(i))

func set_by_index(i: int, m_mg: int) -> void:
	if not _is_writing:
		push_warning("[MassStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_index(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return
	_write[i] = m_mg
	emit_signal("mass_changed", _index.cell(i))

func set_cell(cell: Vector2i, m_mg: int) -> void:
	set_by_index(_index.idx(cell), m_mg)
	emit_signal("mass_changed", cell)

# ===== 읽기 경로 =====
func get_by_index(i: int) -> int:
	if not _index.in_bounds_index(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return 0
	return _read[i]

func get_mass_g(i: int) -> float:  return float(get_by_index(i)) / MG_PER_G
func get_mass_kg(i: int) -> float: return float(get_by_index(i)) / MG_PER_KG

func get_read() -> PackedInt64Array:      return _read
func get_raw_read() -> PackedInt64Array:  return _read
func get_raw_write() -> PackedInt64Array: return _write

# ===== 합계/보정 =====
func _safe_sum(arr: PackedInt64Array) -> int:
	var s: int = 0
	var overflow := false
	for i in arr.size():
		var v := arr[i]
		var ns := s + v
		# int64 오버플로 감지(부호 변화로 감지)
		if (v > 0 and s > 0 and ns < 0) or (v < 0 and s < 0 and ns > 0):
			overflow = true
		s = ns
	if overflow:
		push_warning("[MassStore] potential int64 overflow detected while summing")
	return s

func _clamp_negatives_on_write() -> int:
	var clamp_count := 0
	for i in _write.size():
		if _write[i] < 0:
			_write[i] = 0
			clamp_count += 1
	if clamp_count > 0:
		push_warning("[MassStore] clamp(negative)=%d" % clamp_count)
	return clamp_count


func sum() -> int:
	return _safe_sum(_read)

# ===== 총 질량 출력 =====
func print_total_mass() -> void:
	var total_mg := sum()
	var total_g := float(total_mg) / MG_PER_G
	var total_kg := float(total_mg) / MG_PER_KG

	print("[MassStore] total mass = %d mg (%.3f g, %.6f kg)" % [total_mg, total_g, total_kg])
