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
	super.setup(index)
	if _index == null: return
	var n := _index.size.x * _index.size.y
	if initial == null or initial.size() != n:
		push_error("[PhaseStore.setup] size mismatch. expected=%d, got=%d" % [n, initial.size()])
		_read = PackedByteArray(); _read.resize(n) # 기본 0(VACUUM)
	else:
		_read = PackedByteArray(initial)
	_write = PackedByteArray(_read)

func begin_write() -> void:
	super.begin_write()
	# 최신 읽기 스냅샷을 쓰기 버퍼로 복제
	if _write.size() != _read.size():
		_write = PackedByteArray(_read)
	else:
		for i in _read.size():
			_write[i] = _read[i]

func commit() -> void:
	if not is_writing():
		push_warning("[PhaseStore] commit while not writing (ignored)")
		return
	# 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()

# ── 조회 ────────────────────────────────────────────────
func get_phase(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		return Phase.VACUUM
	return _read[_index.idx(cell)]

func get_by_index(i: int) -> int:
	return _read[i]

func is_solid(cell: Vector2i) -> bool:  return get_phase(cell) == Phase.SOLID
func is_liquid(cell: Vector2i) -> bool: return get_phase(cell) == Phase.LIQUID
func is_gas(cell: Vector2i) -> bool:    return get_phase(cell) == Phase.GAS
func is_vacuum(cell: Vector2i) -> bool: return get_phase(cell) == Phase.VACUUM

func get_raw() -> PackedByteArray:      return _read        # 기존 호환
func get_raw_read() -> PackedByteArray: return _read
func get_raw_write() -> PackedByteArray: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_phase(cell: Vector2i, phase: int) -> void:
	if not is_writing():
		push_warning("[PhaseStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds_cell(cell):
		push_warning("[PhaseStore] out of bounds: %s" % [cell])
		return
	_write[_index.idx(cell)] = phase
	emit_signal("phase_changed", cell)

func set_by_index(i: int, phase: int) -> void:
	if not is_writing():
		push_warning("[PhaseStore] write without begin_write (ignored)")
		return
	_write[i] = phase
	# index→cell 역변환 신호가 필요하면 여기서 emit 고려(지금은 생략)
