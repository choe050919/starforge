class_name DataLayer

var index: GridIndex = GridIndex.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()

func setup(size: Vector2i, phases: PackedByteArray, masses: PackedFloat32Array) -> void:
	index.setup(size)
	phase.setup(index, phases)
	mass.setup(index, masses)
	_log_counts()
	_validate()

func _log_counts() -> void: # 각 phase마다 수를 세어 print
	var counts := [0, 0, 0, 0]
	var data := phase.get_raw()
	for i in data.size():
		counts[data[i]] += 1
	print("[DataLayer] SOLID=%d LIQUID=%d GAS=%d VACUUM=%d" % [counts[PhaseStore.SOLID], counts[PhaseStore.LIQUID], counts[PhaseStore.GAS], counts[PhaseStore.VACUUM]])

func _validate() -> void: # 오류 검증
	var p := phase.get_raw()
	var m := mass.get_read()
	var violations: int = 0
	for i in p.size():
		if p[i] == PhaseStore.SOLID and m[i] != 0.0:
			violations += 1
		elif m[i] > 0.0 and p[i] != PhaseStore.LIQUID:
			violations += 1
	if violations > 0:
		push_error("[DataLayer] invariant violations: %d" % violations)
	else:
		print("[DataLayer] invariants: OK")
