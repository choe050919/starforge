extends RefCounted
class_name BaseStore

signal committed()
signal write_state_changed(is_writing: bool)

var _index: GridIndex
var _is_writing := false

func setup(index: GridIndex, initial: Variant = null) -> void:
	_index = index
	if _index  == null: push_error("[BaseStore.setup] GridIndex not set"); return
	if initial == null: push_error("[BaseStore.setup] initial not set")  ; return

func begin_write() -> void:
	if _is_writing:
		push_warning("[BaseStore] begin_write called twice")
		return
	_is_writing = true
	emit_signal("write_state_changed", true)

func commit() -> void:
	if not _is_writing:
		push_warning("[BaseStore] commit without begin_write (ignored)")
		return
	_is_writing = false
	emit_signal("write_state_changed", false)
	emit_signal("committed")

func abort() -> void:
	_is_writing = false
	emit_signal("write_state_changed", false)

func is_writing() -> bool:
	return _is_writing
