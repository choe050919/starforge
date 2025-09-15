## - 토양 여부 마스크(0/1)만 저장 (PackedByteArray)
## - 토양 인덱스 목록은 파생 캐시로 유지(lazy 재생성)
extends BaseStore
class_name SoilViewStore

signal soil_changed_batch(added: PackedInt32Array, removed: PackedInt32Array)
signal version_changed(version: int)

var _read: PackedByteArray = PackedByteArray()
var _write: PackedByteArray = PackedByteArray()

# 파생 캐시: 토양 인덱스
var _indices: PackedInt32Array = PackedInt32Array()
var _indices_dirty := true

# 커밋 시 배치 변경 집계
var _dirty_added: PackedInt32Array = PackedInt32Array()
var _dirty_removed: PackedInt32Array = PackedInt32Array()

## 간단 버전 카운터(변경 탐지용)
var _version: int = 0

func setup(index: GridIndex, initial: Variant = null) -> void:
	super.setup(index, initial)
	var n := index.size.x * index.size.y

	if initial is PackedByteArray and initial.size() == n:
		_read = PackedByteArray(initial)
	else:
		if initial is PackedByteArray:
			push_error("[SoilViewStore.setup] size mismatch. n=%d, got=%d. Allocating empty mask." % [n, initial.size()])
		elif initial != null:
			push_error("[SoilViewStore.setup] initial type mismatch (%s). PackedByteArray required; allocating empty mask." % typeof(initial))
		_read = PackedByteArray(); _read.resize(n); _read.fill(0)

	_write = PackedByteArray(_read) # 초기 쓰기 버퍼 동기화
	_indices.resize(0)
	_indices_dirty = true
	_dirty_added.resize(0)
	_dirty_removed.resize(0)
	_version = 0

# ── 쓰기 사이클 ───────────────────────────────────────────
func begin_write() -> void:
	super.begin_write()
	_write.resize(0)
	_write.append_array(_read)
	_dirty_added.resize(0)
	_dirty_removed.resize(0)

func commit() -> void:
	super.commit()

	# 변경점 집계(added/removed) 계산
	var n := _read.size()
	var added := PackedInt32Array()
	var removed := PackedInt32Array()

	for i in n:
		var o := _read[i] == 1
		var v := _write[i] == 1
		if o != v:
			if v: added.push_back(i)
			else: removed.push_back(i)

	# 버퍼 스왑
	var tmp := _read
	_read = _write
	_write = tmp

	_indices_dirty = _indices_dirty or (added.size() > 0 or removed.size() > 0)

	# 배치 시그널 & 버전 증가(소비자 전체 리프레시 트리거에 유용)
	if added.size() > 0 or removed.size() > 0:
		soil_changed_batch.emit(added, removed)
	_version += 1
	version_changed.emit(_version)

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return 1 if (i >= 0 and i < _read.size() and _read[i] == 1) else 0

func is_soil(i: int) -> bool:
	return i >= 0 and i < _read.size() and _read[i] == 1

func get_raw_read() -> PackedByteArray:  return _read
func get_raw_write() -> PackedByteArray: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_index(i: int, is_soil_flag: int) -> void:
	if not _is_writing:
		push_warning("[SoilViewStore.set_by_index] write without begin_write (ignored)")
		return
	if i < 0 or i >= _write.size():
		push_warning("[SoilViewStore.set_by_index] index out of range: %d" % i)
		return

	var v := 1 if (is_soil_flag != 0) else 0
	if _write[i] == v:
		return
	_write[i] = v
	# 인덱스 캐시는 커밋에서 일괄 더티 처리됨

# ── 인덱스 파생 캐시 ──────────────────────────────────────
func get_indices() -> PackedInt32Array:
	if _indices_dirty:
		_rebuild_indices()
	return _indices

func count_soil() -> int:
	if _indices_dirty:
		_rebuild_indices()
	return _indices.size()

func _rebuild_indices() -> void:
	var n := _read.size()
	var cnt := 0
	for i in n:
		if _read[i] == 1:
			cnt += 1

	_indices.resize(cnt)
	var k := 0
	for i in n:
		if _read[i] == 1:
			_indices[k] = i
			k += 1

	_indices_dirty = false


# ── 유틸: 전량 리빌드(월드 로드/대량 변경) ───────────────
# fn_is_soil: Callable(sid:int)->bool  또는 (i:int)->bool
func rebuild_from_substances(substance_store: SubstanceStore, fn_is_soil: Callable) -> void:
	var sid := substance_store.get_raw_read()
	var n := sid.size()
	begin_write()
	for i in n:
		var is_soil := false
		if fn_is_soil.is_valid():
			if fn_is_soil.get_argument_count() == 1:
				is_soil = bool(fn_is_soil.call(int(sid[i])))
			else:
				is_soil = bool(fn_is_soil.call(i))
		set_by_index(i, 1 if is_soil else 0)
	commit()
	_indices_dirty = true  # 안전망

# ── 메타 ──────────────────────────────────────────────────
func get_version() -> int:
	return _version
