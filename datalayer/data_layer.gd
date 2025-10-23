## DataLayer manages the core game state data across multiple stores.
##
## [b]Overview[/b]
## DataLayer acts as a unified interface for accessing and modifying game world data,
## including substances, phases, mass, temperature, and lighting. It provides both
## granular cell-level updates and bulk replacement operations.
##
## [b]Core Stores[/b]
## - [code]index[/code]: GridIndex for coordinate/index conversion
## - [code]substance[/code]: SubstanceStore tracking material types (SID)
## - [code]phase[/code]: PhaseStore tracking matter states (solid/liquid/gas/vacuum)
## - [code]mass[/code]: MassStore tracking cell mass in milligrams
## - [code]temperature[/code]: TemperatureStore tracking temperature in centi-Kelvin
## - [code]light[/code]: LightStore tracking light intensity values
##
## [b]Write API - Spec-based Updates[/b]
## Use spec dictionaries to update cells with flexible field control:
## [codeblock]
## # Update a single cell
## data_layer.set_cell_with_spec(Vector2i(10, 5), {
##     "sid": 10001,      # Set substance ID
##     "phase": null,     # Use schema default for phase
##     "mass": 50000,     # Set mass to 50000mg
##     "temp": 29315      # Set temperature
## })
##
## # Update multiple cells at once
## data_layer.set_cells_with_spec([cell1, cell2, cell3], {
##     "temp": 35000      # Only change temperature, preserve other fields
## })
## [/codeblock]
##
## [b]Spec Field Rules[/b]
## - [b]Key absent[/b]: Current value is preserved
## - [b]Key with value[/b]: Set to the specified value
## - [b]Key with null[/b]: Set to schema default for that substance
## - Available keys: [code]"sid"[/code], [code]"phase"[/code], [code]"mass"[/code], [code]"temp"[/code], [code]"light"[/code]
## - Special: [code]"sid"[/code] cannot be null
##
## [b]Write API - Bulk Operations[/b]
## Replace entire store arrays for performance-critical full updates:
## [codeblock]
## # Replace all substance IDs at once
## data_layer.set_bulk_sid(new_substances, &"world_generation")
##
## # Replace all temperatures
## data_layer.set_bulk_temp(new_temperatures, &"thermal_equilibrium")
##
## # Generic bulk setter
## data_layer.set_store_bulk(&"mass", new_masses, &"liquid_flow")
## [/codeblock]
##
## [b]Available Bulk Methods[/b]
## - [code]set_bulk_sid(PackedInt32Array)[/code]
## - [code]set_bulk_phase(PackedByteArray)[/code]
## - [code]set_bulk_mass(PackedInt64Array)[/code]
## - [code]set_bulk_temp(PackedInt32Array)[/code]
## - [code]set_bulk_light(PackedFloat32Array)[/code]
## - [code]set_store_bulk(target, values)[/code] - Generic dispatcher
##
## [b]Signals[/b]
## [code]tiles_changed(indices, reason, payload)[/code] emits after any modification:
## - [code]indices[/code]: PackedInt32Array of changed cell indices (empty for bulk)
## - [code]reason[/code]: StringName describing the change source
## - [code]payload[/code]: Dictionary with flags like [code]sid_changed[/code], [code]phase_changed[/code], etc.
##
## [b]Spec Resolution[/b]
## Get default values for any substance ID:
## [codeblock]
## var spec = data_layer.get_spec(10001)  # Returns { "phase": 0, "mass": 50000, ... }
## [/codeblock]
##
## [b]Transaction Model[/b]
## All write operations use begin_write() → commit() internally per store.
## Multiple cells can be updated efficiently in a single transaction.
##
## [b]Validation[/b]
## DataLayer enforces invariants:
## - VACUUM cells must have zero mass
## - SOLID/LIQUID cells must have positive mass
## - GAS cells currently have zero mass (not tracked)
## Violations are logged during setup and validation passes.

class_name DataLayer

signal tiles_changed(changed_indices: PackedInt32Array, reason: StringName, payload: Dictionary)

# ══════════════════════════════════════════════════════════════════
# Stores
# ══════════════════════════════════════════════════════════════════

var index: GridIndex = GridIndex.new()
var substance: SubstanceStore = SubstanceStore.new()
var phase: PhaseStore = PhaseStore.new()
var mass: MassStore = MassStore.new()
var temperature: TemperatureStore = TemperatureStore.new()
var light: LightStore = LightStore.new()
var durability: DurabilityStore = DurabilityStore.new()
var electricity: ElectricityStore = ElectricityStore.new()

