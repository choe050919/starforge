extends Node
class_name CritterSpawner

@export var critter_scene: PackedScene              # ← Critter 프리팹 씬
@export_node_path("TileMapLayer") var ground_path   # ← Terrain/Ground를 지정
@export_node_path("Node") var tile_change_path      # ← Systems/TileChange를 지정
@export_node_path("Node") var durability_path       # ← Systems/Durability를 지정
@export var only_inside_world: bool = true          # 월드 범위 바깥 클릭 무시

var _ground: TileMapLayer
var _sys: TileChange
var _dur: Durability
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if ground_path != NodePath():
		_ground = get_node(ground_path) as TileMapLayer
	if tile_change_path != NodePath():
		_sys = get_node(tile_change_path) as TileChange
	if durability_path != NodePath():
		_dur = get_node(durability_path) as Durability
	_rng.randomize()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_spawn_at_mouse()

func _spawn_at_mouse() -> void:
	if critter_scene == null or _ground == null:
		push_warning("[Spawner] Missing critter_scene or ground reference.")
		return
	# 마우스 → 셀
	var world_pos: Vector2 = get_viewport().get_mouse_position()
	# Camera2D가 변환해도 get_global_mouse_position()을 써도 됨
	world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
	var local: Vector2 = _ground.to_local(world_pos)
	var cell: Vector2i = _ground.local_to_map(local)

	# 월드 범위 체크(선택)
	if only_inside_world and _sys != null and _sys.size != Vector2i.ZERO:
		if cell.x < 0 or cell.y < 0 or cell.x >= _sys.size.x or cell.y >= _sys.size.y:
			return

	# 인스턴스 생성 → 의존성 주입 → 셀 중심으로 워프
	var critter := critter_scene.instantiate()
	if critter == null or not (critter is Node2D):
		push_error("[Spawner] critter_scene must be a Node2D scene.")
		return
	# 보통은 Spawner와 같은 상위(Actors)에 붙임
	add_child(critter)
	if critter is CritterChanger and _sys != null:
		critter.set_dependencies(_sys, _ground)
	elif critter is CritterBreaker and _dur != null:
		critter.set_dependencies(_dur, _ground)
	if critter.has_method("warp_to_cell"):
		critter.warp_to_cell(cell)
