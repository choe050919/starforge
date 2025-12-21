extends RefCounted
class_name BaseStore

signal committed()
signal write_state_changed(is_writing: bool)

var _index: GridIndex
var _is_writing := false
var _cls: String

func setup(index: GridIndex, initial: Variant = null) -> void:
	_cls = get_class()
	if index == null:
		push_error("[%s.setup] GridIndex not set" % _cls); return
	_index = index

func begin_write() -> void:
	if _is_writing:
		push_warning("[%s.begin_write] begin_write called twice" % _cls); return
	_is_writing = true
	write_state_changed.emit(true)

func commit() -> void:
	if not _is_writing:
		push_warning("[%s.commit] commit without begin_write (ignored)" % _cls)
		return
	_do_commit()
	_is_writing = false
	write_state_changed.emit(false)
	committed.emit()

## 서브클래스에서 오버라이드. 버퍼 스왑 등 커밋 시 실제 작업.
func _do_commit() -> void:
	pass

func abort() -> void:
	_is_writing = false
	write_state_changed.emit(false)
