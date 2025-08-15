extends Node2D

@onready var terrain: Terrain = get_node("Terrain")
@onready var worldgen: WorldGen = get_node("Systems/WorldGen")
@onready var temp: Temperature = get_node("Systems/Temperature")
@onready var clock: SimClock = get_node("Systems/SimClock")
@onready var heatmap: HeatmapOverlay = get_node("Terrain/HeatmapOverlay")
@onready var ground_layer: TileMapLayer = get_node("Terrain/Ground")

func _ready() -> void:
	if worldgen == null:
		push_error("[World] Systems/WorldGen 노드를 찾지 못했습니다."); return
	if terrain == null:
		push_error("[World] Terrain 노드를 찾지 못했습니다."); return

	worldgen.generated.connect(_on_world_generated)
	temp.temperature_updated.connect(_on_temperature_updated)
	clock.tick_sim.connect(temp.on_tick)
	
	worldgen.generate()

func _on_world_generated(tiles: PackedInt32Array, size: Vector2i) -> void:
	terrain.apply_tiles(tiles, size)

	# 카메라 중앙으로
	if has_node("Camera2D") and terrain.ground != null and terrain.ground.tile_set != null:
		var ts: TileSet = terrain.ground.tile_set
		var map_px: Vector2 = Vector2(size.x * ts.tile_size.x, size.y * ts.tile_size.y)
		$Camera2D.position = map_px * 0.5
		# 히트맵 레이아웃도 타일 크기에 맞춰 설정
		heatmap.set_layout(size, ts.tile_size)

	# 온도 초기화 + 초기 렌더
	temp.setup_from_tiles(tiles, size)
	_on_temperature_updated()  # 첫 프레임 그리기

func _on_temperature_updated() -> void:
	var T := temp.get_temperature_buffer()
	var mask := temp.get_solid_mask()
	var vr := temp.get_visual_range()  # Vector2(min, max)
	heatmap.render_full_with_mask(T, mask, vr.x, vr.y)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo:
			# 방법 A) 직접 키코드 사용: T 키
			if e.keycode == KEY_T:
				_toggle_heatmap()
			# 방법 B) 액션 사용 (선호) — 아래 런타임 등록을 같이 쓰면 좋음
			elif Input.is_action_just_pressed("toggle_heatmap"):
				_toggle_heatmap()

func _toggle_heatmap() -> void:
	if heatmap == null:
		return
	heatmap.visible = not heatmap.visible
	var state: String = "ON" if heatmap.visible else "OFF"
	print("HeatmapOverlay: ", state)
