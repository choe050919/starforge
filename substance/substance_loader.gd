class_name SubstanceLoader

var substances : Dictionary = {}

## JSON 파일에서 물질을 로드
func load_materials():
	var file = FileAccess.open("res://substance/substance.json", FileAccess.READ)
	var data = file.get_as_text()
	
	var json_parser= JSON.new()
	var result = json_parser.parse(data)
	
	if result != OK:
		print("JSON 파싱 오류:", json_parser.error_string)
		return

	# 파싱된 데이터 가져오기
	var parsed_data = json_parser.get_data()

	# parsed_data가 Dictionary인지 확인
	if typeof(parsed_data) != TYPE_DICTIONARY:
		print("JSON 파싱된 데이터는 Dictionary가 아닙니다.")
		return
	
	# phases 키가 있는지 확인
	if not parsed_data.has("phase"):
		print("phases 키가 없습니다.")
		return
	
	var phases = parsed_data["phase"]
	
	if typeof(phases) != TYPE_DICTIONARY:
		print("phases는 Dictionary가 아닙니다.")
		return


	
	#var phases = json_parser.get_data()["phases"]
	
	for phase in phases.keys():
		var phase_data = phases[phase]
		for name in phase_data.keys():
			var substance_data = phase_data[name]
			var substance = Substance.new(
				substance_data["id"], 
				name
			)
			substances[name] = substance

## 특정 물질을 가져오는 함수
func get_substance(name: String) -> Substance:
	return substances.get(name, null)
