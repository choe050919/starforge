extends BaseStore
class_name PhaseStore

signal phase_changed(cell: Vector2i) # 셀 1개 변경

enum Phase {
	VACUUM = 0,
	SOLID  = 1,
	LIQUID = 2,
	GAS    = 3
}

var _read: PackedByteArray = PackedByteArray()
var _write: PackedByteArray = PackedByteArray()

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := _index.size.x * _index.size.y
	if initial is PackedByteArray and initial.size() == n:
		_read = PackedByteArray(initial)
	else:
		if initial is PackedByteArray:
			push_error("[PhaseStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[PhaseStore.setup] initial type mismatch (%s). PackedByteArray required; allocating empty buffer." % typeof(initial))
		_read = PackedByteArray(); _read.resize(n); _read.fill(0)

	_write = PackedByteArray(_read)

func begin_write() -> void:
	super.begin_write()

	_write.resize(0)
	_write.append_array(_read)

func commit() -> void:
	if not _is_writing:
		push_warning("[PhaseStore.commit] not in writing state (ignored)")
		return
	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()

func is_valid_id(id: int) -> bool:
	return id >= int(Phase.VACUUM) and id <= int(Phase.GAS)

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i]

func get_phase(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		return Phase.VACUUM
	return _read[_index.idx(cell)]

func is_solid(cell: Vector2i) -> bool:  return get_phase(cell) == Phase.SOLID
func is_liquid(cell: Vector2i) -> bool: return get_phase(cell) == Phase.LIQUID
func is_gas(cell: Vector2i) -> bool:    return get_phase(cell) == Phase.GAS
func is_vacuum(cell: Vector2i) -> bool: return get_phase(cell) == Phase.VACUUM

func get_read() -> PackedByteArray:      return _read
func get_raw_read() -> PackedByteArray:  return _read
func get_raw_write() -> PackedByteArray: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_index(i: int, phase: int) -> void:
	if not _is_writing:
		push_warning("[PhaseStore] write without begin_write (ignored)")
		return
	if not is_valid_id(phase):
		push_warning("[PhaseStore.set_by_idx] invalid id: %d" % phase)
		return
	_write[i] = phase
	# index→cell 역변환 신호가 필요하면 여기서 emit 고려(지금은 생략)

func set_phase(cell: Vector2i, phase: int) -> void:
	if not _is_writing:
		push_warning("[PhaseStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_cell(cell):
		push_warning("[PhaseStore] out of bounds: %s" % [cell])
		return
	if not is_valid_id(phase):
		push_warning("[PhaseStore] invalid id: %d" % phase)
		return
	_write[_index.idx(cell)] = phase
	emit_signal("phase_changed", cell)
