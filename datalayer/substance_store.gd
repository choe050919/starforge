extends BaseStore
class_name SubstanceStore

## 룰 캐시(유효 sid 판정/디버그에만 사용)
var _rules: SubstanceRuleCache = null
## 기본 채움값(예: JSON의 vacuum sid). 미설정 시 0.
var _vacuum_sid: int = 0
## 과도한 로그를 막기 위한 1회 경고 기억
var _warned_invalid: Dictionary = {}

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rules = cache

func set_vacuum_sid(sid: int) -> void:
	_vacuum_sid = sid

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

# ── 유효성 ───────────────────────────────────────────────
## 룰 캐시가 있으면 등록 여부로 판정, 없으면 0 이상이면 통과(개발 초반 관용)
func _is_valid_sid(sid: int) -> bool:
	if _rules != null:
		return _rules.phase_of_sid.has(sid)
	return sid >= 0

func _warn_invalid_once(sid: int, where: String) -> void:
	if _warned_invalid.has(sid):
		return
	_warned_invalid[sid] = true
	push_warning("[SubstanceStore.%s] unregistered sid: %d (once)" % [where, sid])

# ── 읽기 ────────────────────────────────────────────────
func get_by_index(i: int) -> int:
	return _read[i]

func get_by_cell(cell: Vector2i) -> int:
	if not _index.in_bounds_cell(cell):
		push_warning("[SubstanceStore.get_by_cell] out of bounds: %s" % [cell])
		return _vacuum_sid
	return _read[_index.idx(cell)]

func get_raw_read() -> PackedInt32Array:  return _read
func get_raw_write() -> PackedInt32Array: return _write

# ── 쓰기 ────────────────────────────────────────────────
func set_by_index(i: int, sid: int) -> void:
	if not _is_writing:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not _is_valid_sid(sid):
		_warn_invalid_once(sid, "set_by_index")
		return
	_write[i] = sid

func set_substance(cell: Vector2i, sid: int) -> void:
	if not _is_writing:
		push_warning("[SubstanceStore] write without begin_write (ignored)")
		return
	if not _index.in_bounds(cell):
		push_warning("[SubstanceStore.set_substance] out of bounds: %s" % [cell])
		return
	if not _is_valid_sid(sid):
		_warn_invalid_once(sid, "set_substance")
		return
	_write[_index.idx(cell)] = sid

## (옵션) 디버그 편의
func get_vacuum_sid() -> int:
	return _vacuum_sid
