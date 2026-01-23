## HungerUI: 허기 상태 표시 UI
extends Control
class_name HungerUI

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var label_calories: Label = $LabelCalories
@onready var label_state: Label = $LabelState
@onready var label_digesting: Label = $LabelDigesting

var _hunger_system: HungerSystem

func setup(hunger_system: HungerSystem) -> void:
	_hunger_system = hunger_system
	
	if _hunger_system:
		_hunger_system.hunger_changed.connect(_on_hunger_changed)
		_hunger_system.hunger_state_changed.connect(_on_state_changed)

func _ready() -> void:
	if progress_bar:
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.show_percentage = false

func _process(_delta: float) -> void:
	_update_digesting_display()

func _on_hunger_changed(current: float, max_val: float, ratio: float) -> void:
	if progress_bar:
		progress_bar.value = ratio * 100.0
		
		# 상태별 색상
		if _hunger_system:
			var color := _hunger_system.get_state_color()
			progress_bar.modulate = color
	
	if label_calories:
		label_calories.text = "%.1f / %.1f kcal" % [current, max_val]

func _on_state_changed(state: int) -> void:
	if not label_state or not _hunger_system:
		return
	
	var state_text := _hunger_system.get_state_text()
	var color := _hunger_system.get_state_color()
	
	label_state.text = "State: %s" % state_text
	label_state.modulate = color

func _update_digesting_display() -> void:
	if not label_digesting or not _hunger_system:
		return
	
	var digesting := _hunger_system._digesting_food
	
	if digesting.is_empty():
		label_digesting.text = ""
		return
	
	var total_cal := 0.0
	var min_time := INF
	
	for food in digesting:
		total_cal += food.calories
		min_time = min(min_time, food.time_left)
	
	label_digesting.text = "Digesting: %.1f kcal (%.0fs)" % [total_cal, min_time]
