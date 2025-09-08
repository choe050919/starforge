class_name DataLayer

var index: GridIndex = GridIndex.new()
var substance: SubstanceStore = SubstanceStore.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()
var temperature: TemperatureStore = TemperatureStore.new()
#var moisture: MoistureStore = MoistureStore.new()
#var soil_view: SoilViewStore = SoilViewStore.new()
#var hydro_field: HydrologyField = HydrologyField.new()

func setup(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	masses: PackedInt64Array,
	temperatures: PackedInt32Array,
) -> void:
	index.setup(size)
	substance.setup(index, substances)
	phase.setup(index, phases)
	mass.setup(index, masses)
	temperature.setup(index, temperatures)

	_log_counts()
	_validate()

# ───────────────────────────────────────────────────────────────
const SID  := "sid"
const PHASE:= "phase"
const MASS := "mass"
const TEMP := "temp"

# 임시 조치. 규모 커지면 Resource로 분리 필요. TODO
var _schema := {
	0: { "sid": 0, "phase": PhaseStore.Phase.VACUUM, "mass": 0, "temp": 0 }, # VACCUM
	10001: { "sid": 10001, "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 27315 }, # ICE
	10002: { "sid": 10002, "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 30015 }, # SOIL
	20001: { "sid": 20001, "phase": PhaseStore.Phase.LIQUID, "mass": 1_000_000, "temp": 29315 }, # WATER
	30001: { "sid": 30001, "phase": PhaseStore.Phase.GAS,    "mass": 1_000,    "temp": 37315 }  # STEAM
}

# 허용 키(딱 4개): "sid" | "phase" | "mass" | "temp"
# 규칙:
# 반드시 "sid" 포함(없으면 거부).
# 나머지 키는 “선택적 오버라이드”. 없으면 스키마(TileSchema) 에서 기본값을 채움.
# VACUUM이면 mass=0, phase=VACUUM, sid=VACUUM, temp=0로 강제.
func apply_cells_with_spec(cells: Array[Vector2i], tile_spec: Dictionary, reason: StringName = &"") -> void:
	if not tile_spec.has(SID):
		push_error("[DataLayer] tile_spec must include 'sid'")

	# 1) 스키마에서 기본 스펙 가져오기 (tile-> {sid, phase, mass, temp})
	## 스키마에 저장된 기본 스펙
	var spec = get_spec(tile_spec["sid"])  # {sid, phase, mass, temp}

	# 2) 오버라이드 적용
	for k in tile_spec.keys():
		if k != "sid":
			spec[k] = tile_spec[k]

	# 3) 자동 보정
	if spec["mass"] <= 0:
		spec["mass"] = 0
		spec["sid"] = 0
		spec["phase"] = 0
		spec["temp"] = 0

	# 4) 필요한 스토어만 begin
	var to_begin := []
	to_begin.append(substance)
	to_begin.append(phase)
	to_begin.append(mass)
	to_begin.append(temperature)
	for s: BaseStore in to_begin: s.begin_write()

	# 5) 배치 set
	for c in cells:
		var i := index.idx(c)
		substance.set_by_index(i, spec["sid"])
		phase.set_by_index(i, spec["phase"])
		mass.set_by_index(i, spec["mass"])
		temperature.set_by_index(i, spec["temp"])

	# 6) commit
	for s: BaseStore in to_begin: s.commit()

func get_spec(tile_id: int) -> Dictionary:
	if not _schema.has(tile_id):
		push_error("[DataLayer] Unknown tile id %s" % tile_id)
		return {}
	return _schema[tile_id].duplicate(true) # 복사본 리턴 (원본 보호)

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
