extends RefCounted
class_name SubstanceRuleCache

# 공개 캐시 (런타임 조회 전용)
var rules_by_sid: Dictionary = {}   # sid -> Array[ {to_sid:int, t_ck_min?:int, t_ck_max?:int, hyst_ck:int} ]
var phase_of_sid: Dictionary = {}   # sid -> PH enum(int)
var path_to_sid: Dictionary = {}    # "phase/name" -> sid
var sid_to_path: Dictionary = {}    # (디버그용) sid -> "phase/name"

# 열(thermal) 속성 (SI)
var c_by_sid: Dictionary = {}   # sid -> c[J/kg·K]
var k_by_sid: Dictionary = {}   # sid -> k[W/m·K]

# 광(optical) 속성
var opt_transparent_by_sid: Dictionary = {}  # sid -> bool (없으면 false)
var opt_k_by_sid: Dictionary = {}            # sid -> k [m^-1] (없으면 0.0)
var opt_alpha_by_sid: Dictionary = {}        # sid -> alpha = exp(-k) (k 기반 사전계산, 기본 1.0)
var opt_albedo_by_sid: Dictionary = {}       # sid -> albedo [0..1], 선택(없으면 0.0)

# phase 문자열 → enum
const PH_SOLID  := 1
const PH_LIQUID := 2
const PH_GAS    := 3

# 기본값 캐시 (DataLayer 브리지용)
var def_phase_str_by_sid: Dictionary = {}  # sid -> "solid"/"liquid"/"gas"/"vacuum"
var def_mass_by_sid: Dictionary = {}       # sid -> int (mg)
var def_temp_by_sid: Dictionary = {}       # sid -> int (cC)
var def_light_by_sid: Dictionary = {}      # sid -> float

# ══════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════

## 파일에서 로드 (검증 포함)
func load_from_file(path: String = "res://datalayer/substance/substance.json") -> bool:
	# 파일 존재 여부 확인
	if not FileAccess.file_exists(path):
		push_error("[SubstanceRuleCache] ❌ File not found: ", path)
		return false
	
	# 파일 열기 시도
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("[SubstanceRuleCache] ❌ Failed to open file: ", path, " Error code: ", err)
		return false
	
	# 파일 내용 읽기
	var text := file.get_as_text()
	if text.is_empty():
		push_error("[SubstanceRuleCache] ❌ File is empty: ", path)
		return false
	
	# 파싱 및 로드
	var success := _load_from_text(text)
	
	# 로드 결과 검증
	if not success:
		push_error("[SubstanceRuleCache] ❌ Failed to parse data from: ", path)
		return false
	
	if phase_of_sid.is_empty():
		push_error("[SubstanceRuleCache] ❌ No substances loaded from: ", path)
		return false
	
	print("[SubstanceRuleCache] Successfully loaded %d substances from: %s" 
		% [phase_of_sid.size(), path])
	return true

## 문자열(JSON)에서 로드 (테스트용)
func load_from_text(json_text: String) -> bool:
	return _load_from_text(json_text)

# ══════════════════════════════════════════════════════════════════
# Internal Loading Logic
# ══════════════════════════════════════════════════════════════════

func _load_from_text(text: String) -> bool:
	# 초기화
	_clear_all_caches()
	
	# JSON 파싱
	var j := JSON.new()
	var parse_result := j.parse(text)
	
	if parse_result != OK:
		push_error("[SubstanceRuleCache] JSON parse error: ", j.get_error_message(), 
				   " at line ", j.get_error_line())
		return false
	
	# 루트 검증
	var root = j.get_data()
	if typeof(root) != TYPE_DICTIONARY:
		push_error("[SubstanceRuleCache] Root is not a dictionary, got type: ", typeof(root))
		return false
	
	if not root.has("phase"):
		push_error("[SubstanceRuleCache] Missing 'phase' key in JSON")
		return false
	
	var phases: Dictionary = root["phase"]
	
	# 패스1: 물질 기본 정보 로드
	var loaded_count := _load_substances(phases)
	if loaded_count == 0:
		push_error("[SubstanceRuleCache] No substances were loaded")
		return false
	
	# 패스2: 전이 규칙 로드
	var rule_count := _load_transitions(phases)
	
	print("[SubstanceRuleCache] Loaded: %d substances, %d transition rules" 
		% [loaded_count, rule_count])
	
	return true

func _clear_all_caches() -> void:
	path_to_sid.clear()
	sid_to_path.clear()
	phase_of_sid.clear()
	rules_by_sid.clear()
	c_by_sid.clear()
	k_by_sid.clear()
	opt_transparent_by_sid.clear()
	opt_k_by_sid.clear()
	opt_alpha_by_sid.clear()
	opt_albedo_by_sid.clear()
	def_phase_str_by_sid.clear()
	def_mass_by_sid.clear()
	def_temp_by_sid.clear()
	def_light_by_sid.clear()

