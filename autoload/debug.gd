extends Node
## 디버그 메시지 출력을 위한 전역 유틸리티.
## 
## log(), warn(), error() 함수를 제공하며,
## 호출자 객체의 클래스명/스크립트명을 자동으로 태그에 포함합니다.

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
	
	var tag := _get_tag(caller)
	var formatted_msg := _format_message(tag, msg, args)
	print(formatted_msg)

## 경고 메시지를 출력합니다.
## 
## 사용법:
##   Debug.warn(self, "메시지")
##   Debug.warn(self, "포맷: %d, %s", [123, "테스트"])
## 
## debug_enabled와 무관하게 항상 출력됩니다.
func warn(caller: Object, msg: String, args: Array = []) -> void:
	var tag := _get_tag(caller)
	var formatted_msg := _format_message(tag, msg, args)
	push_warning(formatted_msg)

## 에러 메시지를 출력합니다.
## 
## 사용법:
##   Debug.error(self, "메시지")
##   Debug.error(self, "포맷: %d, %s", [123, "테스트"])
## 
## debug_enabled와 무관하게 항상 출력됩니다.
func error(caller: Object, msg: String, args: Array = []) -> void:
	var tag := _get_tag(caller)
	var formatted_msg := _format_message(tag, msg, args)
	push_error(formatted_msg)

## caller 객체로부터 태그를 생성합니다.
func _get_tag(caller: Object) -> String:
	var script = caller.get_script()
	if script and script.get_global_name():
		return script.get_global_name()
	else:
		return caller.get_class()

## 메시지를 포맷팅합니다.
func _format_message(tag: String, msg: String, args: Array) -> String:
	if args.is_empty():
		return "[%s] %s" % [tag, msg]
	else:
		return "[%s] %s" % [tag, msg % args]
