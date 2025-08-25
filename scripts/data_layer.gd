class_name DataLayer

var index: GridIndex = GridIndex.new()
var substance: SubstanceStore = SubstanceStore.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()
var temperature: TemperatureStore = TemperatureStore.new()

func setup(
		size: Vector2i,
		substances: PackedInt32Array,
		phases: PackedByteArray,
		masses: PackedInt64Array
	) -> void:
	index.setup(size)
	substance.setup(index, substances)
	phase.setup(index, phases)
	mass.setup(index, masses)
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

# 단일 쓰기 API: 물질 교체 → SubstanceDef로 phase/mass 동기화
func replace_substance(cell: Vector2i, id: int, opts: Dictionary = {}) -> void:
	# 호출자는 반드시 begin_frame_write()를 먼저 호출해야 함
	substance.set_substance(cell, id)

	# phase 동기화
	phase.set_phase(cell, SubstanceDef.phase_of(id))

	# mass 동기화: 기본값 또는 보존/오버라이드
	if opts.get("preserve_mass", false):
		# 아무 것도 하지 않음 (기존 질량 유지)
		pass
	else:
		var m := SubstanceDef.default_mass_of(id)
		if opts.has("override_mass_mg"):
			m = int(opts["override_mass_mg"])
		mass.set_cell(cell, m)

# ───────────────────────────────────────────────────────────────
# 각 phase 수 집계
func _log_counts() -> void:
	var counts := [0, 0, 0, 0]
	var data := phase.get_raw()
	for i in data.size():
		counts[data[i]] += 1
	print("[DataLayer] SOLID=%d LIQUID=%d GAS=%d VACUUM=%d" % [counts[PhaseStore.Phase.SOLID], counts[PhaseStore.Phase.LIQUID], counts[PhaseStore.Phase.GAS], counts[PhaseStore.Phase.VACUUM]])

# 무결성 검증(기존 + 물질/phase 일관성 체크 옵션)
func _validate() -> void:
	var p := phase.get_raw()
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