# ══════════════════════════════════════════════════════════════════
# Dependencies & Constants
# ══════════════════════════════════════════════════════════════════

var _rule_cache: SubstanceRuleCache

const VACUUM_SID := 0

# ══════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════

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
	
	# DurabilityStore 초기화 추가
	durability.setup(index, null)
	_initialize_durability_from_world_data()

	# 로깅 및 검증
	_log_setup_statistics()
	_validate_invariants()

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rule_cache = cache

## 월드 생성 시 모든 셀의 Durability 초기값 설정
func _initialize_durability_from_world_data() -> void:
	var n := index.size.x * index.size.y
	
	for i in n:
		var cell := index.cell(i)
		var sid := substance.get_by_index(i)
		var mass_mg := mass.get_by_index(i)
		var mass_kg := float(mass_mg) / 1_000_000.0
		
		# 진공이 아니고 질량이 있는 셀만 초기화
		if sid != VACUUM_SID and mass_kg > 0.0:
			durability.reset_cell(cell, sid, mass_kg)
	
	print("[DataLayer] Durability initialized for %d cells" % n)

# ══════════════════════════════════════════════════════════════════
# Write API - Spec-based Cell Updates
# ══════════════════════════════════════════════════════════════════

## Update multiple cells with a specification dictionary
## Spec keys: "sid" | "phase" | "mass" | "temp" | "light"
## - Key absent → preserve current value
## - Key present with non-null value → set to new value
## - Key present with null value → set to schema default
func set_cells_with_spec(cells: Array[Vector2i], spec: Dictionary, reason: StringName = &"") -> void:
	if cells.is_empty():
		return
	
	var update_data := _calculate_cell_updates(cells, spec)
	
	if update_data.indices.is_empty():
		return
	
	_apply_cell_updates(update_data)
	_emit_tile_changes(update_data, reason)

## Single-cell convenience wrapper for set_cells_with_spec
func set_cell_with_spec(cell: Vector2i, spec: Dictionary, reason: StringName = &"") -> void:
	set_cells_with_spec([cell], spec, reason)

# ── Update Calculation ───────────────────────────────────────────

func _calculate_cell_updates(cells: Array[Vector2i], spec: Dictionary) -> Dictionary:
	var indices: Array[int] = []
	var target_sids: Array[int] = []
	var target_phases: Array[int] = []
	var target_masses: Array[int] = []
	var target_temps: Array[int] = []
	var target_hps: Array[float] = []
	
	var changed_sid: Array[bool] = []
	var changed_phase: Array[bool] = []
	var changed_mass: Array[bool] = []
	var changed_temp: Array[bool] = []
	var changed_hp: Array[bool] = []
	
	var any_sid_changed := false
	var any_phase_changed := false
	var any_mass_changed := false
	var any_temp_changed := false
	var any_hp_changed := false
	
	for cell in cells:
		if not index.in_bounds_cell(cell):
			push_error("[DataLayer] Invalid cell: %s" % cell)
			continue
		
		var update := _calculate_single_cell_update(cell, spec)
		
		if not update.has_changes:
			continue
		
		indices.append(update.index)
		target_sids.append(update.target_sid)
		target_phases.append(update.target_phase)
		target_masses.append(update.target_mass)
		target_temps.append(update.target_temp)
		target_hps.append(update.target_hp)
		
		changed_sid.append(update.changed_sid)
		changed_phase.append(update.changed_phase)
		changed_mass.append(update.changed_mass)
		changed_temp.append(update.changed_temp)
		changed_hp.append(update.changed_hp)
		
		any_sid_changed = any_sid_changed or update.changed_sid
		any_phase_changed = any_phase_changed or update.changed_phase
		any_mass_changed = any_mass_changed or update.changed_mass
		any_temp_changed = any_temp_changed or update.changed_temp
		any_hp_changed = any_hp_changed or update.changed_hp
	
	return {
		"indices": indices,
		"target_sids": target_sids,
		"target_phases": target_phases,
		"target_masses": target_masses,
		"target_temps": target_temps,
		"target_hps": target_hps,
		"changed_sid": changed_sid,
		"changed_phase": changed_phase,
		"changed_mass": changed_mass,
		"changed_temp": changed_temp,
		"changed_hp": changed_hp,
		"any_sid_changed": any_sid_changed,
		"any_phase_changed": any_phase_changed,
		"any_mass_changed": any_mass_changed,
		"any_temp_changed": any_temp_changed,
		"any_hp_changed": any_hp_changed
	}

