## 플레이어 채굴 시각화: 플레이어와 대상 타일을 선으로 연결하고, 라인 위로 파티클을 흘려보냄
class_name MiningVisual
extends Node2D

# ── 의존성 ───────────────────────────────────────────────────
@export var player_path: NodePath
@export var ground_path: NodePath

var _player: Player = null
var _ground: TileMapLayer = null

# ── 설정 ───────────────────────────────────────────────────
@export var line_color: Color = Color(1.0, 0.8, 0.2, 0.8)  # 노란색
@export var line_width: float = 2.0

@export var particle_enabled: bool = true
@export var particle_interval_sec: float = 0.1
@export var particle_speed: float = 2.0  # 초당 진행도
@export var particle_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var particle_radius: float = 3.0

# ── 상태 ───────────────────────────────────────────────────
var _cell_size: Vector2 = Vector2(32, 32)

var _particle_timer: float = 0.0
var _particles: Array[float] = []  # 각 파티클의 진행도 (0.0 → 1.0)

# ── 생명주기 ───────────────────────────────────────────────────
func _ready() -> void:
	_bind_dependencies()
	_cache_cell_size()

func _bind_dependencies() -> void:
	if player_path != NodePath() and has_node(player_path):
		_player = get_node(player_path)

	if ground_path != NodePath() and has_node(ground_path):
		_ground = get_node(ground_path)

func _cache_cell_size() -> void:
	if _ground and _ground.tile_set:
		_cell_size = _ground.tile_set.tile_size

func _process(delta: float) -> void:
	queue_redraw()
	
	_update_particles(delta)
	
	# 새 파티클 생성
	if particle_enabled and _is_player_mining():
		_particle_timer += delta
		if _particle_timer >= particle_interval_sec:
			_particle_timer = 0.0
			_spawn_particle()

func _draw() -> void:
	if not _is_player_mining():
		return
	
	var target_cell := _player.get_mining_target()
	if target_cell.x < -9998:
		return
	
	# 플레이어 위치 (월드 → 로컬)
	var player_local := to_local(_player.global_position)
	
	# 타겟 셀 중심 (월드 → 로컬)
	var target_world: Vector2
	if _ground:
		target_world = _ground.to_global(_ground.map_to_local(target_cell))
	else:
		target_world = Vector2(target_cell) * _cell_size + _cell_size * 0.5
	var target_local := to_local(target_world)
	
	# 선 + 타겟 표시
	draw_line(player_local, target_local, line_color, line_width)
	draw_circle(target_local, 4.0, line_color)
	
	# 파티클
	for progress in _particles:
		var pos := player_local.lerp(target_local, progress)
		draw_circle(pos, particle_radius, particle_color)

# ── 내부: 채굴 상태 ───────────────────────────────────────────
func _is_player_mining() -> bool:
	if _player == null:
		return false
	if not _player.has_method("is_mining"):
		return false
	return _player.is_mining()

# ── 내부: 파티클 ─────────────────────────────────────────────
func _update_particles(delta: float) -> void:
	var i := 0
	while i < _particles.size():
		_particles[i] += delta * particle_speed
		if _particles[i] >= 1.0:
			_particles.remove_at(i)
		else:
			i += 1

func _spawn_particle() -> void:
	_particles.append(0.0)
