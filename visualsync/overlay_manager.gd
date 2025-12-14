extends Node
class_name OverlayManager

signal active_changed(old_mode: OverlayMode, new_mode: OverlayMode)

enum OverlayMode { NONE, HEATMAP, HEAT_SOURCE, LIGHT, NAVIGATION }

# 토글 가능한 오버레이만 등록
@export var overlay_paths := {
	OverlayMode.HEATMAP: NodePath("OverlayLayer/HeatmapOverlay"),
	OverlayMode.HEAT_SOURCE: NodePath("OverlayLayer/HeatSourceOverlay"),
	OverlayMode.LIGHT: NodePath("OverlayLayer/LightOverlay"),
	OverlayMode.NAVIGATION: NodePath("OverlayLayer/NavigationOverlay"),
}

@onready var _grayscale: ColorRect = get_node("FXLayer/Grayscale")

var _active := OverlayMode.NONE
var _overlays: Dictionary[OverlayMode, CanvasItem] = {}

func _ready() -> void:
	for mode in overlay_paths.keys():
		var path: NodePath = overlay_paths[mode]
		var node := get_node(path)
		if node:
			_overlays[mode] = node
		else:
			push_warning("[OverlayManager] missing overlay node at path: %s (mode=%s)" % [str(path), str(mode)])
	
	_apply()

# ── Public API ───────────────────────────────────────────────

## 현재 활성화된 오버레이를 반환합니다.
func get_active() -> OverlayMode:
	return _active

## 현재 활성화된 오버레이가 [param mode]인지 검사합니다.
func is_active(mode: OverlayMode) -> bool:
	return _active == mode

## 모든 오버레이를 끕니다.
func clear() -> void:
	set_active(OverlayMode.NONE)

## [param mode] 오버레이를 토글합니다.
## [br]이미 켜져 있다면 끄고, 아니라면 [param mode]를 켭니다.
func toggle(mode: OverlayMode) -> void:
	if _active == mode:
		set_active(OverlayMode.NONE)
	else:
		set_active(mode)

## [param mode] 오버레이를 켭니다.
## [br]주의: 외부에서는 [method toggle]을 사용하는 것을 권장합니다.
func set_active(mode: OverlayMode) -> void:
	if mode == _active:
		return
	
	var old := _active
	_active = mode
	_apply()
	active_changed.emit(old, _active)
	
	print("[Overlay] %s" % OverlayMode.find_key(_active))

# NOTE: 내부 노드를 외부에 노출하면 위험할 수 있음
func get_overlay_node(mode: int) -> CanvasItem:
	return _get_overlay(mode)

# ── Internals ───────────────────────────────────────────────

# NOTE: get_overlay_node를 제거한다면 필요 없어짐
func _get_overlay(mode: int) -> CanvasItem:
	if mode == OverlayMode.NONE:
		return null
	if not overlay_paths.has(mode):
		return null
	var path: NodePath = overlay_paths[mode]
	if not has_node(path):
		return null
	return get_node(path) as CanvasItem

func _apply() -> void:
	# 1) 모든 오버레이 끄기
	for overlay in _overlays.values():
		if overlay:
			overlay.visible = false
	
	# 2) FX 끄기
	if _grayscale:
		_grayscale.visible = false
	
	# 3) 활성 오버레이만 켜기
	if _active != OverlayMode.NONE:
		var target: CanvasItem = _overlays[_active]
		if target:
			target.visible = true
		if _grayscale:
			_grayscale.visible = true

# ── Debug ───────────────────────────────────────────────

func debug_active_name() -> String:
	return OverlayMode.find_key(_active)