func _calculate_single_cell_update(cell: Vector2i, spec: Dictionary) -> Dictionary:
	var i := index.idx(cell)
	
	# Current values
	var cur_sid := substance.get_by_index(i)
	var cur_phase := phase.get_by_index(i)
	var cur_mass := mass.get_by_index(i)
	var cur_temp := temperature.get_by_index(i)
	var cur_hp := durability.get_hp_by_index(i)
	
	# Target SID
	var target_sid := cur_sid
	if spec.has("sid"):
		if spec["sid"] == null:
			push_error("[DataLayer] SID cannot be null")
			return {"has_changes": false}
		target_sid = int(spec["sid"])
	
	# Get defaults for target SID
	var default_spec := get_spec(target_sid)
	
	# Resolve target values
	var target_phase := int(_resolve_field("phase", cur_phase, default_spec, spec))
	var target_mass := int(_resolve_field("mass", cur_mass, default_spec, spec))
	var target_temp := int(_resolve_field("temp", cur_temp, default_spec, spec))
	
	# hp는 schema에 없으므로 별도 처리
	var target_hp := cur_hp
	if spec.has("hp"):
		if spec["hp"] != null:
			target_hp = float(spec["hp"])
		# null이면 현재 값 유지
	
	# Determine what changed
	var changed_sid := spec.has("sid") and (target_sid != cur_sid)
	var changed_phase := (target_phase != cur_phase)
	var changed_mass := (target_mass != cur_mass)
	var changed_temp := (target_temp != cur_temp)
	var changed_hp: bool = spec.has("hp") and (abs(target_hp - cur_hp) > 0.001)
	
	var has_changes := changed_sid or changed_phase or changed_mass or changed_temp or changed_hp
	
	return {
		"has_changes": has_changes,
		"index": i,
		"target_sid": target_sid,
		"target_phase": target_phase,
		"target_mass": target_mass,
		"target_temp": target_temp,
		"target_hp": target_hp,
		"changed_sid": changed_sid,
		"changed_phase": changed_phase,
		"changed_mass": changed_mass,
		"changed_temp": changed_temp,
		"changed_hp": changed_hp
	}

# ── Update Application ───────────────────────────────────────────

func _apply_cell_updates(update_data: Dictionary) -> void:
	var indices: Array = update_data.indices
	
	# Begin write transactions
	if update_data.any_sid_changed:
		substance.begin_write()
	if update_data.any_phase_changed:
		phase.begin_write()
	if update_data.any_mass_changed:
		mass.begin_write()
	if update_data.any_temp_changed:
		temperature.begin_write()
	if update_data.any_hp_changed:
		durability.begin_write()
	
	# Apply updates
	for k in indices.size():
		var idx: int = indices[k]
		
		if update_data.any_sid_changed and update_data.changed_sid[k]:
			substance.set_by_index(idx, update_data.target_sids[k])
		
		if update_data.any_phase_changed and update_data.changed_phase[k]:
			phase.set_by_index(idx, update_data.target_phases[k])
		
		if update_data.any_mass_changed and update_data.changed_mass[k]:
			mass.set_by_index(idx, update_data.target_masses[k])
		
		if update_data.any_temp_changed and update_data.changed_temp[k]:
			temperature.set_by_index(idx, update_data.target_temps[k])
		
		if update_data.any_hp_changed and update_data.changed_hp[k]:
			durability.set_hp_by_index(idx, update_data.target_hps[k])
	
	# Commit transactions
	if update_data.any_sid_changed:
		substance.commit()
	if update_data.any_phase_changed:
		phase.commit()
	if update_data.any_mass_changed:
		mass.commit()
	if update_data.any_temp_changed:
		temperature.commit()
	if update_data.any_hp_changed:
		durability.commit()

func _emit_tile_changes(update_data: Dictionary, reason: StringName) -> void:
	var final_reason := reason if reason != &"" else &"apply_spec_cells"
	
	tiles_changed.emit(
		PackedInt32Array(update_data.indices),
		final_reason,
		{
			"sid_changed": update_data.any_sid_changed,
			"phase_changed": update_data.any_phase_changed,
			"mass_changed": update_data.any_mass_changed,
			"temp_changed": update_data.any_temp_changed,
			"hp_changed": update_data.any_hp_changed
		}
	)

