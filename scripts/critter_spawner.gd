extends Node
class_name CritterSpawner

@export var critter_scene: PackedScene              # ← Critter 프리팹 씬
@export var _ground: Ground
@export var _Tchange: TileChange
@export var _dur: Durability
@export var only_inside_world: bool = true          # 월드 범위 바깥 클릭 무시

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

var data: DataLayer

func setup(_data: DataLayer):
	data = _data

func _spawn_at_mouse(scene := critter_scene) -> void:
	if scene == null or _ground == null:
		push_warning("[Spawner] Missing critter_scene or ground reference.")
		return
	# 마우스 → 셀
	var world_pos: Vector2 = get_viewport().get_mouse_position()
	# Camera2D가 변환해도 get_global_mouse_position()을 써도 됨
	world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
	var local: Vector2 = _ground.to_local(world_pos)
	var cell: Vector2i = _ground.local_to_map(local)

	# 월드 범위 체크(선택)
	if only_inside_world and _Tchange != null:
		if cell.x < 0 or cell.y < 0:
			return

	# 인스턴스 생성 → 의존성 주입 → 셀 중심으로 워프
	var critter := scene.instantiate()
	if critter == null or not (critter is Node2D):
		push_error("[Spawner] critter_scene must be a Node2D scene.")
		return
	# 보통은 Spawner와 같은 상위(Actors)에 붙임
	add_child(critter)
	print("[Spawner] %s가 생성됨" % critter.name)
	if critter is Fish:
		critter.setup(data, _ground)
	if (critter is CritterChanger or critter is CritterBuilder) and _Tchange != null:
		critter.set_dependencies(_Tchange, _ground)
	elif critter is CritterBreaker and _dur != null:
		critter.set_dependencies(_dur, _ground)
	if critter.has_method("warp_to_cell"):
		critter.warp_to_cell(cell)

func _on_sim_tick(_dt: float, sim_time: float):
	for actor in get_children():
		actor._on_sim_tick(_dt, sim_time)


func _on_tool_manager_request_spawn_fish(world_pos: Vector2, cell: Vector2i) -> void:
	_spawn_at_mouse()
