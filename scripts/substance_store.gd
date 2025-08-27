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

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedInt32Array and initial.size() == n:
		_read = PackedInt32Array(initial)
	else:
		if initial is PackedInt32Array:
			push_error("[SubstanceStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[SubstanceStore.setup] initial type mismatch (%s). PackedInt32Array required; allocating empty buffer." % typeof(initial))
		_read = PackedInt32Array(); _read.resize(n); _read.fill(0)

	_write = PackedInt32Array(_read)

func begin_write() -> void:
	super.begin_write()

	_write.resize(0)
	_write.append_array(_read)

func commit() -> void:
	if not _is_writing:
		push_warning("[SubstanceStore.commit] not in writing state (ignored)")
		return
	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()

func is_valid_id(id: int) -> bool:
	return id >= int(SubstanceId.VACUUM) and id <= int(SubstanceId.WATER)

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i]

func get_substance(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		push_warning("[SubstanceStore.get] out of bounds: %s" % [cell])
		return SubstanceId.VACUUM
	return _read[_index.idx(cell)]

func get_raw_read() -> PackedInt32Array:  return _read
func get_raw_write() -> PackedInt32Array: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_idx(i: int, mat: int) -> void:
	if not _is_writing:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_by_idx] invalid id: %d" % mat)
		return
	_write[i] = mat

func set_substance(cell: Vector2i, mat: int) -> void:
	if not _is_writing:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.set_substance] out of bounds: %s" % [cell])
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_substance] invalid id: %d" % mat)
		return
	_write[_index.idx(cell)] = mat
