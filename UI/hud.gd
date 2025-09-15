extends CanvasLayer
class_name HUD

signal play_toggled(running: bool)
signal speed_selected(mult: float)
signal overlay_toggled(name: StringName, enabled: bool)

@onready var btn_play: Button        = %BtnPlayPause
@onready var opt_speed: OptionButton = %OptSpeed
@onready var cb_water: CheckBox      = %CbWater
@onready var cb_temp: CheckBox       = %CbTemp

# 툴 버튼 참조
@onready var btn_tool_vacuum: Button = %BtnToolVacuum
@onready var btn_tool_fish: Button   = %BtnToolFish
var _tool_btn_group := ButtonGroup.new()

# ToolManager 연결
@export var _tool_manager: ToolManager

var _running := true

func _ready() -> void:
	# 배속 옵션 채우기
	# item_text => 표시, metadata => 실제 배속값
	_add_speed_item("0.5×", 0.5)
	_add_speed_item("1×",   1.0)
	_add_speed_item("2×",   2.0)
	_add_speed_item("5×",   5.0)
	opt_speed.select(1) # 기본 1×

	# 콜백 연결
	#btn_play.pressed.connect(_on_play_pressed) 이미 연결함.
	#opt_speed.item_selected.connect(_on_speed_selected) 이미 연결함.
	cb_water.toggled.connect(func(on): overlay_toggled.emit(&"water", on))
	cb_temp.toggled.connect(func(on):  overlay_toggled.emit(&"temp", on))

	# 툴팁
	btn_play.tooltip_text = "Play/Pause (Space)"
	cb_water.tooltip_text = "Toggle Water Overlay"
	cb_temp.tooltip_text  = "Toggle Temperature Overlay"

	# ToolManager 참조 및 신호 연결
	if _tool_manager == null:
		push_warning("[HUD] ToolManager not set; tool buttons will be inert")
	else:
		_tool_manager.tool_changed.connect(_sync_tool_ui)
		# 초기 상태 동기화
		_sync_tool_ui(_tool_manager.current_tool)

	# 툴 버튼 설정/연결
	# 배타 선택 보장(토글 + 같은 그룹)
	btn_tool_vacuum.toggle_mode = true
	btn_tool_fish.toggle_mode = true
	btn_tool_vacuum.button_group = _tool_btn_group
	btn_tool_fish.button_group = _tool_btn_group

	btn_tool_vacuum.text = "Vacuum [1]"
	btn_tool_fish.text   = "Fish [2]"
	btn_tool_vacuum.tooltip_text = "Set tool to Vacuum (Hotkey: 1)"
	btn_tool_fish.tooltip_text   = "Set tool to Fish (Hotkey: 2)"

	# 버튼은 오직 ToolManager에 요청만 함(의미 실행/분기는 ToolManager가 담당)
	btn_tool_vacuum.pressed.connect(func():
		if _tool_manager: _tool_manager.set_tool(ToolManager.Tool.VACUUM))
	btn_tool_fish.pressed.connect(func():
		if _tool_manager: _tool_manager.set_tool(ToolManager.Tool.SPAWN_FISH))

func _add_speed_item(label: String, mult: float) -> void:
	var idx := opt_speed.item_count
	opt_speed.add_item(label)
	opt_speed.set_item_metadata(idx, mult)

func _on_play_pressed() -> void:
	_running = not _running
	btn_play.text = "⏸" if _running else "▶"
	play_toggled.emit(_running)

func _on_speed_selected(idx: int) -> void:
	var mult: float = opt_speed.get_item_metadata(idx)
	speed_selected.emit(mult)

# 외부에서 HUD 초기 상태 동기화하고 싶으면 사용
func set_state(running: bool, speed_mult: float, water_on: bool, temp_on: bool) -> void:
	_running = running
	btn_play.text = "⏸" if _running else "▶"

	var found := false
	for i in opt_speed.item_count:
		if is_equal_approx(float(opt_speed.get_item_metadata(i)), speed_mult):
			opt_speed.select(i)
			found = true
			break
	if not found:
		# 예상치 못한 배속이 들어오면 임시 추가
		_add_speed_item("%sx" % speed_mult, speed_mult)
		opt_speed.select(opt_speed.item_count - 1)

	cb_water.button_pressed = water_on
	cb_temp.button_pressed  = temp_on

# ToolManager → HUD 동기화 훅
func _sync_tool_ui(new_tool: int) -> void:
	if new_tool == ToolManager.Tool.VACUUM:
		btn_tool_vacuum.button_pressed = true
		btn_tool_fish.button_pressed = false
	elif new_tool == ToolManager.Tool.SPAWN_FISH:
		btn_tool_vacuum.button_pressed = false
		btn_tool_fish.button_pressed = true
	else:
		btn_tool_vacuum.button_pressed = false
		btn_tool_fish.button_pressed = false
