extends Node2D
class_name World

# ── VisualSync ───────────────────────────────────────────────────
@onready var visual_sync: VisualSync = %VisualSync
@onready var ground: Ground = %Ground

# ── Overlay Manager ──────────────────────────────────────────────
@onready var overlay_manager: OverlayManager = %OverlayManager
@onready var heatmap = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEATMAP) as HeatmapOverlay
@onready var heat_src = overlay_manager.get_overlay(OverlayManager.OverlayMode.HEAT_SOURCE) as HeatSourceOverlay
@onready var light_overlay = overlay_manager.get_overlay(OverlayManager.OverlayMode.LIGHT) as LightOverlay

# ── Terrain & Overlays ───────────────────────────────────────────
@onready var terrain = $Terrain
@onready var liquid_overlay: LiquidOverlay =     $Terrain/LiquidOverlay
@onready var crack_overlay: CrackOverlay =       $Terrain/CrackOverlay
@onready var corner_highlight: CornerHighlight = $Terrain/CornerHighlight

# ── Systems ──────────────────────────────────────────────────────
@onready var worldgen:     WorldGen        = %WorldGen
@onready var durability:   Durability      = %Durability
@onready var temp:         Temperature     = %Temperature
@onready var clock:        SimClock        = %SimClock
@onready var tchange:      TileChange      = %TileChange
@onready var liquid:       Liquid          = %Liquid
@onready var phase_change: PhaseChange     = %PhaseChange
@onready var input:        InputController = %InputController
@onready var hover:        HoverManager    = %HoverManager
@onready var light:        Light           = %Light
@onready var plant:        Plant           = %Plant
@onready var grid_nav:     GridNav         = %GridNav
@onready var mining:       Mining          = %Mining
@onready var construction: Construction    = %Construction

# ── Items ────────────────────────────────────────────────────────
@onready var ground_item_registry: GroundItemRegistry = %GroundItemRegistry

# ── Actors ───────────────────────────────────────────────────────
@onready var spawner: CritterSpawner = %Spawner
@onready var player: Player =          %Player

# ── UI ───────────────────────────────────────────────────────────
@onready var tile_info_hud: TileInfoHUD = $UIFXLayer/TileInfoHUD
@onready var hud: HUD = $HUD
@onready var mining_visual: MiningVisual = %MiningVisual

@onready var camera: Camera2D = $Camera2D

# ── State ────────────────────────────────────────────────────────
var _is_running := true
var _speed_mult := 1.0
var _sim_time := 0.0
var _world_ready := false  # 월드 초기화 완료 플래그

# ── Data & Caches ────────────────────────────────────────────────
var data_layer: DataLayer = DataLayer.new()
var substance_loader: SubstanceLoader = SubstanceLoader.new()
var rule_cache := SubstanceRuleCache.new()

# ══════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	# SimClock 자동 시작 방지
	clock.set_process(false)
	
	_setup_hud()

	# 리소스 로딩 실패 시 게임 중단
	if not _load_resources():
		push_error("[World] ❌ CRITICAL: Resource loading failed. Cannot continue.")
		_show_error_and_quit("Critical resources failed to load.\nPlease check the console for details.")
		return

	_setup_input_and_hover()
	_setup_worldgen()
	_setup_durability()
	_setup_player()
	_setup_construction()
	_setup_mining_visual()

# ── Setup Helpers ────────────────────────────────────────────────

func _setup_hud() -> void:
	hud.play_toggled.connect(_on_hud_play)
	hud.speed_selected.connect(_set_speed_multiplier)
	hud.overlay_toggled.connect(_on_hud_overlay)
	hud.set_state(_is_running, _speed_mult, liquid_overlay.visible, heatmap.visible)

