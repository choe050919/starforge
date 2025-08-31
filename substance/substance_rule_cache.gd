extends RefCounted
class_name SubstanceRuleCache

# 공개 캐시 (런타임에서 바로 사용)
var rules_by_sid: Dictionary = {}   # sid -> Array[ {to_sid:int, t_ck_min?:int, t_ck_max?:int, hyst_ck:int} ]
var phase_of_sid: Dictionary = {}   # sid -> PH enum(int)

# 내부 상수: 문자열 phase -> enum 값
const PH_SOLID  := 1
const PH_LIQUID := 2
const PH_GAS    := 3

# 파일에서 로드(최소 처리)
func load_from_file(path: String = "res://substance/substance.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	_load_from_text(file.get_as_text())

# 문자열(JSON)에서 로드(최소 처리)
func load_from_text(json_text: String) -> void:
	_load_from_text(json_text)

# ─────────────────────────────────────────────────────────

func _load_from_text(text: String) -> void:
	# 가정: JSON은 정상. (검증/경고 없음)
	var j := JSON.new()
	if j.parse(text) != OK:
		return
	var root: Dictionary = j.get_data()
	var phases: Dictionary = root["phase"]

	# 패스1: "phase/name" -> sid, 그리고 sid -> phase_kind
	var path_map: Dictionary = {}  # "phase/name" -> sid
	phase_of_sid.clear()
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		var phase_kind := _phase_kind(phase_str)
		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])
			path_map["%s/%s" % [phase_str, name]] = sid
			phase_of_sid[sid] = phase_kind

	# 패스2: 전이 컴파일 → sid -> rules[]
	rules_by_sid.clear()
	for phase_str in phases.keys():
		var phase_dict: Dictionary = phases[phase_str]
		for name in phase_dict.keys():
			var sdata: Dictionary = phase_dict[name]
			var sid: int = int(sdata["id"])

			if sdata.has("transition") and typeof(sdata["transition"]) == TYPE_ARRAY:
				for trans in sdata["transition"]:
					var to_path = trans.get("to", "")
					var to_sid = path_map.get(to_path, null)
					if to_sid == null:
						continue

					var when: Dictionary = trans.get("when", {})
					var rule := {
						"to_sid": int(to_sid),
						"hyst_ck": int(trans.get("hyst_ck", 0)),
					}
					if when.has("t_ck_min"):
						rule["t_ck_min"] = int(when["t_ck_min"])
					if when.has("t_ck_max"):
						rule["t_ck_max"] = int(when["t_ck_max"])

					if not rules_by_sid.has(sid):
						rules_by_sid[sid] = []
					rules_by_sid[sid].append(rule)

# 문자열 phase를 enum으로
func _phase_kind(phase_str: String) -> int:
	match phase_str:
		"solid":  return PH_SOLID
		"liquid": return PH_LIQUID
		"gas":    return PH_GAS
		_:        return 0  # VACUUM 등은 여기선 미사용(최소 구현)
