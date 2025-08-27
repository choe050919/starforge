extends BaseStore
class_name TemperatureStore
## 셀 단위 온도 저장소 (더블 버퍼)
## 단위: centiKelvin (cK = 0.01 K). 내부 저장/연산은 int32(cK) 기준.

const CK_PER_K := 100
const CK_0C := 27315 # 0 °C = 273.15 K = 27315 cK
const MIN_CK := 0 # 0 K = -273.15 °C
#const MAX_CK := 15_000_000 # 150,000 K (안전 상한; 필요 시 조정)

var _read: PackedInt32Array = PackedInt32Array()
var _write: PackedInt32Array = PackedInt32Array()

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)

	var n := index.size.x * index.size.y
	if initial is PackedInt32Array and initial.size() == n:
		_read = PackedInt32Array(initial)
	else:
		if initial is PackedInt32Array:
			push_error("[MassStore.setup] size mismatch. n=%d, got=%d.  Allocating empty buffer." % [n, initial.size()])
		else:
			push_error("[MassStore.setup] initial type mismatch (%s). PackedInt32Array required; allocating empty buffer." % typeof(initial))
		_read = PackedInt32Array(); _read.resize(n); _read.fill(0)

	_write = PackedInt32Array(_read)

func begin_write() -> void:
	super.begin_write()

	_write.resize(0)
	_write.append_array(_read)

func commit() -> void:
	if not _is_writing:
		push_warning("[TemperatureStore.commit] not in writing state (ignored)")
		return
	# 스왑
	var tmp := _read
	_read = _write
	_write = tmp
	super.commit()
