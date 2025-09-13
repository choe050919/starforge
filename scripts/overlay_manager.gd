extends Node
class_name OverlayManager

enum OverlayMode { NONE, HEATMAP, HEAT_SOURCE, LIGHT }

@onready var grayscale_overlay: ColorRect = get_node("FXLayer/GrayscaleOverlay")

var current_overlay: int = OverlayMode.NONE

# 오버레이 경로 테이블 (토글 가능한 오버레이만 등록)
var overlay_paths := {
	OverlayMode.HEATMAP: NodePath("OverlayLayer/HeatmapOverlay"),
	OverlayMode.HEAT_SOURCE: NodePath("OverlayLayer/HeatSourceOverlay"),
	OverlayMode.LIGHT: NodePath("OverlayLayer/LightOverlay"),
}

func _ready() -> void:
	_apply_state()

func _get_overlay(mode: int) -> CanvasItem:
	if mode == OverlayMode.NONE:
		return null
	if not overlay_paths.has(mode):
		return null
	var path: NodePath = overlay_paths[mode]
	if not has_node(path):
		return null
	return get_node(path) as CanvasItem

func get_overlay(mode: int) -> CanvasItem:
	return _get_overlay(mode)

func _apply_state() -> void:
	for m in overlay_paths.keys():
		var overlay := _get_overlay(m)
		if overlay:
			overlay.visible = false
	if grayscale_overlay:
		grayscale_overlay.visible = false
	if current_overlay != OverlayMode.NONE:
		var target := _get_overlay(current_overlay)
		if target:
			target.visible = true
		if grayscale_overlay:
			grayscale_overlay.visible = true

func set_overlay(mode: int) -> void:
	if mode == current_overlay:
		return
	current_overlay = mode
	_apply_state()

	var name_str := "NONE"
	if mode == OverlayMode.HEATMAP:
		name_str = "HEATMAP"
	elif mode == OverlayMode.HEAT_SOURCE:
		name_str = "HEAT_SOURCE"
	elif mode == OverlayMode.LIGHT:
		name_str = "LIGHT"
	print("[Overlay] ", name_str)

func toggle_overlay(mode: int) -> void:
	if current_overlay == mode:
		set_overlay(OverlayMode.NONE)
	else:
		set_overlay(mode)
