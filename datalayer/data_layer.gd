class_name DataLayer

signal tiles_changed(changed_indices: PackedInt32Array, reason: StringName, payload: Dictionary)

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
var _schema := { # sid 값을 기준으로 찾을 수 있다.
	0: { "phase": PhaseStore.Phase.VACUUM, "mass": 0, "temp": 0 }, # VACCUM
	10001: { "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 27315 }, # ICE
	10002: { "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 30015 }, # SOIL
	20001: { "phase": PhaseStore.Phase.LIQUID, "mass": 1_000_000, "temp": 29315 }, # WATER
	30001: { "phase": PhaseStore.Phase.GAS,    "mass": 1_000,    "temp": 37315 }  # STEAM
}

# ───────────────────────────────────────────────────────────────
## 단일? 진입점(Write-API)
## 받는 키: "sid" | "phase" | "mass" | "temp"
## 키가 없음 → 보존(preserve)
## 키가 있고 값이 not null → 새 값으로 설정(set)
## 키가 있고 값이 null → 스키마 기본값(default)으로 설정
func set_cell_with_spec(cell: Vector2i, spec: Dictionary, reason: StringName = &"") -> void:
	# 0) 인덱스 & 범위 체크
	if not index.in_bounds_cell(cell):
		push_error("[DataLayer.set_cell_with_spec] invalid cell: %s" % [cell])
		return
	var i := index.idx(cell)

	# 1) 현재값
	var cur_sid   : int = substance.get_by_index(i)
	var cur_phase : int = phase.get_by_index(i)
	var cur_mass  : int = mass.get_by_index(i)
	var cur_temp  : int = temperature.get_by_index(i)

	# 2) 타겟 sid 결정
	var tgt_sid := cur_sid
	if spec.has("sid"):
		if spec["sid"] == null:
			push_error("[DataLayer.set_cell_with_spec] sid cannot be null"); return
		tgt_sid = int(spec["sid"])

	# 3) 기본값 테이블 준비 (항상 최종 sid 기준)
	var default_spec := get_spec(tgt_sid)

	# 4) 타겟값 해석 (없음=보존 / null=기본 / 값=설정)
	var tgt_phase : int = int(_resolve_field("phase", cur_phase, default_spec, spec))
	var tgt_mass  : int = int(_resolve_field("mass",  cur_mass,  default_spec, spec)) # 키 이름이 mass_mg이면 바꿔주세요
	var tgt_temp  : int = int(_resolve_field("temp",  cur_temp,  default_spec, spec)) # 키 이름이 temp_ck이면 바꿔주세요

	print("[Debug.set_cell_with_spec] ", tgt_phase, tgt_mass, tgt_temp)

	# 5) 실제 변경 여부
	var ch_sid   : bool = spec.has("sid") and (tgt_sid != cur_sid)
	var ch_phase : bool = (tgt_phase != cur_phase)
	var ch_mass  : bool = (tgt_mass  != cur_mass)
	var ch_temp  : bool = (tgt_temp  != cur_temp)

	print("[Debug.set_cell_with_spec] ", ch_sid, ch_phase, ch_mass, ch_temp)

	if not (ch_sid or ch_phase or ch_mass or ch_temp):
		return

	# 6) 바뀌는 스토어만 begin
	if ch_sid:   substance.begin_write()
	if ch_phase: phase.begin_write()
	if ch_mass:  mass.begin_write()
	if ch_temp:  temperature.begin_write()

	# 7) set_by_index (바뀌는 항목만)
	if ch_sid:   substance.set_by_index(i, tgt_sid)
	if ch_phase: phase.set_by_index(i, tgt_phase)
	if ch_mass:  mass.set_by_index(i, tgt_mass)
	if ch_temp:  temperature.set_by_index(i, tgt_temp)

	# 8) commit
	if ch_sid:   substance.commit()
	if ch_phase: phase.commit()
	if ch_mass:  mass.commit()
	if ch_temp:  temperature.commit()

	emit_signal(
		"tiles_changed",
		PackedInt32Array([i]),
		reason if reason != &"" else &"apply_spec_cell",
		{"sid_changed": ch_sid}
	)

# 재작성 필요. TODO
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

## 규칙 해석 헬퍼: 없음=보존 / null=기본 / 값=설정
func _resolve_field(field: String, current: Variant, default_spec: Dictionary, spec: Dictionary) -> Variant:
	if not spec.has(field):
		return current
	var v = spec[field]
	if v == null:
		return default_spec.get(field, current) # 기본값 없으면 보존 fallback
	return v

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