## 개선된 리소스 로딩 (검증 포함)
func _load_resources() -> bool:
	print("[World] ═══════════════════════════════════════")
	print("[World] Loading critical resources...")
	
	# Substance loader
	substance_loader.load_materials()
	
	# Substance rules 로드 (명시적 경로)
	var json_path := "res://datalayer/substance/substance.json"
	
	# 파일 존재 확인 (선행 검증)
	if not FileAccess.file_exists(json_path):
		push_error("[World] Substance JSON not found at: ", json_path)
		push_error("[World] Please ensure the file exists at the correct location.")
		return false
	
	print("[World] Loading substance rules from: ", json_path)
	var load_success := rule_cache.load_from_file(json_path)
	
	if not load_success:
		push_error("[World] Failed to load substance rules!")
		push_error("[World] Game cannot continue without substance data.")
		return false
	
	# 최종 검증: 필수 데이터 확인
	if rule_cache.phase_of_sid.is_empty():
		push_error("[World] Substance cache is empty after loading!")
		return false
	
	if rule_cache.k_by_sid.is_empty() and rule_cache.c_by_sid.is_empty():
		push_warning("[World] ⚠️ No thermal properties loaded (k, c are empty)")
	
	print("[World] Successfully loaded %d substances" % rule_cache.phase_of_sid.size())
	print("[World] ═══════════════════════════════════════")
	return true

## 에러 표시 및 게임 종료
func _show_error_and_quit(message: String) -> void:
	# 에디터에서는 즉시 종료하지 않고 경고만 출력
	if OS.has_feature("editor"):
		push_error("[World] ", message)
		push_error("[World] Running in editor - game not terminated")
		# 에디터에서는 계속 실행 (디버깅 편의)
		return
	
	# 배포 빌드에서는 에러 다이얼로그 표시 후 종료
	printerr(message)
	OS.alert(message, "Critical Error")
	get_tree().quit()

func _setup_input_and_hover() -> void:
	hover.setup(data_layer)
	input.setup(data_layer, hover)
	
	input.pan_requested.connect(_pan_camera)
	input.zoom_requested.connect(_zoom_camera)
	input.overlay_toggle_requested.connect(_on_overlay_toggle_requested)
	input.player_move_requested.connect(_on_player_move_requested)
	input.mining_requested.connect(_on_mining_requested)
	input.pickup_requested.connect(_on_pickup_requested)
	
	hover.hover_changed.connect(_on_hover_changed)

func _setup_worldgen() -> void:
	worldgen.bind_rule_cache(rule_cache)
	worldgen.generated.connect(_on_world_generated)
	worldgen.generate()

func _setup_durability() -> void:
	durability.break_requested.connect(_on_durability_break)
	durability.break_requested.connect(crack_overlay.on_break_requested)

func _setup_player() -> void:
	# 기존 경로들
	player.grid_nav_path = NodePath("%GridNav")
	player.overlay_path = NodePath("%OverlayManager/OverlayLayer/NavigationOverlay")
	player.mining_path = NodePath("%Mining")
	
	# 인벤토리용 경로 추가
	player.ground_item_registry_path = NodePath("%GroundItemRegistry")
	
	# DataLayer 설정
	player.setup(data_layer)
	
	# 인벤토리 변경 신호 연결 (UI 업데이트용)
	player.inventory_changed.connect(_on_player_inventory_changed)

func _setup_construction() -> void:
	# Construction 경로 설정
	construction.player_path = NodePath("%Player")
	construction.tile_change_path = NodePath("%TileChange")
	
	# DataLayer 설정
	construction.setup(data_layer)
	
	# ToolManager 신호 연결
	if input._tool_manager:
		input._tool_manager.request_construct.connect(_on_construct_requested)
		input._tool_manager.request_construct_ladder.connect(_on_construct_ladder_requested)

func _setup_mining_visual() -> void:
	mining_visual.player_path = NodePath("../Actors/Player")
	mining_visual.ground_path = NodePath("%Ground")

# ══════════════════════════════════════════════════════════════════
# World Generation
# ══════════════════════════════════════════════════════════════════

func _on_world_generated(
		size: Vector2i,
		substances: PackedInt32Array,
		phases: PackedByteArray,
		mass: PackedInt64Array,
		temperatures: PackedInt32Array,
		tiles: PackedInt32Array,
		springs: PackedVector2Array
) -> void:
	_apply_worldgen_result(size, substances, phases, mass, temperatures, tiles, springs)
	_post_apply_worldgen(size, mass)

## 월드 생성 결과를 '상태'로 적용한다.
func _apply_worldgen_result(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	temperatures: PackedInt32Array,
	tiles: PackedInt32Array,
	springs: PackedVector2Array
) -> void:
	_setup_visual_layer(tiles, size)
	_setup_data_layer(size, substances, phases, mass, temperatures)
	_setup_simulation_systems(springs)

