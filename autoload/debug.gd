extends Node

## 디버그 로그를 출력합니다.
## 
## 사용법:
##   Debug.log(self, "메시지")
##   Debug.log(self, "포맷: %d, %s", [123, "테스트"])
## 
## caller 객체에 debug_enabled 변수가 true일 때만 출력됩니다.
func log(caller: Object, msg: String, args: Array = []) -> void:
	if not caller.get("debug_enabled"):
		return
	
	var tag: String
	var script = caller.get_script()
	if script and script.get_global_name():
		tag = script.get_global_name()
	else:
		tag = caller.get_class()
	
	if args.is_empty():
		print("[%s] %s" % [tag, msg])
	else:
		print("[%s] %s" % [tag, msg % args])
