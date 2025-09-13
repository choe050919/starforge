## 단위: W/m² (irradiance, 복사조도)
## - 값은 0 이상 (음수 불가)
extends BaseStore
class_name LightStore

signal light_changed(cell: Vector2i)

var _read: PackedFloat32Array = PackedFloat32Array()
var _write: PackedFloat32Array = PackedFloat32Array()

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedFloat32Array and initial.size() == n:
		_read = PackedFloat32Array(initial)
	else:
		if initial is PackedFloat32Array:
			push_error("[LightStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[LightStore.setup] initial type mismatch (%s). PackedFloat32Array required; allocating empty buffer." % typeof(initial))
		_read = PackedFloat32Array(); _read.resize(n); _read.fill(0)

	_write = PackedFloat32Array(_read)

func begin_write() -> void:
	super.begin_write()

	_write.resize(0)
	_write.append_array(_read)

func commit() -> void:
	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()

func is_valid_value(t: int) -> bool:
	return t >= 0

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i]

func get_by_cell(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		return -1
	return _read[_index.idx(cell)]

func get_raw_read() -> PackedFloat32Array:  return _read
func get_raw_write() -> PackedFloat32Array: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_index(i: int, value: int) -> void:
	if not _is_writing:
		push_warning("[PhaseStore] write without begin_write (ignored)")
		return
	if not is_valid_value(value):
		push_warning("[PhaseStore.set_by_idx] invalid id: %d" % value)
		return
	_write[i] = value