func _setup_visual_layer(tiles: PackedInt32Array, size: Vector2i) -> void:
	ground.apply_tiles(tiles, size)
	visual_sync.setup(data_layer)

func _setup_data_layer(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	temperatures: PackedInt32Array
) -> void:
	data_layer.setup(size, substances, phases, mass, temperatures)
	data_layer.bind_rule_cache(rule_cache)
	data_layer.tiles_changed.connect(visual_sync.on_tiles_changed)

func _setup_simulation_systems(springs: PackedVector2Array) -> void:
	durability.setup(data_layer)
	
	temp.setup(data_layer, rule_cache)
	
	tchange.setup(data_layer)
	
	liquid.setup(data_layer, springs)
	liquid.set_liquid_sids()
	
	phase_change.setup(data_layer, rule_cache)
	
	light.setup(data_layer, rule_cache)
	
	plant.setup(data_layer.index)
	plant.set_soil_checker(_is_soil)
	plant.set_light_sampler(Callable(data_layer.light, "get_by_cell"))
	
	grid_nav.setup(data_layer)
	
	mining.setup(data_layer)

## 적용 이후 후처리 + SimClock 시작
func _post_apply_worldgen(size: Vector2i, initial_mass: PackedInt64Array) -> void:
	# 레이아웃 (타일셋 크기 참조)
	if ground.tile_set != null:
		var ts: TileSet = ground.tile_set
		var map_px := Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		camera.position = map_px * 0.5
		input.set_cell_size(ts.tile_size)
		if liquid_overlay != null: liquid_overlay.set_layout(size, ts.tile_size)
		if crack_overlay != null: crack_overlay.set_layout(size)
		if heatmap != null: heatmap.set_layout(size, ts.tile_size)
		if heat_src != null: heat_src.set_layout(size, ts.tile_size)
		if light_overlay != null: light_overlay.set_layout(size, ts.tile_size)
	else:
		push_error("[World._on_world_generated] tileset is null"); return

	corner_highlight.setup(ground)

	# 초기 렌더
	liquid_overlay.render(initial_mass)

	# HUD의 타일 정보(온도 포함) 데이터 배선
	tile_info_hud.setup(data_layer, hover)

	spawner.setup(data_layer, plant)

	# 시뮬 배선
	if not clock.tick_sim.is_connected(_on_sim_clock_tick):
		clock.tick_sim.connect(_on_sim_clock_tick)
	
	# 월드 준비 완료 플래그 설정
	_world_ready = true
	
	# SimClock 시작
	clock.set_process(true)
	
	print("[World] World setup complete, SimClock started")

var sim_time := 0.0

# ══════════════════════════════════════════════════════════════════
# Simulation Tick
# ══════════════════════════════════════════════════════════════════

## SimClock에서 올라오는 틱 이벤트를 처리한다.
func _on_sim_clock_tick(tag: StringName, dt: float) -> void:
	# 월드가 준비되지 않았으면 무시 (이중 안전장치)
	if not _world_ready:
		push_warning("[World] SimClock tick ignored: world not ready yet")
		return
	
	_sim_time += dt
	
	match tag:
		"sim":
			_tick_simulation(dt)
		"temp":
			_tick_temperature(dt)
		_:
			push_error("[World] Invalid tick tag: %s" % tag)

func _tick_simulation(dt: float) -> void:
	phase_change._on_sim_tick(dt, _sim_time)
	liquid.tick_liquid(dt)
	liquid_overlay.render(liquid.get_amounts())
	spawner._on_sim_tick(dt, _sim_time)
	light._on_sim_tick(dt)
	plant.tick(dt)

func _tick_temperature(dt: float) -> void:
	temp._on_sim_tick(dt)

# ══════════════════════════════════════════════════════════════════
# Input & Camera Handlers
# ══════════════════════════════════════════════════════════════════

func _pan_camera(delta: Vector2) -> void:
	camera.pan(delta)

func _zoom_camera(dir: float) -> void:
	if camera:
		camera.apply_zoom(dir)

func _on_overlay_toggle_requested(mode: OverlayManager.OverlayMode) -> void:
	overlay_manager.toggle_overlay(mode)

