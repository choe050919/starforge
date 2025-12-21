extends Control
class_name HUD

# ── 시그널 ──────────────────────────────────────────────────────
signal play_toggled(running: bool)
signal speed_selected(mult: float)
signal overlay_toggled(name: StringName, enabled: bool)

# ── 게임 컨트롤 ─────────────────────────────────────────────────
@onready var btn_play: Button        = %BtnPlayPause
@onready var opt_speed: OptionButton = %OptSpeed
@onready var cb_water: CheckBox      = %CbWater
@onready var cb_temp: CheckBox       = %CbTemp

# ── 툴 버튼 ─────────────────────────────────────────────────────
@onready var btn_tool_mine: Button = %BtnToolMine
@onready var btn_tool_vacuum: Button = %BtnToolVacuum
@onready var btn_tool_fish: Button = %BtnToolFish
@onready var btn_tool_plant: Button = %BtnToolPlant
@onready var btn_tool_add_temp: Button = %BtnToolAddTemp
@onready var btn_tool_construct: Button = %BtnToolConstruct
@onready var btn_tool_ladder: Button = %BtnToolLadder

var _tool_btn_group := ButtonGroup.new()
var _tool_buttons: Dictionary = {}

# ── 의존성 ──────────────────────────────────────────────────────
@export var _tool_manager: ToolManager

# ── 상태 ────────────────────────────────────────────────────────
var _running := true

# ── 초기화 ────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_speed_options()
	_setup_overlay_toggles()
	_setup_tooltips()
	_setup_tool_buttons()
	_connect_tool_manager()

func _setup_speed_options() -> void:
	# 배속 옵션 채우기
	# item_text => 표시, metadata => 실제 배속값
	_add_speed_item("0.5×", 0.5)
	_add_speed_item("1×",   1.0)
	_add_speed_item("2×",   2.0)
	_add_speed_item("5×",   5.0)
	opt_speed.select(1) # 기본 1×

func _setup_overlay_toggles() -> void:
	cb_water.toggled.connect(func(on): overlay_toggled.emit(&"water", on))
	cb_temp.toggled.connect(func(on): overlay_toggled.emit(&"temp", on))

func _setup_tooltips() -> void:
	btn_play.tooltip_text = "Play/Pause (Space)"
	cb_water.tooltip_text = "Toggle Water Overlay"
	cb_temp.tooltip_text  = "Toggle Temperature Overlay"

func _setup_tool_buttons() -> void:
	# Tool → Button 매핑 정의
	_tool_buttons = {
		ToolManager.Tool.MINE: btn_tool_mine,
		ToolManager.Tool.VACUUM: btn_tool_vacuum,
		ToolManager.Tool.SPAWN_FISH: btn_tool_fish,
		ToolManager.Tool.SPAWN_PLANT: btn_tool_plant,
		ToolManager.Tool.ADD_TEMP: btn_tool_add_temp,
		ToolManager.Tool.CONSTRUCT: btn_tool_construct,
		ToolManager.Tool.CONSTRUCT_LADDER: btn_tool_ladder,
	}
	
	# Tool → 표시 텍스트
	var labels := {
		ToolManager.Tool.MINE: "Mine [1]",
		ToolManager.Tool.VACUUM: "Vacuum [2]",
		ToolManager.Tool.SPAWN_FISH: "Fish [3]",
		ToolManager.Tool.SPAWN_PLANT: "Plant [4]",
		ToolManager.Tool.ADD_TEMP: "AddTemp [5]",
		ToolManager.Tool.CONSTRUCT: "Build [6]",
		ToolManager.Tool.CONSTRUCT_LADDER: "Ladder [7]",
	}
	
	# 버튼 설정 및 연결
	for tool in _tool_buttons:
		var btn: Button = _tool_buttons[tool]
		btn.toggle_mode = true
		btn.button_group = _tool_btn_group
		btn.text = labels.get(tool, "???")
		if _tool_manager:
			btn.pressed.connect(_tool_manager.set_tool.bind(tool))

func _connect_tool_manager() -> void:
	if _tool_manager == null:
		push_warning("[HUD] ToolManager not set; tool buttons will be inert")
		return
	_tool_manager.tool_changed.connect(_sync_tool_ui)
	_sync_tool_ui(_tool_manager.current_tool)

# ── 외부 인터페이스 ─────────────────────────────────────────────

## 외부에서 HUD 초기 상태를 동기화한다.
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

# ── 내부 핸들러 ─────────────────────────────────────────────────

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

## ToolManager → HUD 동기화
func _sync_tool_ui(new_tool: ToolManager.Tool) -> void:
	if _tool_buttons.has(new_tool):
		_tool_buttons[new_tool].button_pressed = true
