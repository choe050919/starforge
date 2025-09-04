extends RefCounted
class_name SubstanceRuleCache

# 공개 캐시 (런타임에서 바로 사용)
var rules_by_sid: Dictionary = {}   # sid -> Array[ {to_sid:int, t_ck_min?:int, t_ck_max?:int, hyst_ck:int} ]
var phase_of_sid: Dictionary = {}   # sid -> PH enum(int)
var path_to_sid: Dictionary = {}    # "phase/name" -> sid
var sid_to_path: Dictionary = {}    # (디버그용) sid -> "phase/name"
# 열 속성(SI) 원본 저장
var c_by_sid: Dictionary = {}   # sid -> c[J/kg·K]
var k_by_sid: Dictionary = {}   # sid -> k[W/m·K]

# 내부 상수: 문자열 phase -> enum 값
const PH_SOLID  := 1
const PH_LIQUID := 2
const PH_GAS    := 3

# 파일에서 로드(최소 처리)
func load_from_file(path: String = "res://substance/substance.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	_load_from_text(file.get_as_text())

# 문자열(JSON)에서 로드(최소 처리)
func load_from_text(json_text: String) -> void:
	_load_from_text(json_text)

# ─────────────────────────────────────────────────────────

func _load_from_text(text: String) -> void:
	path_to_sid.clear()
	sid_to_path.clear()
	phase_of_sid.clear()
	rules_by_sid.clear()
	c_by_sid.clear()
	k_by_sid.clear()

	# 가정: JSON은 정상. (검증/경고 없음)
	var j := JSON.new()
	if j.parse(text) != OK: return
	var root: Dictionary = j.get_data()
	var phases: Dictionary = root["phase"]

	# 패스1: 기본 맵 + 열 속성(SI) 수집	
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		var phase_kind := _phase_kind(phase_str)
		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])
			var path := "%s/%s" % [phase_str, name]

			# 멤버에 등록
			path_to_sid[path] = sid
			sid_to_path[sid] = path
			phase_of_sid[sid] = phase_kind

			var th: Dictionary = sdata.get("thermal", {})
			c_by_sid[sid] = float(th.get("c_J_per_kgK", 0.0))
			k_by_sid[sid] = float(th.get("k_W_per_mK", 0.0))

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

# 문자열 phase를 enum으로
func _phase_kind(phase_str: String) -> int:
	match phase_str:
		"solid":  return PH_SOLID
		"liquid": return PH_LIQUID
		"gas":    return PH_GAS
		_:        return 0

# 헬퍼 함수들
func sid_of(path: String, default_val: int = -1) -> int:
	# 정확한 "phase/name" 경로를 sid로 변환. 없으면 default 반환.
	return int(path_to_sid.get(path, default_val))

func has_sid(sid: int) -> bool:
	return phase_of_sid.has(sid)

func path_of_sid(sid: int, default_val: String = "") -> String:
	return String(sid_to_path.get(sid, default_val))
