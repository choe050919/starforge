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
@onready var visual_sync: VisualSync =     %Systems/VisualSync

@onready var overlay_manager: OverlayManager = %OverlayManager
@onready var heatmap = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEATMAP) as HeatmapOverlay
@onready var heat_src = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEAT_SOURCE) as HeatSourceOverlay

@onready var tile_info_hud: TileInfoHUD = $UIFXLayer/TileInfoHUD
var tile_info_tracker: TileInfoTracker

@onready var hud: HUD = $HUD
var _is_running := true
var _speed_mult := 1.0

var tile_store: TileStore = TileStore.new()
var event_queue: EventQueue = EventQueue.new()
var data_layer: DataLayer = DataLayer.new()

var substance_loader: SubstanceLoader = SubstanceLoader.new()
var rule_cache := SubstanceRuleCache.new()

@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	hud.play_toggled.connect(_on_hud_play)
	hud.speed_selected.connect(_on_hud_speed)
	hud.overlay_toggled.connect(_on_hud_overlay)

	# 초기 상태를 HUD와 동기화
	hud.set_state(_is_running, _speed_mult, liquid_overlay.visible, heatmap.visible)

	substance_loader.load_materials()
	rule_cache.load_from_file("res://substance/substance.json")

	hover_service.setup(data_layer)

	input.setup(data_layer, hover_service)
	input.pan_requested.connect(_on_pan_requested)
	input.zoom_requested.connect(_on_zoom_requested)
	input.overlay_toggle_requested.connect(_on_overlay_toggle_requested)

	hover_service.hover_changed.connect(_on_hover_changed)

	tile_info_tracker = tile_info_hud.get_node("TileInfoTracker") as TileInfoTracker

	# connect signals
	worldgen.generated.connect(_on_world_generated)
	#temp.temperature_updated.connect(_on_temperature_updated) !!!!!!!!!

	worldgen.bind_rule_cache(rule_cache)

	worldgen.generate()

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
		temperatures: PackedInt32Array,
		tiles: PackedInt32Array,
		springs: PackedVector2Array
	) -> void:
	terrain.apply_tiles(tiles, size)
	tile_store.setup(tiles, size)
	data_layer.setup(size, substances, phases, mass, temperatures)

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

	durability.setup_from_tiles(tiles, size)

	tchange.setup(tile_store, size, event_queue)

	liquid.setup(data_layer, springs)
	liquid.set_liquid_sids()

	liquid_overlay.render(mass)

	temp.setup(data_layer.substance, data_layer.phase, data_layer.temperature, data_layer.mass, data_layer.index, clock, rule_cache)

	phase_change.setup(data_layer.phase, data_layer.substance, data_layer.temperature, data_layer.index, visual_sync, clock, rule_cache)

	tile_info_hud.setup(hover_service, data_layer.index, data_layer.substance, data_layer.phase, data_layer.mass, data_layer.temperature)

	clock.tick_sim.connect(_on_tick_sim)

var sim_time := 0.0

func _on_tick_sim(tag: StringName, dt: float) -> void:
	sim_time += dt
	match tag:
		"sim":
			# 기본 10Hz 틱
			phase_change._on_sim_tick(dt, sim_time)
			liquid.tick_liquid(dt)
			var events := event_queue.pop_all()
			if events.size() > 0:
				tchange.apply_events(events)
			liquid_overlay.render(liquid.get_amounts())
			if overlay_manager.current_overlay == OverlayManager.OverlayMode.HEATMAP:
				_on_temperature_updated() # TODO: 이름 변경
		"temp":
			temp._on_sim_tick(dt)
		_:
			push_error("[World._on_tick_sim] wrong tag")

func _on_temperature_updated() -> void: # 이름이 부적절함.
	var T_ck: PackedInt32Array = data_layer.temperature.get_read()
	var mask: PackedByteArray = data_layer.phase.get_read()
	heatmap.render_full_with_mask(T_ck, mask)

	# ΔT 기반 열원 오버레이 렌더
	#if heat_src != null:
		#var dT := temp.get_last_delta()
		#heat_src.render_heat_sources(dT)
	
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

func _on_hud_play(running: bool) -> void:
	_is_running = running
	# 제일 빠른 MVP: 전역 타임스케일만 조절
	Engine.time_scale = _speed_mult if _is_running else 0.0

func _on_hud_speed(mult: float) -> void:
	_speed_mult = mult
	# 전역 타임스케일 방식 (쉽다)
	Engine.time_scale = _speed_mult if _is_running else 0.0

	# 만약 전역이 아니라 SimClock만 빠르게 하고 싶다면:
	# sim_clock.sim_rate_hz = int(round(sim_clock.sim_rate_hz * mult))  # 권장X: 점프됨
	# -> 별도 설계가 필요. P0는 Engine.time_scale로 충분.

func _on_hud_overlay(name: StringName, enabled: bool) -> void:
	match name:
		&"water":
			if is_instance_valid(liquid_overlay):
				liquid_overlay.visible = enabled
		&"temp":
			if is_instance_valid(heatmap):
				heatmap.visible = enabled
