extends Node2D
class_name MiningVisual
## 플레이어 채굴 시각화: 플레이어와 대상 타일을 선으로 연결

@export var player_path: NodePath
@export var ground_path: NodePath

var _player: Node2D = null
var _ground: TileMapLayer = null
var _cell_size: Vector2 = Vector2(32, 32)

@export var line_color: Color = Color(1.0, 0.8, 0.2, 0.8)  # 노란색
@export var line_width: float = 2.0
@export var particle_enabled: bool = true
@export var particle_interval_sec: float = 0.1

var _particle_timer: float = 0.0

func _ready() -> void:
	if player_path != NodePath() and has_node(player_path):
		_player = get_node(player_path)
	
	if ground_path != NodePath() and has_node(ground_path):
		_ground = get_node(ground_path)
		if _ground and _ground.tile_set:
			_cell_size = _ground.tile_set.tile_size

func _process(delta: float) -> void:
	queue_redraw()
	
	# 파티클 효과 (선택)
	if particle_enabled and _is_player_mining():
		_particle_timer += delta
		if _particle_timer >= particle_interval_sec:
			_particle_timer = 0.0
			_spawn_particle()

func _draw() -> void:
	if not _is_player_mining():
		return
	
	var target_cell = _player.get_mining_target()
	if target_cell.x < -9998:
		return
	
	# 플레이어 위치
	var player_pos := _player.global_position
	
	# 타겟 셀 중심 (월드 좌표)
	var target_world := Vector2(target_cell) * _cell_size + _cell_size * 0.5
	if _ground:
		target_world = _ground.to_global(_ground.map_to_local(target_cell) + _cell_size * 0.5)
	
	# 선 그리기 (로컬 좌표로 변환)
	var local_player := to_local(player_pos)
	var local_target := to_local(target_world)
	
	draw_line(local_player, local_target, line_color, line_width)
	
	# 타겟 셀에 작은 원 표시
	draw_circle(local_target, 4.0, line_color)

func _is_player_mining() -> bool:
	if _player == null:
		return false
	if not _player.has_method("is_mining"):
		return false
	return _player.is_mining()

func _spawn_particle() -> void:
	# 간단한 파티클: 작은 점이 플레이어 → 타겟으로 날아가는 효과
	# 실제 구현은 CPUParticles2D나 간단한 Sprite 애니메이션으로
	pass
