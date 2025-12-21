extends Node
class_name ToolManager

# ── 도구 정의 ───────────────────────────────────────────────────

enum Tool { 
	NONE, 
	MINE, 
	VACUUM, 
	SPAWN_FISH, 
	SPAWN_PLANT, 
	ADD_TEMP,
	CONSTRUCT,
	CONSTRUCT_LADDER
}

## 현재 선택된 도구
@export var current_tool: Tool = Tool.SPAWN_FISH

# ── 시그널 ──────────────────────────────────────────────────────=

# UI/하이라이트용
signal tool_changed(new_tool: Tool)

# - 도메인 시스템에게 “의미 있는 행동”을 요청
#   (InputController는 이 신호에 관여하지 않음)
signal request_mine(cell: Vector2i)
signal request_vacuum(cell: Vector2i)
signal request_spawn_fish(world_pos: Vector2, cell: Vector2i)
signal request_spawn_plant(cell: Vector2i)
signal request_add_temp(cell: Vector2i)
signal request_construct(cell: Vector2i)
signal request_construct_ladder(cell: Vector2i)

# ── 초기화 ──────────────────────────────────────────────────────

func _ready() -> void:
	# 초기 도구 상태를 구독자에게 알린다. (UI 등이 시작 시점 상태를 동기화할 수 있도록)
	tool_changed.emit(current_tool)

# ── 외부 API ─────────────────────────────────────────────

## 도구를 변경한다.
## UI 버튼, 핫키 등 모든 도구 변경 요청은 이 함수를 통해야 한다.
## 같은 도구를 다시 선택하면 무시된다.
func set_tool(new_tool: Tool) -> void:
	if new_tool == current_tool:
		return
	current_tool = new_tool
	print("[ToolManager] tool selected: ", new_tool)
	tool_changed.emit(current_tool)

## 숫자 인덱스로 도구를 선택한다.
## 유효하지 않은 인덱스는 무시된다.
func select_tool_by_index(idx: int) -> void:
	if idx < 0:
		return
	# 유효한 값인지 체크
	if not Tool.values().has(idx):
		return
	set_tool(idx)

## 클릭 이벤트를 처리한다.
## 현재 선택된 도구에 맞는 request_* 시그널을 발사한다.
## [param cell]: 클릭된 그리드 좌표
## [param world_pos]: 클릭된 월드 좌표
func handle_click(cell: Vector2i, world_pos: Vector2) -> void:
	match current_tool:
		Tool.MINE:
			request_mine.emit(cell)
		Tool.VACUUM:
			request_vacuum.emit(cell)
		Tool.SPAWN_FISH:
			request_spawn_fish.emit(world_pos, cell)
		Tool.SPAWN_PLANT:
			request_spawn_plant.emit(cell)
		Tool.ADD_TEMP:
			request_add_temp.emit(cell)
		Tool.CONSTRUCT:
			request_construct.emit(cell)
		Tool.CONSTRUCT_LADDER:
			request_construct_ladder.emit(cell)
		_:
			push_warning("[ToolManager] Unknown tool: %s" % [str(current_tool)])

## 도구를 순환 선택한다.
## [param step]: 양수면 다음, 음수면 이전
func cycle_tool(step: int) -> void:
	var count := Tool.size()
	var next := (current_tool + step) % count
	if next < 0:
		next += count
	set_tool(next)

## 디버깅/로그/툴팁용 이름 변환기
static func tool_name(t: Tool) -> StringName:
	match t:
		Tool.NONE:             return &"NONE"
		Tool.MINE:             return &"MINE"
		Tool.VACUUM:           return &"VACUUM"
		Tool.SPAWN_FISH:       return &"SPAWN_FISH"
		Tool.SPAWN_PLANT:      return &"SPAWN_PLANT"
		Tool.ADD_TEMP:         return &"ADD_TEMP"
		Tool.CONSTRUCT:        return &"CONSTRUCT"
		Tool.CONSTRUCT_LADDER: return &"CONSTRUCT_LADDER"
		_:                     return &"UNKNOWN"
