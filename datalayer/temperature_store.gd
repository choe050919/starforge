## 셀 단위 온도 저장소 (더블 버퍼)
## 단위: centiKelvin (cK = 0.01 K). 내부 저장/연산은 int32(cK) 기준.
extends BaseStore
class_name TemperatureStore

signal temperature_changed(cell: Vector2i)

const CK_PER_K := 100
const CK_0C := 27315 # 0 °C = 273.15 K = 27315 cK
const MIN_CK := 0 # 0 K = -273.15 °C
const MAX_CK := 15_000_000 # 150,000 K (안전 상한; 필요 시 조정)

var _read: PackedInt32Array = PackedInt32Array()
var _write: PackedInt32Array = PackedInt32Array()

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedInt32Array and initial.size() == n:
		_read = PackedInt32Array(initial)
	else:
		if initial is PackedInt32Array:
			push_error("[TemperatureStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[TemperatureStore.setup] initial type mismatch (%s). PackedInt32Array required; allocating empty buffer." % typeof(initial))
		_read = PackedInt32Array(); _read.resize(n); _read.fill(0)

	_write = PackedInt32Array(_read)

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
	return t >= MIN_CK and t <= MAX_CK

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i]

func get_by_cell(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		return -1
	return _read[_index.idx(cell)]

func get_raw_read() -> PackedInt32Array:  return _read
func get_raw_write() -> PackedInt32Array: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_index(i: int, temp: int) -> void:
	if not _is_writing:
		push_warning("[TemperatureStore.set_by_index] write without begin_write (ignored)")
		return
	if not is_valid_value(temp):
		push_warning("[TemperatureStore.set_by_index] invalid id: %d" % temp)
		return
	_write[i] = temp
	emit_signal("temperature_changed", _index.cell(i))

func replace_all(values: PackedInt32Array, reason: StringName = &"bulk_replace") -> void:
	var n := _index.size.x * _index.size.y
	if values.size() != n:
		push_error("[TemperatureStore.replace_all] size mismatch: need=%d, got=%d" % [n, values.size()])
		return

	# 대량 교체: per-cell temperature_changed를 쏘지 않음 (성능)
	var was_writing := _is_writing
	if not was_writing:
		begin_write()
	# _write를 통째로 교체(복제하여 외부 참조 차단)
	_write = values.duplicate()
	if not was_writing:
		commit()
	else:
		# 이미 외부에서 begin_write() 중이면 호출자가 commit()을 할 것으로 가정
		pass

# ── 합계/보정 ───────────────────────────────────────────
func _safe_sum(arr: PackedInt32Array) -> int:
	var s: int = 0
	var overflow := false
	for i in arr.size():
		var v := arr[i]
		var ns := s + v
		# int32 오버플로 감지(부호 변화로 감지)
		if (v > 0 and s > 0 and ns < 0) or (v < 0 and s < 0 and ns > 0):
			overflow = true
		s = ns
	if overflow:
		push_warning("[TemperatureStore] potential int32 overflow detected while summing")
	return s

func _clamp_negatives_on_write() -> int: # ??????????????
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

# ── 도구 ────────────────────────────────────────────────
func print_total_temperature() -> void:
	var total_ck := sum()
	var total_k := total_ck / CK_PER_K
	var total_c := (total_ck + CK_0C) / CK_PER_K

	print("[TemperatureStore] total temperature = %d cK (%.3f K, %.6f °C)" % [total_ck, total_k, total_c])
