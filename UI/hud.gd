extends Control
class_name HUD

signal play_toggled(running: bool)
signal speed_selected(mult: float)
signal overlay_toggled(name: StringName, enabled: bool)

@onready var btn_play: Button        = %BtnPlayPause
@onready var opt_speed: OptionButton = %OptSpeed
@onready var cb_water: CheckBox      = %CbWater
@onready var cb_temp: CheckBox       = %CbTemp

# 툴 버튼들
@onready var btn_tool_mine: Button = %BtnToolMine
@onready var btn_tool_vacuum: Button = %BtnToolVacuum
@onready var btn_tool_fish: Button = %BtnToolFish
@onready var btn_tool_plant: Button = %BtnToolPlant
@onready var btn_tool_add_temp: Button = %BtnToolAddTemp
@onready var btn_tool_construct: Button = %BtnToolConstruct
@onready var btn_tool_ladder: Button = %BtnToolLadder

var _tool_btn_group := ButtonGroup.new()

# ToolManager 연결
@export var _tool_manager: ToolManager

var _running := true

func _ready() -> void:
	# ToolManager 참조 및 신호 연결
	if _tool_manager == null:
		push_warning("[HUD] ToolManager not set; tool buttons will be inert")
	else:
		_tool_manager.tool_changed.connect(_sync_tool_ui)
		_sync_tool_ui(_tool_manager.current_tool)

	# 배속 옵션 채우기
	# item_text => 표시, metadata => 실제 배속값
	_add_speed_item("0.5×", 0.5)
	_add_speed_item("1×",   1.0)
	_add_speed_item("2×",   2.0)
	_add_speed_item("5×",   5.0)
	opt_speed.select(1) # 기본 1×

	# 오버레이 토글
	cb_water.toggled.connect(func(on): overlay_toggled.emit(&"water", on))
	cb_temp.toggled.connect(func(on):  overlay_toggled.emit(&"temp", on))

	# 툴팁
	btn_play.tooltip_text = "Play/Pause (Space)"
	cb_water.tooltip_text = "Toggle Water Overlay"
	cb_temp.tooltip_text  = "Toggle Temperature Overlay"

	# 툴 버튼 설정
	_setup_tool_buttons()

func _setup_tool_buttons() -> void:
	var buttons := [
		btn_tool_mine, btn_tool_vacuum, btn_tool_fish,
		btn_tool_plant, btn_tool_add_temp, btn_tool_construct,
		btn_tool_ladder
	]
	
	# 배타 선택 설정
	for btn in buttons:
		btn.toggle_mode = true
		btn.button_group = _tool_btn_group

	# 버튼 텍스트
	btn_tool_mine.text = "Mine [1]"
	btn_tool_vacuum.text = "Vacuum [2]"
	btn_tool_fish.text = "Fish [3]"
	btn_tool_plant.text = "Plant [4]"
	btn_tool_add_temp.text = "AddTemp [5]"
	btn_tool_construct.text = "Build [6]"
	btn_tool_ladder.text = "Ladder [7]"

	# 버튼 → ToolManager 연결
	if _tool_manager:
		btn_tool_mine.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.MINE))
		btn_tool_vacuum.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.VACUUM))
		btn_tool_fish.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.SPAWN_FISH))
		btn_tool_plant.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.SPAWN_PLANT))
		btn_tool_add_temp.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.ADD_TEMP))
		btn_tool_construct.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.CONSTRUCT))
		btn_tool_ladder.pressed.connect(func():
			_tool_manager.set_tool(ToolManager.Tool.CONSTRUCT_LADDER))

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
	match new_tool:
		ToolManager.Tool.MINE:
			btn_tool_mine.button_pressed = true
		ToolManager.Tool.VACUUM:
			btn_tool_vacuum.button_pressed = true
		ToolManager.Tool.SPAWN_FISH:
			btn_tool_fish.button_pressed = true
		ToolManager.Tool.SPAWN_PLANT:
			btn_tool_plant.button_pressed = true
		ToolManager.Tool.ADD_TEMP:
			btn_tool_add_temp.button_pressed = true
		ToolManager.Tool.CONSTRUCT:
			btn_tool_construct.button_pressed = true
		ToolManager.Tool.CONSTRUCT_LADDER:
			btn_tool_ladder.button_pressed = true
