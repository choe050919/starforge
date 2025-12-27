class_name SubstanceLoader

var substances : Dictionary = {}
var _id_to_name: Dictionary[int, String] = {}

## JSON 파일에서 물질을 로드
func load_materials():
	var file = FileAccess.open("res://datalayer/substance/substance.json", FileAccess.READ)
	if file == null: push_error("[SubstanceLoader] Failed to find json file!"); return
	var root := _parse_json_dict(file.get_as_text())
	if root.is_empty(): return
	var phases := _get_dict(root, "phase", "root")
	if phases.is_empty(): return

	var path_map: Dictionary = {}  # "phase/name" -> Substance

	# Substance 생성 + 경로맵 구성
	for phase in phases.keys():
		var phase_data = phases[phase]
		for name in phase_data.keys():
			var substance_data = phase_data[name]
			var s = Substance.new(substance_data["id"], name)
			substances[name] = s
			_id_to_name[s.id] = name
			path_map["%s/%s" % [phase, name]] = s

	# transition 해석 → to_sid로 컴파일
	for phase in phases.keys():
		var phase_data = phases[phase]
		for name in phase_data.keys():
			var s_data = phase_data[name]
			var s: Substance = path_map["%s/%s" % [phase, name]]

			if s_data.has("transition") and typeof(s_data["transition"]) == TYPE_ARRAY:
				for trans in s_data["transition"]:
					var to_path = trans.get("to", "")
					var to_sub: Substance = path_map.get(to_path, null)
					if to_sub == null:
						push_error("[SubstanceLoader] Unknown transition target: %s" % to_path)
						continue

					var when = trans.get("when", {})
					var rule := {
						"to_sid": to_sub.id,
						"t_ck_min": when.get("t_ck_min", null),
						"t_ck_max": when.get("t_ck_max", null),
						"hyst_ck": int(trans.get("hyst_ck", 0)),
					}
					s.transitions.append(rule)

## 특정 물질을 가져오는 함수
func get_substance(name: String) -> Substance:
	return substances.get(name, null)

func get_name_by_id(sid: int) -> String:
	return _id_to_name.get(sid, "???")

# ── 얇은 검증 헬퍼들 ────────────────────────────────────────────

## JSON 문자열을 파싱해서 Dictionary로 반환.
## - 파싱 실패 시 {} 반환
## - 최상위가 Dictionary가 아닐 경우 {} 반환
func _parse_json_dict(text: String) -> Dictionary:
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		push_error("[SubstanceLoader] JSON 파싱 오류: %s" % j.error_string); 
		return {}
	return _as_dict(j.get_data(), "root")

## Dictionary에서 특정 key를 꺼내 Dictionary로 반환.
## - key가 없거나 Dictionary가 아니면 {} 반환
## - label은 오류 메시지에 표시할 경로
func _get_dict(d: Dictionary, key: String, label: String) -> Dictionary:
	if not d.has(key):
		push_error("[SubstanceLoader] %s에 '%s' 키 없음" % [label, key]); 
		return {}
	return _as_dict(d[key], "%s.%s" % [label, key])

## 값이 Dictionary인지 확인 후 반환.
## - Dictionary가 아니면 {} 반환
## - label은 오류 메시지에 표시할 경로
func _as_dict(v: Variant, label: String) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		push_error("[SubstanceLoader] %s는 Dictionary가 아님" % label)
		return {}
	return v
