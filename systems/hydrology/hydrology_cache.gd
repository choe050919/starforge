# HydrologyCache.gd
extends RefCounted
class_name HydrologyCache

# sid -> 값
var max_by_sid: Dictionary = {}     # int sid -> int (mg)
var infil_by_sid: Dictionary = {}   # int sid -> int (mg/tick)
var leak_by_sid: Dictionary = {}    # int sid -> int (mg/tick)
var diff_by_sid: Dictionary = {}    # int sid -> int (mg/tick)

# (선택) Dense arrays
var _sid_max: int = -1
var max_dense: PackedInt32Array = PackedInt32Array()
var infil_dense: PackedInt32Array = PackedInt32Array()
var leak_dense: PackedInt32Array = PackedInt32Array()
var diff_dense: PackedInt32Array = PackedInt32Array()
var _has_dense: bool = false

var _version: int = 0

func load_from_text(text: String) -> void:
	max_by_sid.clear()
	infil_by_sid.clear()
	leak_by_sid.clear()
	diff_by_sid.clear()
	_sid_max = -1
	_has_dense = false
	_version += 1

	var j := JSON.new()
	var err: int = j.parse(text)
	if err != OK:
		push_error("[HydrologyCache] JSON parse error: %s" % j.error_string)
		return

	var root_v: Variant = j.get_data()
	if typeof(root_v) != TYPE_DICTIONARY:
		return
	var root: Dictionary = root_v

	var phases_v: Variant = root.get("phase", {})
	if typeof(phases_v) != TYPE_DICTIONARY:
		return
	var phases: Dictionary = phases_v

	for phase_key in phases.keys():
		var pd_v: Variant = phases[phase_key]
		if typeof(pd_v) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = pd_v

		for name in pd.keys():
			var sdata_v: Variant = pd[name]
			if typeof(sdata_v) != TYPE_DICTIONARY:
				continue
			var sdata: Dictionary = sdata_v
			if not sdata.has("id"):
				continue

			var sid: int = int(sdata["id"])
			_sid_max =  _sid_max if _sid_max > sid else sid

			var hydro_v: Variant = sdata.get("hydrology", {})
			if typeof(hydro_v) != TYPE_DICTIONARY:
				# 미정의면 0으로
				max_by_sid[sid] = 0
				infil_by_sid[sid] = 0
				leak_by_sid[sid] = 0
				diff_by_sid[sid] = 0
				continue
			var hydro: Dictionary = hydro_v

			var raw_max: int = int(hydro.get("max_moisture_mg", 0))
			var raw_in : int = int(hydro.get("infiltration_limit_mg_per_tick", 0))
			var raw_lk : int = int(hydro.get("leak_down_mg_per_tick", 0))
			var raw_df : int = int(hydro.get("soil2soil_diffusivity_mg_per_tick", 0))

			var v_max: int = raw_max if raw_max >= 0 else 0
			var v_in : int = raw_in  if raw_in  >= 0 else 0
			var v_lk : int = raw_lk  if raw_lk  >= 0 else 0
			var v_df : int = raw_df  if raw_df  >= 0 else 0

			max_by_sid[sid]   = v_max
			infil_by_sid[sid] = v_in
			leak_by_sid[sid]  = v_lk
			diff_by_sid[sid]  = v_df

	# Dense 배열 구성(선택)
	if _sid_max >= 0 and _sid_max <= 200000:
		_build_dense()

func _build_dense() -> void:
	var count: int = _sid_max + 1
	max_dense.resize(count)
	infil_dense.resize(count)
	leak_dense.resize(count)
	diff_dense.resize(count)

	for sid in count:
		max_dense[sid]   = int(max_by_sid.get(sid, 0))
		infil_dense[sid] = int(infil_by_sid.get(sid, 0))
		leak_dense[sid]  = int(leak_by_sid.get(sid, 0))
		diff_dense[sid]  = int(diff_by_sid.get(sid, 0))

	_has_dense = true

func capacity_of(sid: int) -> int:
	return max_dense[sid] if _has_dense and sid >= 0 and sid < max_dense.size() else int(max_by_sid.get(sid, 0))

func infil_of(sid: int) -> int:
	return infil_dense[sid] if _has_dense and sid >= 0 and sid < infil_dense.size() else int(infil_by_sid.get(sid, 0))

func leak_of(sid: int) -> int:
	return leak_dense[sid] if _has_dense and sid >= 0 and sid < leak_dense.size() else int(leak_by_sid.get(sid, 0))

func diff_of(sid: int) -> int:
	return diff_dense[sid] if _has_dense and sid >= 0 and sid < diff_dense.size() else int(diff_by_sid.get(sid, 0))

func version() -> int:
	return _version
