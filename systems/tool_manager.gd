extends Node
class_name ToolManager

# ─────────────────────────────────────────────────────────
## 1) 도구 enum
##    - 에디터에서 current_tool을 드롭다운으로 선택 가능
enum Tool { VACUUM, SPAWN_FISH }

## 현재 선택된 도구 (기본: 물고기 소환)
@export var current_tool: int = Tool.SPAWN_FISH

# ─────────────────────────────────────────────────────────
# 2) 방송 시그널
##    - UI/하이라이트용
signal tool_changed(new_tool: int)
##    - 도메인 시스템에게 “의미 있는 행동”을 요청
##      (InputController는 이 신호에 관여하지 않음)
signal request_vacuum(cell: Vector2i)
signal request_spawn_fish(world_pos: Vector2, cell: Vector2i)

func _ready() -> void:
	# 에디터에서 기본값으로 시작할 때, UI가 즉시 반영되도록 1회 방송
	emit_signal(&"tool_changed", current_tool)

# ─────────────────────────────────────────────────────────
# 3) 외부 인터페이스
##    - UI 버튼/핫키가 모두 이 메서드를 호출 (중복 로직 방지)
func set_tool(new_tool: int) -> void:
	if new_tool == current_tool:
		return
	current_tool = new_tool
	print("[ToolManager] tool selected: ", new_tool)
	emit_signal(&"tool_changed", current_tool)

## 숫자 핫키(예: 1, 2) → enum과 바로 매핑해서 선택
func select_tool_by_index(idx: int) -> void:
	if idx < 0:
		return
	# enum은 0..(len-1) 범위의 연속된 int이므로 간단 체크
	if idx > Tool.SPAWN_FISH:
		return
	set_tool(idx)

## InputController가 좌클릭을 해석하여 호출/혹은 신호로 연결하는 진입점
## - 클릭 좌표는 cell & world_pos 둘 다 전달(도구별 필요 좌표가 다를 수 있으므로)
func handle_click(cell: Vector2i, world_pos: Vector2, modifiers: int = 0) -> void:
	match current_tool:
		Tool.VACUUM:
			emit_signal(&"request_vacuum", cell)
		Tool.SPAWN_FISH:
			emit_signal(&"request_spawn_fish", world_pos, cell)
		_:
			# enum 누락 방지용 가드
			push_warning("[ToolManager] Unknown tool: %s" % [str(current_tool)])

## (선택) 마우스 휠 등으로 다음/이전 도구 순환하고 싶을 때 사용
func cycle_tool(step: int) -> void:
	var count := Tool.size()
	var next := (current_tool + step) % count
	if next < 0:
		next += count
	set_tool(next)

## 디버깅/로그/툴팁용 이름 변환기
static func tool_name(t: int) -> StringName:
	match t:
		Tool.VACUUM:     return &"VACUUM"
		Tool.SPAWN_FISH: return &"SPAWN_FISH"
		_:               return &"UNKNOWN"
