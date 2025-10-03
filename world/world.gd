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

# ── Actors ───────────────────────────────────────────────────────
@onready var spawner: CritterSpawner = %Spawner

# ── UI ───────────────────────────────────────────────────────────
@onready var tile_info_hud: TileInfoHUD = $UIFXLayer/TileInfoHUD
@onready var hud: HUD = $HUD

# ── State ────────────────────────────────────────────────────────
var _is_running := true
var _speed_mult := 1.0

# ── Data & Caches ────────────────────────────────────────────────
var data_layer: DataLayer = DataLayer.new()

var substance_loader: SubstanceLoader = SubstanceLoader.new()
var rule_cache := SubstanceRuleCache.new()

@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	# HUD 연결
	hud.play_toggled.connect(_on_hud_play)
	hud.speed_selected.connect(_set_speed_multiplier)
	hud.overlay_toggled.connect(_on_hud_overlay)
	hud.set_state(_is_running, _speed_mult, liquid_overlay.visible, heatmap.visible)

	# 룰/소재 로드
	substance_loader.load_materials()
	rule_cache.load_from_file("res://substance/substance.json")

	# 입력/호버
	hover.setup(data_layer)
	input.setup(data_layer, hover)
	input.pan_requested.connect(_pan_camera)
	input.zoom_requested.connect(_zoom_camera)
	input.overlay_toggle_requested.connect(_on_overlay_toggle_requested)
	hover.hover_changed.connect(_on_hover_changed)

	# 월드 생성
	worldgen.generated.connect(_on_world_generated)
	worldgen.bind_rule_cache(rule_cache)
	worldgen.generate()

	# 내구도↔타일 변경, 크랙 오버레이
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
	_apply_worldgen_result(size, substances, phases, mass, temperatures, tiles, springs)
	_post_apply_worldgen(size, mass)

## 월드 생성 결과를 '상태'로 적용한다.
## - 타일, DataLayer, 시뮬 시스템들의 setup
## - 여기까지 끝나면 '그려지기 직전의 세계'가 준비된 상태여야 한다.
func _apply_worldgen_result(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	temperatures: PackedInt32Array,
	tiles: PackedInt32Array,
	springs: PackedVector2Array
) -> void:
	# 시각화/데이터
	ground.apply_tiles(tiles, size)

	visual_sync.setup(data_layer)

	data_layer.setup(size, substances, phases, mass, temperatures)

	data_layer.tiles_changed.connect(visual_sync.on_tiles_changed)

	# 시스템들 (데이터 준비 이후)
	durability.setup_from_tiles(tiles, size)
	temp.setup(data_layer, rule_cache)
	tchange.setup(data_layer)
	liquid.setup(data_layer, springs); liquid.set_liquid_sids()
	phase_change.setup(data_layer, rule_cache)
	light.setup(data_layer, rule_cache)
	plant.setup(data_layer.index)
	plant.set_soil_checker(func(cell: Vector2i) -> bool: # TODO sid hardcoding
		return data_layer.substance.get_by_cell(cell) == 10002
	)
	plant.set_light_sampler(Callable(data_layer.light, "get_by_cell"))
	grid_nav.setup(data_layer)

## 적용 이후 후처리:
## - 카메라/오버레이 레이아웃(타일셋/맵 크기 필요)
## - 초기 렌더
## - HUD/툴 UI 동기화
## - SimClock 배선
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
	# light_overlay는 초기 렌더 X.

	# HUD의 타일 정보(온도 포함) 데이터 배선
	tile_info_hud.setup(data_layer, hover)

	spawner.setup(data_layer, plant)

	# 시뮬 배선
	if not clock.tick_sim.is_connected(_on_sim_clock_tick):
		clock.tick_sim.connect(_on_sim_clock_tick)

var sim_time := 0.0

## SimClock에서 올라오는 틱 이벤트를 처리한다.
## 인자:
##   tag: "sim" | "temp" (시뮬 틱 종류)
##   dt:  해당 틱의 경과 시간(초)
## 동작:
##   - "sim": PhaseChange → Liquid → Event 적용 → Liquid Overlay 렌더 → (옵션)Heatmap 갱신
##   - "temp": 온도 전용 연산 틱
## 부가작용: data_layer 내부 상태 변경, 오버레이 렌더 호출
func _on_sim_clock_tick(tag: StringName, dt: float) -> void:
	sim_time += dt
	match tag:
		"sim":
			# 기본 10Hz 틱
			phase_change._on_sim_tick(dt, sim_time)
			liquid.tick_liquid(dt)
			liquid_overlay.render(liquid.get_amounts())
			spawner._on_sim_tick(dt, sim_time)
			light._on_sim_tick(dt)
			plant.tick(dt)
		"temp":
			temp._on_sim_tick(dt)
		_:
			push_error("[World._on_sim_clock_tick] wrong tag: %s" % [str(tag)])

# ── Input / HUD ──────────────────────────────────────────────────
func _pan_camera(delta: Vector2) -> void:
	camera.pan(delta)

func _zoom_camera(dir: float) -> void:
	if camera != null:
		camera.apply_zoom(dir)

func _on_overlay_toggle_requested(mode: OverlayManager.OverlayMode) -> void:
	overlay_manager.toggle_overlay(mode)

func _on_hover_changed(cell: Vector2i) -> void:
	corner_highlight.show_cell(cell)
	tile_info_hud.on_hover_changed(cell)

func _on_hud_play(running: bool) -> void:
	_is_running = running
	# 제일 빠른 MVP: 전역 타임스케일만 조절
	Engine.time_scale = _speed_mult if _is_running else 0.0

func _set_speed_multiplier(mult: float) -> void:
	_speed_mult = mult
	# 전역 타임스케일 방식 (쉽다)
	Engine.time_scale = _speed_mult if _is_running else 0.0

	# 만약 전역이 아니라 SimClock만 빠르게 하고 싶다면:
	# sim_clock.sim_rate_hz = int(round(sim_clock.sim_rate_hz * mult))  # 권장X: 점프됨
	# -> 별도 설계가 필요. P0는 Engine.time_scale로 충분.

func _on_hud_overlay(overlay_name: StringName, enabled: bool) -> void:
	match overlay_name:
		&"water":
			if is_instance_valid(liquid_overlay):
				liquid_overlay.visible = enabled
		&"temp":
			if is_instance_valid(heatmap):
				heatmap.visible = enabled

var _spec_amphib := preload("res://plants/specs/amphibious_spec.tres")

func _on_tool_manager_request_spawn_plant(cell: Vector2i) -> void:
	if _spec_amphib == null:
		push_error("[PlantTest] spec is null")
		return
	# 자리 가능 검사 → 배치
	if plant.can_place(_spec_amphib, cell):
		var id := plant.place(_spec_amphib, cell, 1.0)
		if id < 0:
			push_warning("[PlantTest] place failed (unknown)")
	else:
		push_warning("[PlantTest] cannot place: not_soil/out_of_bounds/occupied")

@onready var agent: AnimalAgent = $Actors/AnimalAgent

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_G:  # G 키 → 마우스 위치로 이동
				agent.move_to_world(get_global_mouse_position())
			KEY_S:  # S 키 → 정지
				agent.stop()
			KEY_F:  # F 키 → 플레이어 따라가기
				if has_node("Player"):
					agent.follow_node($Player)
