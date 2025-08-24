extends BaseStore
class_name SubstanceStore

enum SubstanceId {
	VACUUM  = 0,
	ICE     = 1,
	GROUND  = 2,
	URANIUM = 3,
	WATER   = 4,
}

var _read: PackedInt32Array = PackedInt32Array()
var _write: PackedInt32Array = PackedInt32Array()

enum { STATE_READING, STATE_WRITING }

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)
	if _index == null:
		push_error("[SubstanceStore.setup] GridIndex not set")
		return

	var n := index.size.x * index.size.y

	_read = PackedInt32Array()
	_read.resize(n)

	if initial is PackedInt32Array and initial.size() == n:
		for i in n:
			_read[i] = initial[i]
	else:
		if initial != null and initial is PackedInt32Array and initial.size() != n:
			push_error("[SubstanceStore.setup] size mismatch. expected=%d, got=%d" % [n, initial.size()])
		# 기본값: VACUUM
		for i in n:
			_read[i] = SubstanceId.VACUUM

	_write = PackedInt32Array(_read)

func begin_write() -> void:
	super.begin_write()
	# 최신 읽기 스냅샷을 쓰기 버퍼로 복제
	if _write.size() != _read.size():
		_write = PackedInt32Array(_read)
	else:
		for i in _read.size():
			_write[i] = _read[i]

func commit() -> void:
	if not is_writing():
		push_warning("[SubstanceStore.commit] not in writing state (ignored)")
		return
	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()

# ── 조회 ────────────────────────────────────────────────
func is_valid_id(id: int) -> bool:
	return id >= int(SubstanceId.VACUUM) and id <= int(SubstanceId.WATER)

func get_by_idx(i: int) -> int:
	return _read[i]

func get_substance(cell: Vector2i) -> int:
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.get] out of bounds: %s" % [cell])
		return SubstanceId.VACUUM
	return _read[_index.idx(cell)]

func get_raw_read() -> PackedInt32Array:  return _read
func get_raw_write() -> PackedInt32Array: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_idx(i: int, mat: int) -> void:
	if not is_writing():
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_by_idx] invalid id: %d" % mat)
		return
	_write[i] = mat

func set_substance(cell: Vector2i, mat: int) -> void:
	if not is_writing():
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.set_substance] out of bounds: %s" % [cell])
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_substance] invalid id: %d" % mat)
		return
	_write[_index.idx(cell)] = mat
