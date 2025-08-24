class_name MassStore
# 단위: milligram(㎎). 내부 저장/연산은 int64(mg) 기준.

const MG_PER_G  := 1000
const MG_PER_KG := 1000000

enum { STATE_READING, STATE_WRITING }
var _state := STATE_READING

var _index: GridIndex
var _read: PackedInt64Array = PackedInt64Array()
var _write: PackedInt64Array = PackedInt64Array()

func setup(index: GridIndex, initial: PackedInt64Array) -> void:
	_index = index
	if _index == null:
		push_error("[MassStore.setup] _index not set; call setup() first")
	var expected := index.size.x * index.size.y
	if initial.size() != expected:
		push_error("[MassStore.setup] size mismatch. expected=%d, got=%d" % [expected, initial.size()])
		_read = PackedInt64Array(); _read.resize(expected)
	else:
		_read = PackedInt64Array(initial)
	_write = PackedInt64Array(_read)
	_state = STATE_READING

func begin_write() -> void:
	_state = STATE_WRITING
	if _write.size() != _read.size():
		push_warning("[MassStore] resync buffers: read=%d write=%d -> write=%d" % [_read.size(), _write.size(), _read.size()])
		_write = PackedInt64Array(_read)
	else:
		for i in _read.size():
			_write[i] = _read[i]

# ===== 쓰기 경로 =====
func add(i: int, dm_mg: int) -> void:
	if _state != STATE_WRITING:
		push_warning("[MassStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_idx(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return
	_write[i] += dm_mg

func set_idx(i: int, m_mg: int) -> void:
	if _state != STATE_WRITING:
		push_warning("[MassStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_idx(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return
	_write[i] = m_mg

func set_cell(cell: Vector2i, m_mg: int) -> void:
	set_idx(_index.idx(cell), m_mg)

# ===== 읽기 경로 =====
func get_mass(i: int) -> int:
	if not _index.in_bounds_idx(i):
		push_warning("[MassStore] Out‑of‑Bounds cell ignored: idx=%d" % i)
		return 0
	return _read[i]

func get_mass_g(i: int) -> float:
	return float(get_mass(i)) / MG_PER_G

func get_mass_kg(i: int) -> float:
	return float(get_mass(i)) / MG_PER_KG

# ===== 오버플로 안전 합계 =====
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

# ===== 음수 클램프 =====
func _clamp_negatives_on_write() -> int:
	var clamp_count := 0
	for i in _write.size():
		if _write[i] < 0:
			_write[i] = 0
			clamp_count += 1
	if clamp_count > 0:
		push_warning("[MassStore] clamp(negative)=%d" % clamp_count)
	return clamp_count

# ===== 커밋/합계 =====
func commit() -> void: # read 버전을 write 버전으로 최신화(참조 스왑)
	if _state != STATE_WRITING:
		push_warning("[MassStore] commit called while not writing")
		return

	# 1) 음수 보정
	_clamp_negatives_on_write()

	# 2) 합계 보존 검증(정수 mg → Δ는 0이어야 정상)
	var sum_r := _safe_sum(_read)
	var sum_w := _safe_sum(_write)
	var delta := sum_w - sum_r
	if delta != 0:
		push_warning("[MassStore] conservation violated: Δ=%d mg (r=%d, w=%d)" % [delta, sum_r, sum_w])

	# 3) 참조 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	_state = STATE_READING

func sum() -> int:
	return _safe_sum(_read)

func get_read() -> PackedInt64Array:
	return _read

# ===== 총 질량 출력 =====
func print_total_mass() -> void:
	var total_mg := sum()
	var total_g := float(total_mg) / MG_PER_G
	var total_kg := float(total_mg) / MG_PER_KG

	print("[MassStore] total mass = %d mg (%.3f g, %.6f kg)" % [total_mg, total_g, total_kg])
