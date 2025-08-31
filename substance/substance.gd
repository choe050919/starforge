extends Resource
class_name Substance

# 물질 속성
var id : int
var name : String
var transitions: Array = []

# 생성자
func _init(_id, _name):
	self.id = _id
	self.name = _name

# 물질 정보 출력
func get_info() -> String:
	return "Name: %s\nID: %d" % [self.name, self.id]
