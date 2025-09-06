extends RefCounted
class_name BaseStore

signal committed()
signal write_state_changed(is_writing: bool)

var _index: GridIndex
var _is_writing := false
var cls: String

func setup(index: GridIndex, initial: Variant = null) -> void:
	cls = get_class()
	if index   == null: push_error("[%s.setup] GridIndex not set" % cls); return
	if initial == null: push_error("[%s.setup] initial not set" % cls);   return
	_index = index

func begin_write() -> void:
	if _is_writing:
		push_warning("[%s.begin_write] begin_write called twice" % cls); return
	_is_writing = true
	emit_signal("write_state_changed", true)

func commit() -> void:
	if not _is_writing:
		push_warning("[%s.commit] commit without begin_write (ignored)" % cls)
		return
	_is_writing = false
	emit_signal("write_state_changed", false)
	emit_signal("committed")

func abort() -> void:
	_is_writing = false
	emit_signal("write_state_changed", false)

#func is_writing() -> bool:
	#return _is_writing

# ── 헬퍼 ────────────────────────────────────────────────