# ══════════════════════════════════════════════════════════════════
# Write API - Bulk Store Replacement
# ══════════════════════════════════════════════════════════════════

func set_bulk_sid(arr: PackedInt32Array, reason: StringName = &"") -> void:
	if not _validate_bulk_array_size(arr.size()):
		return
	
	substance.replace_all(arr, reason if reason != &"" else &"bulk_sid")
	_emit_bulk_change(&"bulk_sid", {"sid_changed": true})

func set_bulk_phase(arr: PackedByteArray, reason: StringName = &"") -> void:
	if not _validate_bulk_array_size(arr.size()):
		return
	
	phase.replace_all(arr, reason if reason != &"" else &"bulk_phase")
	_emit_bulk_change(&"bulk_phase", {"phase_changed": true})

func set_bulk_mass(arr: PackedInt64Array, reason: StringName = &"") -> void:
	if not _validate_bulk_array_size(arr.size()):
		return
	
	mass.replace_all(arr, reason if reason != &"" else &"bulk_mass")
	_emit_bulk_change(&"bulk_mass", {"mass_changed": true})

func set_bulk_temp(arr: PackedInt32Array, reason: StringName = &"") -> void:
	if not _validate_bulk_array_size(arr.size()):
		return
	
	temperature.replace_all(arr, reason if reason != &"" else &"bulk_temp")
	_emit_bulk_change(&"bulk_temp", {"temp_changed": true})

func set_bulk_light(arr: PackedFloat32Array, reason: StringName = &"") -> void:
	if not _validate_bulk_array_size(arr.size()):
		return
	
	light.replace_all(arr, reason if reason != &"" else &"bulk_light")
	_emit_bulk_change(&"bulk_light", {"light_changed": true})

## Generic bulk setter with type validation
func set_store_bulk(target: StringName, values: Variant, reason: StringName = &"") -> void:
	match String(target):
		"sid":
			if values is PackedInt32Array:
				set_bulk_sid(values, reason)
			else:
				push_error("[DataLayer] 'sid' expects PackedInt32Array")
		"phase":
			if values is PackedByteArray:
				set_bulk_phase(values, reason)
			else:
				push_error("[DataLayer] 'phase' expects PackedByteArray")
		"mass":
			if values is PackedInt64Array:
				set_bulk_mass(values, reason)
			else:
				push_error("[DataLayer] 'mass' expects PackedInt64Array")
		"temp":
			if values is PackedInt32Array:
				set_bulk_temp(values, reason)
			else:
				push_error("[DataLayer] 'temp' expects PackedInt32Array")
		"light":
			if values is PackedFloat32Array:
				set_bulk_light(values, reason)
			else:
				push_error("[DataLayer] 'light' expects PackedFloat32Array")
		_:
			push_error("[DataLayer] Unknown bulk target: %s" % target)

# ── Bulk Update Helpers ──────────────────────────────────────────

func _validate_bulk_array_size(array_size: int) -> bool:
	var expected_size := index.size.x * index.size.y
	
	if array_size != expected_size:
		push_error("[DataLayer] Array size mismatch: expected=%d, got=%d" 
			% [expected_size, array_size])
		return false
	
	return true

func _emit_bulk_change(reason: StringName, changes: Dictionary) -> void:
	var payload := changes.duplicate()
	payload["full_refresh"] = true
	tiles_changed.emit(PackedInt32Array(), reason, payload)

# ══════════════════════════════════════════════════════════════════
# Write API - Full Cell Initialization
# ══════════════════════════════════════════════════════════════════

#func reset_cell(cell, sid, reason):
	#substance.reset_cell(cell, sid)
	#phase.reset_cell(cell, ...)
	#mass.reset_cell(cell, ...)
	#temperature.reset_cell(cell, ...)
	#durability.reset_cell(cell, sid, mass_kg)
	# 각 Store가 자기 책임으로 초기화

