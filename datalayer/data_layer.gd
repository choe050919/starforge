class_name DataLayer

var index: GridIndex = GridIndex.new()
var substance: SubstanceStore = SubstanceStore.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()
var temperature: TemperatureStore = TemperatureStore.new()
var moisture: MoistureStore = MoistureStore.new()
var soil_view: SoilViewStore = SoilViewStore.new()
var hydro_field: HydrologyField = HydrologyField.new()

func setup(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	masses: PackedInt64Array,
	temperatures: PackedInt32Array,
	hydro_cache: HydrologyCache
) -> void:
	index.setup(size)
	substance.setup(index, substances)
	phase.setup(index, phases)
	mass.setup(index, masses)
	temperature.setup(index, temperatures)

	moisture.setup(index)
	soil_view.setup(index)

	_log_counts()
	_validate()

# ───────────────────────────────────────────────────────────────
# 프레임 경계 (쓰기 한정 구간)
func begin_frame_write() -> void:
	phase.begin_write()
	mass.begin_write()
	substance.begin_write()

func commit_all() -> void:
	# 필요 시 파생 캐시/마스크 갱신 순서 고려(지금은 단순 커밋)
	phase.commit()
	mass.commit()
	substance.commit()

# ───────────────────────────────────────────────────────────────
# 각 phase 수 집계
func _log_counts() -> void:
	var counts := [0, 0, 0, 0]
	var data := phase.get_read()
	for i in data.size():
		counts[data[i]] += 1
	print("[DataLayer] SOLID=%d LIQUID=%d GAS=%d VACUUM=%d" % [counts[PhaseStore.Phase.SOLID], counts[PhaseStore.Phase.LIQUID], counts[PhaseStore.Phase.GAS], counts[PhaseStore.Phase.VACUUM]])

# 무결성 검증(기존 + 물질/phase 일관성 체크 옵션)
func _validate() -> void:
	var p := phase.get_read()
	var m := mass.get_read()
	var violations: int = 0
	for i in p.size():
		match p[i]:
			PhaseStore.Phase.VACUUM:
				if m[i] != 0:
					violations += 1
			PhaseStore.Phase.LIQUID:
				if m[i] <= 0:
					violations += 1
			PhaseStore.Phase.SOLID:
				if m[i] <= 0:
					violations += 1
			PhaseStore.Phase.GAS:
				# 현재 가스 질량은 추적하지 않는다고 가정
				if m[i] != 0:
					violations += 1
			_:
				pass
	if violations > 0:
		push_error("[DataLayer] invariant violations: %d" % violations)
	else:
		print("[DataLayer] invariants: OK")
