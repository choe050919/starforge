extends Node2D

@onready var terrain: Terrain = get_node("Terrain")
@onready var worldgen: WorldGen = get_node("Systems/WorldGen")
@onready var temp: Temperature = get_node("Systems/Temperature")
@onready var clock: SimClock = get_node("Systems/SimClock")
@onready var heatmap: HeatmapOverlay = get_node("Terrain/HeatmapOverlay")
@onready var ground_layer: TileMapLayer = get_node("Terrain/Ground")
@onready var tchange: TileChange = get_node("Systems/TileChange")
@onready var heat_src: HeatSourceOverlay = get_node("Terrain/HeatSourceOverlay")
@onready var durability: Durability = get_node("Systems/Durability")
@onready var crack_overlay: CrackOverlay = get_node("Terrain/CrackOverlay")

enum OverlayMode { NONE, HEATMAP, HEAT_SOURCE }

var current_overlay: int = OverlayMode.NONE

# 오버레이 경로 테이블 (존재하는 것만 등록)
var overlay_paths := {
	OverlayMode.HEATMAP:     NodePath("Terrain/HeatmapOverlay"),
	OverlayMode.HEAT_SOURCE: NodePath("Terrain/HeatSourceOverlay"),
}

func _ready() -> void:
	if worldgen == null:
		push_error("[World] Systems/WorldGen 노드를 찾지 못했습니다."); return
	if terrain == null:
		push_error("[World] Terrain 노드를 찾지 못했습니다."); return

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

	_apply_overlay_state() # 생략 가능

func _on_world_generated(tiles: PackedInt32Array, size: Vector2i) -> void:
	terrain.apply_tiles(tiles, size)

	# center camera on the map
	if has_node("Camera2D") and terrain.ground != null and terrain.ground.tile_set != null:
		var ts: TileSet = terrain.ground.tile_set
		var map_px: Vector2 = Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		$Camera2D.position = map_px * 0.5
		# adjust overlays to tile size
		heatmap.set_layout(size, ts.tile_size)
		if heat_src != null:
			heat_src.set_layout(size, ts.tile_size)
		if crack_overlay != null:
			crack_overlay.set_layout(size)

	# initialize temperature and first render
	temp.setup_from_tiles(tiles, size)
	_on_temperature_updated() # 첫 프레임 그리기

	if durability:
		durability.setup_from_tiles(tiles, size)

	if tchange:
		tchange.setup(tiles, size) # 타일 변경 시스템에 현재 맵 전달

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
	if tchange:
		tchange.commit() # 큐에 쌓인 변경을 일괄 적용

func _on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if temp != null:
		temp.on_tile_destroyed(cell, from_tile, reason)

func _on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if temp != null:
		temp.on_tile_replaced(cell, from_tile, to_tile, reason)
	if durability != null:
		durability.on_tile_replaced(cell, from_tile, to_tile, reason)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo:
			if e.keycode == KEY_T:
				toggle_overlay(OverlayMode.HEATMAP)
			elif e.keycode == KEY_Y:
				toggle_overlay(OverlayMode.HEAT_SOURCE)

func _get_overlay(mode: int) -> CanvasItem:
	if mode == OverlayMode.NONE:
		return null
	if not overlay_paths.has(mode):
		return null
	var path: NodePath = overlay_paths[mode]
	if not has_node(path):
		return null
	return get_node(path) as CanvasItem

func _apply_overlay_state() -> void:
	# 1) 모든 오버레이 끄기
	for m in overlay_paths.keys():
		var overlay_node := _get_overlay(m)
		if overlay_node != null:
			overlay_node.visible = false
	# 2) 현재 모드 켜기 (NONE이면 생략)
	if current_overlay != OverlayMode.NONE:
		var target_overlay := _get_overlay(current_overlay)
		if target_overlay != null:
			target_overlay.visible = true

func set_overlay(mode: int) -> void:
	if mode == current_overlay:
		print("overlay ERROR")
		return
	current_overlay = mode
	_apply_overlay_state()

	var name_str: String = "NONE"
	if mode == OverlayMode.HEATMAP:
		name_str = "HEATMAP"
	elif mode == OverlayMode.HEAT_SOURCE:
		name_str = "HEAT_SOURCE"
	print("[Overlay] ", name_str)

func toggle_overlay(mode: int) -> void:
	# 같은 모드를 다시 누르면 NONE으로 전환
	if current_overlay == mode:
		set_overlay(OverlayMode.NONE)
	else:
		set_overlay(mode)