func clear_cell(cell: Vector2i, reason: StringName = &"clear") -> void:
	if not index.in_bounds_cell(cell):
		return
	
	var i := index.idx(cell)
	
	# 진공으로 설정
	var vacuum_spec := get_spec(VACUUM_SID)
	
	# Store들 업데이트
	substance.begin_write()
	phase.begin_write()
	mass.begin_write()
	temperature.begin_write()
	durability.begin_write()
	
	substance.set_by_index(i, VACUUM_SID)
	phase.set_by_index(i, vacuum_spec.get("phase", PhaseStore.Phase.VACUUM))
	mass.set_by_index(i, 0)
	temperature.set_by_index(i, vacuum_spec.get("temp", 0))
	durability.clear_cell(cell)
	
	substance.commit()
	phase.commit()
	mass.commit()
	temperature.commit()
	durability.commit()
	
	# 시그널 발행
	var update_data := {
		"indices": [i],
		"any_sid_changed": true,
		"any_phase_changed": true,
		"any_mass_changed": true,
		"any_temp_changed": true,
		"any_hp_changed": true
	}
	_emit_tile_changes(update_data, reason if reason != &"" else &"clear_cell")

# ══════════════════════════════════════════════════════════════════
# Spec Resolution
# ══════════════════════════════════════════════════════════════════

func get_spec(tile_id: int) -> Dictionary:
	if tile_id == VACUUM_SID:
		return _get_vacuum_spec()
	
	if _rule_cache == null:
		push_error("[DataLayer] Rule cache not bound")
		return {}
	
	var defaults := _rule_cache.get_defaults_for_sid(tile_id)
	if defaults.is_empty():
		push_error("[DataLayer] No defaults found for SID=%d" % tile_id)
		return {}
	
	return _convert_defaults_to_spec(defaults)

func _get_vacuum_spec() -> Dictionary:
	return {
		"phase": PhaseStore.Phase.VACUUM,
		"mass": 0,
		"temp": 0,
		"light": 0.0
	}

func _convert_defaults_to_spec(defaults: Dictionary) -> Dictionary:
	var phase_str := String(defaults.get("phase", "vacuum"))
	var phase_enum := _phase_string_to_enum(phase_str)
	
	return {
		"phase": phase_enum,
		"mass": int(defaults.get("mass", 0)),
		"temp": int(defaults.get("temp", 0)),
		"light": float(defaults.get("light", 0.0))
	}

func _phase_string_to_enum(phase_str: String) -> int:
	match phase_str:
		"solid":
			return PhaseStore.Phase.SOLID
		"liquid":
			return PhaseStore.Phase.LIQUID
		"gas":
			return PhaseStore.Phase.GAS
		"vacuum":
			return PhaseStore.Phase.VACUUM
		_:
			return PhaseStore.Phase.VACUUM

## Resolve field value: absent=preserve / null=default / value=set
func _resolve_field(
	field: String,
	current: Variant,
	default_spec: Dictionary,
	spec: Dictionary
) -> Variant:
	if not spec.has(field):
		return current
	
	var value = spec[field]
	
	if value == null:
		return default_spec.get(field, current)
	
	return value

# ══════════════════════════════════════════════════════════════════
# Statistics & Validation
# ══════════════════════════════════════════════════════════════════

func _log_setup_statistics() -> void:
	var phase_counts := _count_phases()
	
	print("[DataLayer] Phase distribution: SOLID=%d LIQUID=%d GAS=%d VACUUM=%d" % [
		phase_counts[PhaseStore.Phase.SOLID],
		phase_counts[PhaseStore.Phase.LIQUID],
		phase_counts[PhaseStore.Phase.GAS],
		phase_counts[PhaseStore.Phase.VACUUM]
	])

func _count_phases() -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	var phases := phase.get_raw_read()
	
	for i in phases.size():
		counts[phases[i]] += 1
	
	return counts

func _validate_invariants() -> void:
	var phases := phase.get_raw_read()
	var masses := mass.get_raw_read()
	var violations := 0
	
	for i in phases.size():
		if not _check_phase_mass_invariant(phases[i], masses[i]):
			violations += 1
	
	if violations > 0:
		push_error("[DataLayer] Invariant violations: %d" % violations)
	else:
		print("[DataLayer] Invariants: OK")

func _check_phase_mass_invariant(phase_value: int, mass_value: int) -> bool:
	match phase_value:
		PhaseStore.Phase.VACUUM:
			return mass_value == 0
		PhaseStore.Phase.LIQUID, PhaseStore.Phase.SOLID:
			return mass_value > 0
		PhaseStore.Phase.GAS:
			# Gas mass is not currently tracked
			return mass_value == 0
		_:
			return true
