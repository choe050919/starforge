extends Resource
class_name Substance

# 물질 속성
var id : int
var name : String

# 생성자
func _init(id, name):
	self.id = id
	self.name = name

# 물질 정보 출력
func get_info() -> String:
	return "Name: %s\nID: %d" % [self.name, self.id]
