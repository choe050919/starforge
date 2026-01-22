extends Control
class_name UIRoot
## UI 레이아웃의 루트 노드.
## World로부터 UIContext를 받아 하위 UI 컴포넌트들을 초기화한다.

# ── Signals (World로 전달) ──────────────────────────────────────
signal play_toggled(running: bool)
signal speed_selected(mult: float)
signal overlay_toggled(overlay_name: StringName, enabled: bool)

# ── Child UI References ─────────────────────────────────────────
@onready var hud: HUD = %HUD
@onready var hunger_ui: HungerUI = %HungerUI
@onready var inventory_ui: InventoryUI = %InventoryUI

# ── State ───────────────────────────────────────────────────────
var _context: UIContext


func setup(ctx: UIContext) -> void:
	_context = ctx
	
	_setup_hud()
	_setup_hunger_ui()
	_setup_inventory_ui()


func _setup_hud() -> void:
	if not hud:
		push_warning("[UIRoot] HUD not found")
		return
	
	# 신호 연결 (World로 전달)
	hud.play_toggled.connect(_on_hud_play_toggled)
	hud.speed_selected.connect(_on_hud_speed_selected)
	
	hud.set_state(
		_context.is_running,
		_context.speed_mult,
	)
	
	# ToolManager 연결
	if _context.tool_manager:
		hud.set_tool_manager(_context.tool_manager)


func _setup_hunger_ui() -> void:
	if not hunger_ui:
		push_warning("[UIRoot] HungerUI not found")
		return
	
	if _context.hunger:
		hunger_ui.setup(_context.hunger)


func _setup_inventory_ui() -> void:
	if not inventory_ui:
		push_warning("[UIRoot] InventoryUI not found")
		return
	
	if _context.substance_loader:
		inventory_ui.setup(_context.substance_loader)


# ── Signal Forwarding ───────────────────────────────────────────

func _on_hud_play_toggled(running: bool) -> void:
	play_toggled.emit(running)


func _on_hud_speed_selected(mult: float) -> void:
	speed_selected.emit(mult)


func _on_hud_overlay_toggled(overlay_name: StringName, enabled: bool) -> void:
	overlay_toggled.emit(overlay_name, enabled)


# ── Public API (World에서 호출) ─────────────────────────────────

func on_inventory_changed(material_sid: int, mass_mg: int) -> void:
	if inventory_ui:
		inventory_ui.on_inventory_changed(material_sid, mass_mg)
