extends RefCounted
class_name SubstanceStore

enum SubstanceId {
	VACUUM  = 0,
	ICE     = 1,
	GROUND  = 2,
	URANIUM = 3,
	WATER   = 4,
}

enum { STATE_READING, STATE_WRITING }

var _state := STATE_READING
var _index: GridIndex
var _read: PackedInt32Array
var _write: PackedInt32Array

func setup(index: GridIndex, initial: PackedInt32Array) -> void:
	_index = index
	if _index == null:
		push_error("[SubstanceStore.setup] GridIndex not set")
		return
	var n := index.size.x * index.size.y
	_read  = PackedInt32Array(); _read.resize(n)
	_write = PackedInt32Array(); _write.resize(n)
	if initial != null and initial.size() == n:
		for i in n:
			_read[i] = initial[i]
	else:
		# 기본값: VACUUM
		for i in n:
			_read[i] = SubstanceId.VACUUM
	_write = PackedInt32Array(_read)
	_state = STATE_READING

func begin_write() -> void:
	_state = STATE_WRITING
	_write = PackedInt32Array(_read)

func commit() -> void:
	if _state != STATE_WRITING:
		push_warning("[SubstanceStore.commit] not in writing state (ignored)")
		return
	_read = PackedInt32Array(_write)
	_state = STATE_READING

func is_valid_id(id: int) -> bool:
	return id >= int(SubstanceId.VACUUM) and id <= int(SubstanceId.WATER)

func get_by_idx(i: int) -> int:
	return _read[i]

func get_substance(cell: Vector2i) -> int:
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.get] out of bounds: %s" % [cell])
		return SubstanceId.VACUUM
	return _read[_index.idx(cell)]

func set_by_idx(i: int, mat: int) -> void:
	if _state != STATE_WRITING:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_by_idx] invalid id: %d" % mat)
		return
	_write[i] = mat

func set_substance(cell: Vector2i, mat: int) -> void:
	if _state != STATE_WRITING:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.set_substance] out of bounds: %s" % [cell])
		return
	if not is_valid_id(mat):
		push_warning("[SubstanceStore.set_substance] invalid id: %d" % mat)
		return
	_write[_index.idx(cell)] = mat
