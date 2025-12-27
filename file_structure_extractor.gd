extends Node

func _ready():
	print("\n========== [프로젝트 구조 추출 시작] ==========")
	print_dir("res://", "")
	print("========== [추출 끝] ==========\n")
	get_tree().quit() # 출력 후 바로 종료

func print_dir(path: String, indent: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		# 파일 리스트를 먼저 정렬해서 보기 좋게 만들기 위한 배열
		var dirs = []
		var files = []
		
		while file_name != "":
			# .godot 같은 숨김 파일이나 임시 폴더 제외
			if not file_name.begins_with("."): 
				if dir.current_is_dir():
					dirs.append(file_name)
				else:
					files.append(file_name)
			file_name = dir.get_next()
			
		dirs.sort()
		files.sort()
		
		# 폴더 먼저 출력
		for d in dirs:
			print(indent + "+ " + d)
			print_dir(path + "/" + d, indent + "    ") # 재귀 호출
			
		# 파일 출력
		for f in files:
			print(indent + "- " + f)
			
		dir.list_dir_end()
