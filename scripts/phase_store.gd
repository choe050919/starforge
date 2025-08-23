class_name PhaseStore

signal phase_changed(cell: Vector2i) # 셀 1개 변경

const VACUUM := 0
const SOLID := 1
const LIQUID := 2
const GAS := 3

var _index: GridIndex
var _data: PackedByteArray = PackedByteArray()

func setup(index: GridIndex, initial: PackedByteArray) -> void:
	_index = index
	var expected := index.size.x * index.size.y
	if initial.size() != expected:
		push_error("[PhaseStore.setup] size mismatch. expected=%d, got=%d" % [expected, initial.size()])
		_data = PackedByteArray()
		_data.resize(expected) # 어떤 용도지?
		return
	_data = PackedByteArray(initial)

func get_phase(cell: Vector2i) -> int:
	if not _index.in_bounds(cell):
		return VACUUM
	return _data[_index.idx(cell)]

func get_by_index(i: int) -> int:
	return _data[i]

func is_solid(cell: Vector2i) -> bool:
	return get_phase(cell) == SOLID

func is_liquid(cell: Vector2i) -> bool:
	return get_phase(cell) == LIQUID

func is_gas(cell: Vector2i) -> bool:
	return get_phase(cell) == GAS

func is_vacuum(cell: Vector2i) -> bool:
	return get_phase(cell) == VACUUM

func get_raw() -> PackedByteArray: # data 전체 반환
	return _data

func _set_internal(cell: Vector2i, phase: int) -> void:
	if not _index.in_bounds(cell):
		push_error("[PhaseStore] wrong Vector2i value")
		return
	_data[_index.idx(cell)] = phase
	emit_signal("phase_changed", cell)