func _on_hover_changed(cell: Vector2i) -> void:
	corner_highlight.show_cell(cell)
	tile_info_hud.on_hover_changed(cell)

func _on_player_move_requested(world_pos: Vector2) -> void:
	if is_instance_valid(player):
		player.move_to_world(world_pos)

func _on_mining_requested(cell: Vector2i) -> void:
	if is_instance_valid(player):
		player.add_mining_target(cell)

func _on_pickup_requested(cell: Vector2i) -> void:
	if is_instance_valid(player):
		var success := player.pickup_item_at_cell(cell)
		if success:
			print("[World] Pickup successful at cell=", cell)
		else:
			print("[World] Pickup failed at cell=", cell)

func _on_player_inventory_changed(material_sid: int, mass_mg: int) -> void:
	# UI 업데이트 로직 (나중에 인벤토리 UI 추가 시 사용)
	if material_sid < 0:
		print("[World] Inventory: Empty")
	else:
		var mass_kg := float(mass_mg) / 1_000_000.0
		print("[World] Inventory: SID=", material_sid, " Mass=", mass_kg, "kg (", mass_mg, "mg)")
	
	# TODO: 인벤토리 UI 업데이트
	# if inventory_ui:
	#     inventory_ui.update_display(material_sid, mass_mg)

func _on_construct_requested(cell: Vector2i) -> void:
	if not is_instance_valid(construction):
		return
	
	if not is_instance_valid(player):
		return
	
	# 플레이어가 들고 있는 재료로 건설 시도
	var material_sid := player.get_inventory_material_sid()
	if material_sid < 0:
		print("[World] Construction failed: no material in inventory")
		return
	
	var success := construction.place_tile(cell, material_sid)
	if success:
		print("[World] Construction successful at cell=", cell)
	else:
		print("[World] Construction failed at cell=", cell)

func _on_construct_ladder_requested(cell: Vector2i) -> void:
	if not is_instance_valid(construction):
		return
	
	var success := construction.place_ladder(cell)
	if success:
		print("[World] Ladder construction successful at cell=", cell)
	else:
		print("[World] Ladder construction failed at cell=", cell)

# ══════════════════════════════════════════════════════════════════
# HUD Handlers
# ══════════════════════════════════════════════════════════════════

func _on_hud_play(running: bool) -> void:
	_is_running = running
	Engine.time_scale = _speed_mult if _is_running else 0.0

func _set_speed_multiplier(mult: float) -> void:
	_speed_mult = mult
	Engine.time_scale = _speed_mult if _is_running else 0.0

func _on_hud_overlay(overlay_name: StringName, enabled: bool) -> void:
	match overlay_name:
		&"water":
			if is_instance_valid(liquid_overlay):
				liquid_overlay.visible = enabled
		&"temp":
			if is_instance_valid(heatmap):
				heatmap.visible = enabled

# ══════════════════════════════════════════════════════════════════
# Event Handlers
# ══════════════════════════════════════════════════════════════════

func _on_durability_break(cell: Vector2i) -> void:
	tchange.destroy_cell(cell, &"durability")

# ══════════════════════════════════════════════════════════════════
# Utility Functions
# ══════════════════════════════════════════════════════════════════

func _is_soil(cell: Vector2i) -> bool:
	return data_layer.substance.get_by_cell(cell) == 10002

var _spec_amphib := preload("res://systems/plants/specs/amphibious_spec.tres")

# ══════════════════════════════════════════════════════════════════
# Debug/Development Functions
# ══════════════════════════════════════════════════════════════════

func _on_tool_manager_request_spawn_plant(cell: Vector2i) -> void:
	if _spec_amphib == null:
		push_error("[PlantTest] spec is null")
		return
	if plant.can_place(_spec_amphib, cell):
		var id := plant.place(_spec_amphib, cell, 1.0)
		if id < 0:
			push_warning("[PlantTest] place failed (unknown)")
	else:
		push_warning("[PlantTest] cannot place: not_soil/out_of_bounds/occupied")

func _on_tool_manager_request_add_temp(cell: Vector2i) -> void:
	var old_temp := data_layer.temperature.get_by_cell(cell)
	var new_temp := old_temp + 1000
	data_layer.set_cell_with_spec(cell, {"temp" : new_temp})
