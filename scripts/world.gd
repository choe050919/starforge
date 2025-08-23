extends Node2D

@onready var terrain: Terrain = get_node("Terrain")
@onready var ground_layer: TileMapLayer = get_node("Terrain/Ground")
@onready var liquid_overlay: LiquidOverlay = get_node("Terrain/LiquidOverlay")
@onready var crack_overlay: CrackOverlay = get_node("Terrain/CrackOverlay")
@onready var corner_highlight: CornerHighlight = terrain.get_node("CornerHighlight")

@onready var systems = %Systems
@onready var worldgen: WorldGen = systems.get_node("WorldGen")
@onready var durability: Durability = systems.get_node("Durability")
@onready var temp: Temperature = systems.get_node("Temperature")
@onready var clock: SimClock = systems.get_node("SimClock")
@onready var tchange: TileChange = systems.get_node("TileChange")
@onready var liquid: Liquid = systems.get_node("Liquid")
@onready var input: InputController = systems.get_node("InputController")
@onready var hover_service: HoverService = systems.get_node("HoverService")

@onready var overlay_manager: OverlayManager = %OverlayManager
@onready var heatmap: HeatmapOverlay = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEATMAP) as HeatmapOverlay
@onready var heat_src: HeatSourceOverlay = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEAT_SOURCE) as HeatSourceOverlay

var tile_store: TileStore = TileStore.new()
var event_queue: EventQueue = EventQueue.new()
var material_db: MaterialDB = MaterialDB.new()
var data_layer: DataLayer = DataLayer.new()

# 경로 주입용
@export var highlight_path: NodePath
@export var info_panel_path: NodePath

@onready var camera: Camera2D = get_node("Camera2D")

func _ready() -> void:
	if worldgen == null:
		push_error("[World] Systems/WorldGen 노드를 찾지 못했습니다."); return
	if terrain == null:
		push_error("[World] Terrain 노드를 찾지 못했습니다."); return

	hover_service.setup(data_layer)
	input.setup(data_layer, hover_service)
	if input != null:
		input.pan_requested.connect(_on_pan_requested)
		input.zoom_requested.connect(_on_zoom_requested)
		input.overlay_toggle_requested.connect(_on_overlay_toggle_requested)
	if hover_service != null:
		hover_service.hover_changed.connect(_on_hover_changed)

	# connect signals
	worldgen.generated.connect(_on_world_generated)
	temp.temperature_updated.connect(_on_temperature_updated)

	worldgen.generate()

	if clock:
		clock.tick_sim.connect(_on_tick_sim)

	if tchange != null:
		tchange.tile_destroyed.connect(_on_tile_destroyed)
		tchange.tile_replaced.connect(_on_tile_replaced)
	if durability != null and tchange != null:
		durability.break_requested.connect(func(cell: Vector2i): tchange.queue_destroy(cell, &"durability"))

	if durability != null and crack_overlay != null:
		durability.hp_changed.connect(crack_overlay.on_hp_changed)
		durability.break_requested.connect(crack_overlay.on_break_requested)

func _on_world_generated(size: Vector2i, phases: PackedByteArray, mass: PackedFloat32Array, tiles: PackedInt32Array, springs: PackedVector2Array) -> void:
	terrain.apply_tiles(tiles, size)
	tile_store.setup(tiles, size)
	data_layer.setup(size, phases, mass)

	if has_node("Camera2D") and terrain.ground != null and terrain.ground.tile_set != null:
		var ts: TileSet = terrain.ground.tile_set
		var map_px: Vector2 = Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		$Camera2D.position = map_px * 0.5
		heatmap.set_layout(size, ts.tile_size)
		if heat_src != null:
			heat_src.set_layout(size, ts.tile_size)
		if crack_overlay != null:
			crack_overlay.set_layout(size)
		if liquid_overlay != null:
			liquid_overlay.set_layout(size, ts.tile_size)
		input.set_cell_size(ts.tile_size)
		corner_highlight.setup(ground_layer)

	temp.setup_from_tiles(tiles, size)
	_on_temperature_updated()

	if durability:
		durability.setup_from_tiles(tiles, size)

	if tchange:
		tchange.setup(tile_store, size, event_queue)
	if liquid:
		liquid.setup(data_layer, springs)
	if liquid_overlay != null:
		liquid_overlay.render(mass)

func _on_temperature_updated() -> void:
	var T := temp.get_temperature_buffer()
	var mask := temp.get_solid_mask()
	var vr := temp.get_visual_range() # Vector2(min, max)
	heatmap.render_full_with_mask(T, mask, vr.x, vr.y)
	
	# ΔT 기반 열원 오버레이 렌더
	if heat_src != null:
		var dT := temp.get_last_delta()
		heat_src.render_heat_sources(dT)

func _on_tick_sim(dt: float) -> void:
	if temp:
		temp.on_tick(dt)
	if liquid:
		liquid.tick_liquid(dt)
	if liquid_overlay != null:
		liquid_overlay.render(liquid.get_amounts())
	if tchange:
		var events := event_queue.pop_all()
		if events.size() > 0:
			tchange.apply_events(events)

func _on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if temp != null:
		temp.on_tile_destroyed(cell, from_tile, reason)
	if liquid != null:
		liquid.on_tile_destroyed(cell, from_tile, reason)

func _on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if temp != null:
		temp.on_tile_replaced(cell, from_tile, to_tile, reason)
	if liquid != null:
		liquid.on_tile_replaced(cell, from_tile, to_tile, reason)
	if durability != null:
		durability.on_tile_replaced(cell, from_tile, to_tile, reason)

func _on_pan_requested(delta: Vector2) -> void:
	if camera != null:
		camera.pan(delta)

func _on_zoom_requested(dir: float) -> void:
	if camera != null:
		camera.apply_zoom(dir)

func _on_overlay_toggle_requested(mode: OverlayManager.OverlayMode) -> void:
	overlay_manager.toggle_overlay(mode)

func _on_hover_changed(cell: Vector2i) -> void:
	corner_highlight.show_cell(cell)
	# TODO
