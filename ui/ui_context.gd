class_name UIContext extends RefCounted
## UI 시스템에 필요한 의존성을 묶어서 전달하는 컨테이너.
## World에서 생성하여 UIRoot.setup()에 전달한다.

# ── Data ────────────────────────────────────────────────────────
var data_layer: DataLayer
var substance_loader: SubstanceLoader

# ── Systems ─────────────────────────────────────────────────────
var hover: HoverManager
var hunger: HungerSystem
var tool_manager: ToolManager

# ── Visual References (HUD 상태 표시용) ─────────────────────────
var liquid_overlay: Node2D  # LiquidOverlay
var overlay_manager: OverlayManager

# ── Initial State ───────────────────────────────────────────────
var is_running: bool = true
var speed_mult: float = 1.0


static func create(
	p_data_layer: DataLayer,
	p_substance_loader: SubstanceLoader,
	p_hover: HoverManager,
	p_hunger: HungerSystem,
	p_tool_manager: ToolManager,
	p_liquid_overlay: Node2D,
	p_overlay_manager: OverlayManager,
	p_is_running: bool = true,
	p_speed_mult: float = 1.0
) -> UIContext:
	var ctx := UIContext.new()
	ctx.data_layer = p_data_layer
	ctx.substance_loader = p_substance_loader
	ctx.hover = p_hover
	ctx.hunger = p_hunger
	ctx.tool_manager = p_tool_manager
	ctx.liquid_overlay = p_liquid_overlay
	ctx.overlay_manager = p_overlay_manager
	ctx.is_running = p_is_running
	ctx.speed_mult = p_speed_mult
	return ctx