func _load_substances(phases: Dictionary) -> int:
	var loaded_count := 0
	
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		var phase_kind := _phase_kind(phase_str)

		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			
			if not sdata.has("id"):
				push_warning("[SubstanceRuleCache] Substance %s/%s missing 'id' field" % [phase_str, name])
				continue
			
			var sid: int = int(sdata["id"])
			var path := "%s/%s" % [phase_str, name]

			# 기본 정보
			path_to_sid[path] = sid
			sid_to_path[sid] = path
			phase_of_sid[sid] = phase_kind

			# Thermal 속성
			_load_thermal_properties(sid, sdata)
			
			# Optical 속성
			_load_optical_properties(sid, sdata)
			
			# Defaults
			_load_defaults(sid, sdata)
			
			loaded_count += 1
	
	return loaded_count

func _load_thermal_properties(sid: int, sdata: Dictionary) -> void:
	var th: Dictionary = sdata.get("thermal", {})
	c_by_sid[sid] = float(th.get("c_J_per_kgK", 0.0))
	k_by_sid[sid] = float(th.get("k_W_per_mK", 0.0))

func _load_optical_properties(sid: int, sdata: Dictionary) -> void:
	var op: Dictionary = sdata.get("optical", {})
	var transparent := bool(op.get("transparent", false))
	var k_m_inv := float(op.get("attenuation_m_inv", 0.0))
	var albedo := float(op.get("albedo", 0.0))

	opt_transparent_by_sid[sid] = transparent
	opt_k_by_sid[sid] = k_m_inv
	opt_albedo_by_sid[sid] = albedo
	# 성능 위해 칸당 감쇠계수 사전계산 (Δz=1m 가정)
	opt_alpha_by_sid[sid] = 1.0 if (k_m_inv == 0.0) else exp(-k_m_inv)

func _load_defaults(sid: int, sdata: Dictionary) -> void:
	var defs: Dictionary = sdata.get("defaults", {})
	if defs.is_empty():
		return
	
	if defs.has("phase"):
		def_phase_str_by_sid[sid] = String(defs["phase"])
	if defs.has("mass"):
		def_mass_by_sid[sid] = int(defs["mass"])
	if defs.has("temp"):
		def_temp_by_sid[sid] = int(defs["temp"])
	if defs.has("light"):
		def_light_by_sid[sid] = float(defs["light"])

func _load_transitions(phases: Dictionary) -> int:
	var rule_count := 0
	
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])

			if not sdata.has("transition"):
				continue
			
			if typeof(sdata["transition"]) != TYPE_ARRAY:
				continue
			
			for trans in sdata["transition"]:
				var to_path = trans.get("to", "")
				var to_sid = path_to_sid.get(to_path, null)
				
				if to_sid == null:
					push_warning("[SubstanceRuleCache] Unknown transition target: %s -> %s" 
						% [sid_to_path.get(sid, "?"), to_path])
					continue

				var _when: Dictionary = trans.get("when", {})
				var rule := {
					"to_sid": int(to_sid),
					"hyst_ck": int(trans.get("hyst_ck", 0)),
				}
				if _when.has("t_ck_min"): 
					rule["t_ck_min"] = int(_when["t_ck_min"])
				if _when.has("t_ck_max"): 
					rule["t_ck_max"] = int(_when["t_ck_max"])

				if not rules_by_sid.has(sid):
					rules_by_sid[sid] = []
				rules_by_sid[sid].append(rule)
				rule_count += 1
	
	return rule_count

# ══════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════

func _phase_kind(phase_str: String) -> int:
	match phase_str:
		"solid":  return PH_SOLID
		"liquid": return PH_LIQUID
		"gas":    return PH_GAS
		_:        return 0

func sid_of(path: String, default_val: int = -1) -> int:
	return int(path_to_sid.get(path, default_val))

func has_sid(sid: int) -> bool:
	return phase_of_sid.has(sid)

func path_of_sid(sid: int, default_val: String = "") -> String:
	return String(sid_to_path.get(sid, default_val))

func get_defaults_for_sid(sid: int) -> Dictionary:
	var res := {}
	if def_phase_str_by_sid.has(sid): res["phase"] = def_phase_str_by_sid[sid]
	if def_mass_by_sid.has(sid):      res["mass"] = def_mass_by_sid[sid]
	if def_temp_by_sid.has(sid):      res["temp"] = def_temp_by_sid[sid]
	if def_light_by_sid.has(sid):     res["light"] = def_light_by_sid[sid]
	return res
