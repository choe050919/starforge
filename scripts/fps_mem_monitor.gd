# FpsMemMonitor.gd (Godot 4.x)
extends Control

@export var update_interval := 0.5    # 갱신 주기(초)
@export var start_visible := true     # 시작 시 표시 여부
@export var show_peak_memory := false # 피크 메모리도 표시할지

var _accum := 0.0
var _label: Label

func _ready() -> void:
	visible = start_visible
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	size = Vector2.ZERO  # 패널이 내용에 맞춰 알아서 크기 잡게: 필요한 코드인가?

	# 패널 + 라벨 구성
	var panel := PanelContainer.new()
	add_child(panel)
	panel.name = "Panel"
	panel.add_theme_constant_override("margin_left", 10)
	panel.add_theme_constant_override("margin_top", 8)
	panel.add_theme_constant_override("margin_right", 10)
	panel.add_theme_constant_override("margin_bottom", 8)

	_label = Label.new()
	_label.name = "Label"
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.text = "…"
	panel.add_child(_label)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < update_interval:
		return
	_accum = 0.0

	var fps := Engine.get_frames_per_second()
	var mem_mb := OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var text := "FPS: %d\nMemory: %.2f MB" % [fps, mem_mb]

	if show_peak_memory and OS.has_feature("editor"):
		# 피크 메모리는 에디터에서 확인하기 좋음 (릴리즈에서도 동작은 함)
		var peak_mb := OS.get_static_memory_peak_usage() / (1024.0 * 1024.0)
		text += "\nPeak: %.2f MB" % peak_mb

	_label.text = text
