class_name DataLayer

signal tiles_changed(changed_indices: PackedInt32Array, reason: StringName, payload: Dictionary)

var index: GridIndex = GridIndex.new()
var substance: SubstanceStore = SubstanceStore.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()
var temperature: TemperatureStore = TemperatureStore.new()
var light: LightStore = LightStore.new()

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

	var n := index.size.x * index.size.y
	var L0 := PackedFloat32Array(); L0.resize(n)
	for i in n: L0[i] = 0.0
	light.setup(index, L0)

	# 로깅 및 검증 단계
	_log_counts()
	_validate()

# ───────────────────────────────────────────────────────────────
const SID  := "sid"
const PHASE:= "phase"
const MASS := "mass"
const TEMP := "temp"
const LIGHT := "light"

# 임시 조치. 규모 커지면 Resource로 분리 필요. TODO
var _schema := { # sid 값을 기준으로 찾을 수 있다.
	0: { "phase": PhaseStore.Phase.VACUUM, "mass": 0, "temp": 0 }, # VACCUM
	10001: { "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 27315 }, # ICE
	10002: { "phase": PhaseStore.Phase.SOLID, "mass": 1_000_000, "temp": 30015 }, # SOIL
	20001: { "phase": PhaseStore.Phase.LIQUID, "mass": 1_000_000, "temp": 29315 }, # WATER
	30001: { "phase": PhaseStore.Phase.GAS,    "mass": 1_000,    "temp": 37315 }  # STEAM
}

# ───────────────────────────────────────────────────────────────
## 단일 진입점(Write-API) → 복수 셀 배치 버전
## 받는 키: "sid" | "phase" | "mass" | "temp"
## 키가 없음 → 보존(preserve)
## 키가 있고 값이 not null → 새 값으로 설정(set)
## 키가 있고 값이 null → 스키마 기본값(default)으로 설정
func set_cells_with_spec(cells: Array[Vector2i], spec: Dictionary, reason: StringName = &"") -> void:
	if cells.is_empty():
		return

	# ── Pass 1: 타깃 계산 & 변경 여부 수집 ────────────────────────────────
	var idxs: Array[int] = []
	var tgt_sids  : Array[int] = []
	var tgt_phases: Array[int] = []
	var tgt_masses: Array[int] = []
	var tgt_temps : Array[int] = []
	var tgt_lights: Array[float] = []

	var ch_sid_arr  : Array[bool] = []
	var ch_phase_arr: Array[bool] = []
	var ch_mass_arr : Array[bool] = []
	var ch_temp_arr : Array[bool] = []
	var ch_light_arr: Array[bool] = []

	var any_ch_sid   := false
	var any_ch_phase := false
	var any_ch_mass  := false
	var any_ch_temp  := false
	var any_ch_light := false

	for cell in cells:
		if not index.in_bounds_cell(cell):
			push_error("[DataLayer.set_cells_with_spec] invalid cell: %s" % [cell])
			continue
		var i := index.idx(cell)

		# 현재값
		var cur_sid   : int = substance.get_by_index(i)
		var cur_phase : int = phase.get_by_index(i)
		var cur_mass  : int = mass.get_by_index(i)
		var cur_temp  : int = temperature.get_by_index(i)

		# 타깃 sid
		var tgt_sid := cur_sid
		if spec.has("sid"):
			if spec["sid"] == null:
				push_error("[DataLayer.set_cells_with_spec] sid cannot be null"); 
				continue
			tgt_sid = int(spec["sid"])

		# 해당 sid 기준 기본 스펙
		var default_spec := get_spec(tgt_sid)

		# 타깃 필드 해석
		var tgt_phase : int = int(_resolve_field("phase", cur_phase, default_spec, spec))
		var tgt_mass  : int = int(_resolve_field("mass",  cur_mass,  default_spec, spec))
		var tgt_temp  : int = int(_resolve_field("temp",  cur_temp,  default_spec, spec))

		# 변경 여부
		var ch_sid   : bool = spec.has("sid") and (tgt_sid != cur_sid)
		var ch_phase : bool = (tgt_phase != cur_phase)
		var ch_mass  : bool = (tgt_mass  != cur_mass)
		var ch_temp  : bool = (tgt_temp  != cur_temp)

		if not (ch_sid or ch_phase or ch_mass or ch_temp):
			continue

		# accumulate
		idxs.append(i)
		tgt_sids.append(tgt_sid)
		tgt_phases.append(tgt_phase)
		tgt_masses.append(tgt_mass)
		tgt_temps.append(tgt_temp)

		ch_sid_arr.append(ch_sid)
		ch_phase_arr.append(ch_phase)
		ch_mass_arr.append(ch_mass)
		ch_temp_arr.append(ch_temp)

		any_ch_sid   = any_ch_sid   or ch_sid
		any_ch_phase = any_ch_phase or ch_phase
		any_ch_mass  = any_ch_mass  or ch_mass
		any_ch_temp  = any_ch_temp  or ch_temp

	# 변경된 셀이 하나도 없으면 종료
	if idxs.is_empty():
		return

	# ── Pass 2: 스토어별 일괄 begin/set/commit ────────────────────────────
	if any_ch_sid:   substance.begin_write()
	if any_ch_phase: phase.begin_write()
	if any_ch_mass:  mass.begin_write()
	if any_ch_temp:  temperature.begin_write()

	for k in idxs.size():
		var ii := idxs[k]
		if any_ch_sid and ch_sid_arr[k]:
			substance.set_by_index(ii, tgt_sids[k])
		if any_ch_phase and ch_phase_arr[k]:
			phase.set_by_index(ii, tgt_phases[k])
		if any_ch_mass and ch_mass_arr[k]:
			mass.set_by_index(ii, tgt_masses[k])
		if any_ch_temp and ch_temp_arr[k]:
			temperature.set_by_index(ii, tgt_temps[k])

	if any_ch_sid:   substance.commit()
	if any_ch_phase: phase.commit()
	if any_ch_mass:  mass.commit()
	if any_ch_temp:  temperature.commit()

	emit_signal(
		"tiles_changed",
		PackedInt32Array(idxs),
		(reason if reason != &"" else &"apply_spec_cells"),
		{
			"sid_changed": any_ch_sid,
			"phase_changed": any_ch_phase,
			"mass_changed": any_ch_mass,
			"temp_changed": any_ch_temp,
		}
	)

## 하위 호환/편의를 위한 단수 래퍼
## 받는 키: "sid" | "phase" | "mass" | "temp"
## 키가 없음 → 보존(preserve)
## 키가 있고 값이 not null → 새 값으로 설정(set)
## 키가 있고 값이 null → 스키마 기본값(default)으로 설정
func set_cell_with_spec(cell: Vector2i, spec: Dictionary, reason: StringName = &"") -> void:
	set_cells_with_spec([cell], spec, reason)

# 스토어 전체 교체 (개별 스토어 전용)
func set_bulk_sid(arr: PackedInt32Array, reason: StringName = &"") -> void:
	var n := index.size.x * index.size.y
	if arr.size() != n:
		push_error("[DataLayer.set_bulk_sid] size mismatch: need=%d, got=%d" % [n, arr.size()]); return
	substance.replace_all(arr, reason if reason != &"" else &"bulk_sid")
	emit_signal("tiles_changed", PackedInt32Array(), &"bulk_sid",
		{"sid_changed": true, "full_refresh": true})

func set_bulk_phase(arr: PackedByteArray, reason: StringName = &"") -> void:
	var n := index.size.x * index.size.y
	if arr.size() != n:
		push_error("[DataLayer.set_bulk_phase] size mismatch: need=%d, got=%d" % [n, arr.size()]); return
	phase.replace_all(arr, reason if reason != &"" else &"bulk_phase")
	emit_signal("tiles_changed", PackedInt32Array(), &"bulk_phase",
		{"phase_changed": true, "full_refresh": true})

func set_bulk_mass(arr: PackedInt64Array, reason: StringName = &"") -> void:
	var n := index.size.x * index.size.y
	if arr.size() != n:
		push_error("[DataLayer.set_bulk_mass] size mismatch: need=%d, got=%d" % [n, arr.size()]); return
	mass.replace_all(arr, reason if reason != &"" else &"bulk_mass")
	emit_signal("tiles_changed", PackedInt32Array(), &"bulk_mass",
		{"mass_changed": true, "full_refresh": true})

func set_bulk_temp(arr: PackedInt32Array, reason: StringName = &"") -> void:
	var n := index.size.x * index.size.y
	if arr.size() != n:
		push_error("[DataLayer.set_bulk_temp] size mismatch: need=%d, got=%d" % [n, arr.size()]); return
	temperature.replace_all(arr, reason if reason != &"" else &"bulk_temp")
	emit_signal("tiles_changed", PackedInt32Array(), &"bulk_temp",
		{"temp_changed": true, "full_refresh": true})

func set_bulk_light(arr: PackedFloat32Array, reason: StringName = &"") -> void:
	var n := index.size.x * index.size.y
	if arr.size() != n:
		push_error("[DataLayer.set_bulk_light] size mismatch: need=%d, got=%d" % [n, arr.size()]); return
	light.replace_all(arr, reason if reason != &"" else &"bulk_light")
	emit_signal("tiles_changed", PackedInt32Array(), &"bulk_light",
		{"light_changed": true, "full_refresh": true})

## 제네릭 버전
## target: "sid" | "phase" | "mass" | "temp"
func set_store_bulk(target: StringName, values: Variant, reason: StringName = &"") -> void:
	match String(target):
		"sid":
			if values is PackedInt32Array: set_bulk_sid(values, reason)
			else: push_error("[DataLayer.set_store_bulk] sid expects PackedInt32Array")
		"phase":
			if values is PackedByteArray: set_bulk_phase(values, reason)
			else: push_error("[DataLayer.set_store_bulk] phase expects PackedByteArray")
		"mass":
			if values is PackedInt64Array: set_bulk_mass(values, reason)
			else: push_error("[DataLayer.set_store_bulk] mass expects PackedInt64Array")
		"temp":
			if values is PackedInt32Array: set_bulk_temp(values, reason)
			else: push_error("[DataLayer.set_store_bulk] temp expects PackedInt32Array")
		"light":
			if values is PackedFloat32Array: set_bulk_light(values, reason)
			else: push_error("[DataLayer.set_store_bulk] light expects PackedFloat32Array")
		_:
			push_error("[DataLayer.set_store_bulk] unknown target: %s" % [target])


func get_spec(tile_id: int) -> Dictionary:
	if not _schema.has(tile_id):
		push_error("[DataLayer] Unknown tile id %s" % tile_id)
		return {}
	return _schema[tile_id].duplicate(true) # 복사본 리턴 (원본 보호)

## 규칙 해석 헬퍼: 없음=보존 / null=기본 / 값=설정
func _resolve_field(field: String,current: Variant, default_spec: Dictionary, spec: Dictionary) -> Variant:
	if not spec.has(field):
		return current
	var v = spec[field]
	if v == null:
		return default_spec.get(field, current) # 기본값 없으면 보존 fallback
	return v

# ───────────────────────────────────────────────────────────────
## 각 phase 수 집계
func _log_counts() -> void:
	var counts := [0, 0, 0, 0]
	var data := phase.get_raw_read()
	for i in data.size():
		counts[data[i]] += 1
	print("[DataLayer] SOLID=%d LIQUID=%d GAS=%d VACUUM=%d" % [counts[PhaseStore.Phase.SOLID], counts[PhaseStore.Phase.LIQUID], counts[PhaseStore.Phase.GAS], counts[PhaseStore.Phase.VACUUM]])

## 무결성 검증(기존 + 물질/phase 일관성 체크 옵션)
func _validate() -> void:
	var p := phase.get_raw_read()
	var m := mass.get_raw_read()
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
