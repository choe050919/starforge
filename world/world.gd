extends Node2D
class_name World

@onready var terrain = $Terrain
@onready var ground_layer: TileMapLayer =        $Terrain/Ground
@onready var liquid_overlay: LiquidOverlay =     $Terrain/LiquidOverlay
@onready var crack_overlay: CrackOverlay =       $Terrain/CrackOverlay
@onready var corner_highlight: CornerHighlight = $Terrain/CornerHighlight

@onready var systems = %Systems
@onready var worldgen: WorldGen =          %Systems/WorldGen
@onready var durability: Durability =      %Systems/Durability
@onready var temp: Temperature =           %Systems/Temperature
@onready var clock: SimClock =             %Systems/SimClock
@onready var tchange: TileChange =         %Systems/TileChange
@onready var liquid: Liquid =              %Systems/Liquid
@onready var phase_change: PhaseChange =   %Systems/PhaseChange
@onready var input: InputController =      %Systems/InputController
@onready var hover_service: HoverService = %Systems/HoverService

@onready var overlay_manager: OverlayManager = %OverlayManager
@onready var heatmap = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEATMAP) as HeatmapOverlay
@onready var heat_src = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEAT_SOURCE) as HeatSourceOverlay

@onready var tile_info_hud: TileInfoHUD = $UIFXLayer/TileInfoHUD
var tile_info_tracker: TileInfoTracker

var tile_store: TileStore = TileStore.new()
var event_queue: EventQueue = EventQueue.new()
var material_db: MaterialDB = MaterialDB.new()
var data_layer: DataLayer = DataLayer.new()

@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	hover_service.setup(data_layer)

	input.setup(data_layer, hover_service)
	input.pan_requested.connect(_on_pan_requested)
	input.zoom_requested.connect(_on_zoom_requested)
	input.overlay_toggle_requested.connect(_on_overlay_toggle_requested)

	hover_service.hover_changed.connect(_on_hover_changed)

	tile_info_tracker = tile_info_hud.get_node("TileInfoTracker") as TileInfoTracker

	# connect signals
	worldgen.generated.connect(_on_world_generated)
	temp.temperature_updated.connect(_on_temperature_updated)

	worldgen.generate()

	clock.tick_sim.connect(_on_tick_sim)

	tchange.tile_destroyed.connect(_on_tile_destroyed)
	tchange.tile_replaced.connect(_on_tile_replaced)

	durability.break_requested.connect(func(cell: Vector2i): tchange.queue_destroy(cell, &"durability"))

	durability.hp_changed.connect(crack_overlay.on_hp_changed)
	durability.break_requested.connect(crack_overlay.on_break_requested)

func _on_world_generated(
		size: Vector2i,
		substances: PackedInt32Array,
		phases: PackedByteArray,
		mass: PackedInt64Array,
		tiles: PackedInt32Array,
		springs: PackedVector2Array
	) -> void:
	terrain.apply_tiles(tiles, size)
	tile_store.setup(tiles, size)
	data_layer.setup(size, substances, phases, mass)

	if ground_layer.tile_set != null: # 이중 검증임. 위의 apply_tiles에서 이미 검증.
		var ts: TileSet = ground_layer.tile_set
		var map_px: Vector2 = Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		camera.position = map_px * 0.5
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

	phase_change.setup(data_layer.phase, data_layer.substance, temp, data_layer.index, clock)

	tile_info_hud.setup(hover_service, data_layer.index, data_layer.substance, data_layer.phase, data_layer.mass)

func _on_temperature_updated() -> void:
	var T := temp.get_temperature_buffer()
	var mask:= temp.get_solid_mask()
	heatmap.render_full_with_mask(T, mask)

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
	camera.pan(delta)

func _on_zoom_requested(dir: float) -> void:
	if camera != null:
		camera.apply_zoom(dir)

func _on_overlay_toggle_requested(mode: OverlayManager.OverlayMode) -> void:
	overlay_manager.toggle_overlay(mode)

func _on_hover_changed(cell: Vector2i) -> void:
	corner_highlight.show_cell(cell)
	tile_info_tracker.on_hover_changed(cell)
