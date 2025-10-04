extends RefCounted
class_name SubstanceRuleCache

# 공개 캐시 (런타임 조회 전용)
var rules_by_sid: Dictionary = {}   # sid -> Array[ {to_sid:int, t_ck_min?:int, t_ck_max?:int, hyst_ck:int} ]
var phase_of_sid: Dictionary = {}   # sid -> PH enum(int)
var path_to_sid: Dictionary = {}    # "phase/name" -> sid
var sid_to_path: Dictionary = {}    # (디버그용) sid -> "phase/name"

#열(thermal) 속성 (SI)
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

# 파일에서 로드
func load_from_file(path: String = "res://substance/substance.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	_load_from_text(file.get_as_text())

# 문자열(JSON)에서 로드(최소 처리)
func load_from_text(json_text: String) -> void:
	_load_from_text(json_text)

# ─────────────────────────────────────────────────────────

func _load_from_text(text: String) -> void:
	# 초기화
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

	# 가정: JSON은 정상.
	var j := JSON.new()
	if j.parse(text) != OK: return
	var root: Dictionary = j.get_data()
	if not root.has("phase"): return
	var phases: Dictionary = root["phase"]

	# 패스1: sid/phase/path + thermal + optical 수집 + defaults 파싱
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		var phase_kind := _phase_kind(phase_str)

		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])
			var path := "%s/%s" % [phase_str, name]

			path_to_sid[path] = sid
			sid_to_path[sid] = path
			phase_of_sid[sid] = phase_kind

			# thermal (없으면 0으로)
			var th: Dictionary = sdata.get("thermal", {})
			c_by_sid[sid] = float(th.get("c_J_per_kgK", 0.0))
			k_by_sid[sid] = float(th.get("k_W_per_mK", 0.0))

			# optical (없으면 안전 기본값)
			var op: Dictionary = sdata.get("optical", {})
			var transparent := bool(op.get("transparent", false))
			var k_m_inv := float(op.get("attenuation_m_inv", 0.0))
			var albedo := float(op.get("albedo", 0.0))

			opt_transparent_by_sid[sid] = transparent
			opt_k_by_sid[sid] = k_m_inv
			opt_albedo_by_sid[sid] = albedo
			# 성능 위해 칸당 감쇠계수 사전계산 (Δz=1m 가정)
			# k=0이면 alpha=1.0
			opt_alpha_by_sid[sid] = 1.0 if (k_m_inv == 0.0) else exp(-k_m_inv)

			var defs: Dictionary = sdata.get("defaults", {})
			if not defs.is_empty():
				# phase 문자열 그대로 보관 (DataLayer에서 enum으로 변환해도 되고,
				# 여기서 바로 변환해도 됨. 우선 문자열을 보관하는 방식을 권장)
				if defs.has("phase"):
					def_phase_str_by_sid[sid] = String(defs["phase"])
				if defs.has("mass"):
					def_mass_by_sid[sid] = int(defs["mass"])
				if defs.has("temp"):
					def_temp_by_sid[sid] = int(defs["temp"])
				if defs.has("light"):
					def_light_by_sid[sid] = float(defs["light"])

	# 패스2: 전이 규칙 컴파일
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])

			if sdata.has("transition") and typeof(sdata["transition"]) == TYPE_ARRAY:
				for trans in sdata["transition"]:
					var to_path = trans.get("to", "")
					var to_sid = path_to_sid.get(to_path, null)
					if to_sid == null: continue

					var _when: Dictionary = trans.get("when", {})
					var rule := {
						"to_sid": int(to_sid),
						"hyst_ck": int(trans.get("hyst_ck", 0)),
					}
					if _when.has("t_ck_min"): rule["t_ck_min"] = int(_when["t_ck_min"])
					if _when.has("t_ck_max"): rule["t_ck_max"] = int(_when["t_ck_max"])

					if not rules_by_sid.has(sid):
						rules_by_sid[sid] = []
					rules_by_sid[sid].append(rule)

# 문자열 phase → enum
func _phase_kind(phase_str: String) -> int:
	match phase_str:
		"solid":  return PH_SOLID
		"liquid": return PH_LIQUID
		"gas":    return PH_GAS
		_:        return 0

# 헬퍼
func sid_of(path: String, default_val: int = -1) -> int:
	return int(path_to_sid.get(path, default_val))

func has_sid(sid: int) -> bool:
	return phase_of_sid.has(sid)

func path_of_sid(sid: int, default_val: String = "") -> String:
	return String(sid_to_path.get(sid, default_val))

# DataLayer용: defaults 딕셔너리 리턴 (phase는 문자열 그대로)
func get_defaults_for_sid(sid: int) -> Dictionary:
	var res := {}
	if def_phase_str_by_sid.has(sid): res["phase"] = def_phase_str_by_sid[sid]
	if def_mass_by_sid.has(sid):      res["mass"] = def_mass_by_sid[sid]
	if def_temp_by_sid.has(sid):      res["temp"] = def_temp_by_sid[sid]
	if def_light_by_sid.has(sid):     res["light"] = def_light_by_sid[sid]
	return res
