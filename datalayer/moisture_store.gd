## - 각 타일의 토양 수분량(mg)을 Int32로 저장
## - begin_write/commit 더블버퍼, 배치 더티 인덱스 시그널
## - 합계(sum) 디버그, 간단 유틸(가산/클램프/마스크제로)
extends BaseStore
class_name MoistureStore

signal moisture_changed_batch(indices: PackedInt32Array)
signal version_changed(version: int)

var _read: PackedInt32Array = PackedInt32Array()
var _write: PackedInt32Array = PackedInt32Array()

# 더티 집계(중복 방지용 마스크)
var _dirty_mask: PackedByteArray = PackedByteArray()
var _version: int = 0

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedInt32Array and initial.size() == n:
		_read = PackedInt32Array(initial)
	else:
		if initial is PackedInt32Array:
			push_error("[MoistureStore.setup] size mismatch. n=%d, got=%d. Allocating empty buffer." % [n, initial.size()])
		elif initial != null:
			push_error("[MoistureStore.setup] initial type mismatch (%s). PackedInt32Array required; allocating empty buffer." % typeof(initial))
		_read = PackedInt32Array(); _read.resize(n); _read.fill(0)

	_write = PackedInt32Array(_read)

	_dirty_mask.resize(n)
	_dirty_mask.fill(0)
	_version = 0

func begin_write() -> void:
	super.begin_write()
	_write.resize(0)
	_write.append_array(_read)
	if _dirty_mask.size() != _read.size():
		_dirty_mask.resize(_read.size())
	_dirty_mask.fill(0)

func commit() -> void:
	# 변경 인덱스 배치 생성
	var changed := PackedInt32Array()
	var n := _read.size()
	changed.resize(0)
	for i in n:
		if _dirty_mask[i] == 1:
			changed.push_back(i)

	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp

	super.commit()

	# 시그널
	if changed.size() > 0:
		moisture_changed_batch.emit(changed)
	_version += 1
	version_changed.emit(_version)

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i] if (i >= 0 and i < _read.size()) else 0

func get_raw_read() -> PackedInt32Array:  return _read
func get_raw_write() -> PackedInt32Array: return _write

func get_version() -> int: return _version

# ── 쓰기(개별/가산) ───────────────────────────────────────
func set_by_index(i: int, moisture_mg: int) -> void:
	if not _is_writing:
		push_warning("[MoistureStore.set_by_index] write without begin_write (ignored)")
		return
	if i < 0 or i >= _write.size():
		push_warning("[MoistureStore.set_by_index] index out of range: %d" % i)
		return
	var v := moisture_mg
	if v < 0: v = 0
	if _write[i] == v:
		return
	_write[i] = v
	_dirty_mask[i] = 1

func add_delta(i: int, delta_mg: int) -> void:
	if not _is_writing:
		push_warning("[MoistureStore.add_delta] write without begin_write (ignored)")
		return
	if i < 0 or i >= _write.size():
		push_warning("[MoistureStore.add_delta] index out of range: %d" % i)
		return
	var old := _write[i]
	var v := old + delta_mg
	if v < 0: v = 0
	if v == old:
		return
	_write[i] = v
	_dirty_mask[i] = 1

# ── 배치 가산(선택) ───────────────────────────────────────
# indices[k], deltas[k] 쌍으로 적용. 길이 불일치면 공집합 처리.
func add_delta_many(indices: PackedInt32Array, deltas: PackedInt32Array) -> void:
	if not _is_writing:
		push_warning("[MoistureStore.add_delta_many] write without begin_write (ignored)")
		return
	var m: int = min(indices.size(), deltas.size())
	for k in m:
		var i := indices[k]
		if i < 0 or i >= _write.size():
			continue
		var old := _write[i]
		var v := old + deltas[k]
		if v < 0: v = 0
		if v != old:
			_write[i] = v
			_dirty_mask[i] = 1

# ── 디버그/검증 ───────────────────────────────────────────
# 현재 읽기 버퍼 기준 총합(mg)을 Int64로 반환 (질량 보존 확인용)
func sum_read_i64() -> int:
	var acc: int = 0
	for v in _read:
		# GDScript int는 64bit 정수, 오버플로 걱정 없음
		acc += v
	return acc

# 쓰기 버퍼 기준 총합(커밋 전 확인용)
func sum_write_i64() -> int:
	var acc: int = 0
	for v in _write:
		acc += v
	return acc

# ── 유틸(선택) ───────────────────────────────────────────
# (1) 용량 상한 클램프: capacity[i]가 존재하면 moisture<=capacity로 제한
#     begin_write 이후 호출해야 하며, 초과로 내려간 인덱스를 더티로 마킹
func clamp_to_capacity(capacity: PackedInt32Array) -> void:
	if not _is_writing:
		push_warning("[MoistureStore.clamp_to_capacity] must be called during writing")
		return
	var n: int = min(_write.size(), capacity.size())
	for i in n:
		var cap := capacity[i]
		if cap < 0: cap = 0
		var v := _write[i]
		if v > cap:
			_write[i] = cap
			_dirty_mask[i] = 1

# (2) 비토양 마스크에 따라 0으로 강제 (SoilViewStore 마스크와 함께 사용)
func zero_non_soil(soil_mask: PackedByteArray) -> void:
	if not _is_writing:
		push_warning("[MoistureStore.zero_non_soil] must be called during writing")
		return
	var n: int = min(_write.size(), soil_mask.size())
	for i in n:
		if soil_mask[i] == 0 and _write[i] != 0:
			_write[i] = 0
			_dirty_mask[i] = 1
