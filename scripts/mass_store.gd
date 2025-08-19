class_name MassStore

var _index: GridIndex
var _read: PackedFloat32Array = PackedFloat32Array()
var _write: PackedFloat32Array = PackedFloat32Array()

func setup(index: GridIndex, initial: PackedFloat32Array) -> void:
	_index = index
	var expected := index.size.x * index.size.y
	if initial.size() != expected:
		push_error("MassStore.setup: size mismatch. expected=%d, got=%d" % [expected, initial.size()])
		_read = PackedFloat32Array(); _read.resize(expected)
	else:
		_read = PackedFloat32Array(initial)
	_write = PackedFloat32Array(_read)

func begin_write() -> void:
	if _write.size() != _read.size():
		_write = PackedFloat32Array(_read)
	else:
		for i in _read.size():
			_write[i] = _read[i]

func add(i: int, dm: float) -> void:
	_write[i] += dm

func set_mass(i: int, m: float) -> void:
	_write[i] = m

func commit() -> void: # read 버전을 write 버전으로 최신화
	var tmp := _read
	_read = _write
	_write = tmp

func sum() -> float:
	var total: float = 0.0
	for i in _read.size():
		total += _read[i]
	return total

func get_read() -> PackedFloat32Array:
	return _read
