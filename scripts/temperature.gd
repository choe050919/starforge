extends Node
class_name Temperature

signal initialized(size: Vector2i)
signal temperature_updated()  # MVP: 전체 갱신(부분 갱신은 이후)

# ---- 설정값(필요 시 인스펙터에서 조절) ----
@export var k_ground: float = 0.9      # 열전도(상대값)
@export var k_ice: float = 0.4
@export var k_uranium: float = 0.8
@export var c_ground: float = 1.0      # 열용량(상대값)
@export var c_ice: float = 0.8
@export var c_uranium: float = 1.0

@export var t_ground_init: float = 12.0
@export var t_ice_init: float = -5.0
@export var t_uranium_init: float = 12.0
@export var t_min_vis: float = -20.0   # 히트맵 표시 최소/최대(시각화용)
@export var t_max_vis: float = 40.0

# 우라늄 열원 세기(초당 ΔT)
@export var uranium_power_per_sec: float = 3.0

# 우라늄 위치 인덱스 목록
var _uranium_cells: PackedInt32Array = PackedInt32Array()

# ---- 내부 상태 ----
var size: Vector2i
var T: PackedFloat32Array        # 현재 온도
var alpha: PackedFloat32Array    # 확산계수 α = k/(c) (ρ는 상대값에 흡수)
var solid_mask: PackedByteArray  # 1=고체(전달), 0=빈칸(현재는 전달 안 함)
var _last_delta: PackedFloat32Array

# 타일 ID
const TILE_AIR := 0
const TILE_ICE := 1
const TILE_GROUND := 2
const TILE_URANIUM := 3

func setup_from_tiles(tile_types: PackedInt32Array, grid_size: Vector2i) -> void:
	size = grid_size
	var total := size.x * size.y
	T = PackedFloat32Array(); T.resize(total)
	alpha = PackedFloat32Array(); alpha.resize(total)
	solid_mask = PackedByteArray(); solid_mask.resize(total)
	_last_delta = PackedFloat32Array(); _last_delta.resize(total)

	for y in size.y:
		for x in size.x:
			var idx := y * size.x + x
			var tt := tile_types[idx]
			match tt:
				TILE_GROUND:
					T[idx] = t_ground_init
					alpha[idx] = k_ground / max(0.0001, c_ground)
					solid_mask[idx] = 1
				TILE_ICE:
					T[idx] = t_ice_init
					alpha[idx] = k_ice / max(0.0001, c_ice)
					solid_mask[idx] = 1
				TILE_URANIUM:
					T[idx] = t_uranium_init
					alpha[idx] = k_uranium / max(0.0001, c_uranium)
					solid_mask[idx] = 1
					_uranium_cells.append(idx)              # ← 우라늄 셀 기록
				_:
					# AIR: 계산 제외(마스크 0), 온도는 보조값이나 0으로 둠
					T[idx] = 0.0
					alpha[idx] = 0.0
					solid_mask[idx] = 0

	emit_signal("initialized", size)
	emit_signal("temperature_updated")

func on_tick(dt: float) -> void:
	if T.is_empty():
		return

	var Tnew := _diffuse(dt)
	_apply_uranium_heating(dt, Tnew)
	_compute_delta(Tnew)
	T = Tnew
	emit_signal("temperature_updated")

func _diffuse(dt: float) -> PackedFloat32Array:
	var w: int = size.x
	var h: int = size.y
	var Tnew: PackedFloat32Array = PackedFloat32Array()
	Tnew.resize(T.size())

	for y in h:
		for x in w:
			var idx: int = y * w + x

			# 공기는 그대로 둠
			if solid_mask[idx] == 0:
				Tnew[idx] = T[idx]
				continue

			var t_center: float = T[idx]

			# --- 이웃 평균 기반 업데이트 (최댓값 원리 보장) ---
			var sum_n: float = 0.0
			var n: int = 0

			# 위
			var yy: int = max(0, y - 1)
			var idx_n: int = yy * w + x
			if solid_mask[idx_n] == 1:
				sum_n += T[idx_n]; n += 1
			# 아래
			yy = min(h - 1, y + 1)
			idx_n = yy * w + x
			if solid_mask[idx_n] == 1:
				sum_n += T[idx_n]; n += 1
			# 왼쪽
			var xx: int = max(0, x - 1)
			idx_n = y * w + xx
			if solid_mask[idx_n] == 1:
				sum_n += T[idx_n]; n += 1
			# 오른쪽
			xx = min(w - 1, x + 1)
			idx_n = y * w + xx
			if solid_mask[idx_n] == 1:
				sum_n += T[idx_n]; n += 1

			if n == 0:
				# 완전히 고립된 셀(주변이 전부 공기)이면 변화 없음
				Tnew[idx] = t_center
				continue

			var avg_n: float = sum_n / float(n)

			# α(=k/c) * dt * n 을 블렌드 팩터로 사용하되 [0,1]로 클램프
			var a: float = alpha[idx]
			var blend: float = clamp(dt * a * float(n), 0.0, 1.0)

			# 평균으로 blend 만큼만 이동 → 항상 기존 [min,max] 안에 머무름
			Tnew[idx] = lerp(t_center, avg_n, blend)

	return Tnew

func _apply_uranium_heating(dt: float, Tnew: PackedFloat32Array) -> void:
	if _uranium_cells.size() == 0 or uranium_power_per_sec == 0.0:
		return

	var delta_t: float = uranium_power_per_sec * dt
	for i in _uranium_cells.size():
		var uidx: int = _uranium_cells[i]
		if uidx >= 0 and uidx < Tnew.size() and solid_mask[uidx] == 1:
			Tnew[uidx] += delta_t

func _compute_delta(Tnew: PackedFloat32Array) -> void:
	for i in T.size():
		if solid_mask[i] == 1:
			_last_delta[i] = Tnew[i] - T[i]
		else:
			_last_delta[i] = 0.0

func get_temperature_buffer() -> PackedFloat32Array:
	return T

func get_visual_range() -> Vector2:
	return Vector2(t_min_vis, t_max_vis)

func get_solid_mask() -> PackedByteArray:
	return solid_mask

func _cell_to_index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x

# 타일 '파괴' 시 호출: from_tile이 우라늄이면 열원 제거
func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if size == Vector2i.ZERO:
		return
	var idx: int = _cell_to_index(cell)
	if idx < 0 or idx >= T.size():
		return

	# AIR로 정리
	solid_mask[idx] = 0
	alpha[idx] = 0.0
	T[idx] = 0.0

	# 우라늄 열원 제거
	if from_tile == TILE_URANIUM:
		var p: int = _uranium_cells.find(idx)
		if p != -1:
			_uranium_cells.remove_at(p)

	emit_signal("temperature_updated")

# 타일 '교체' 시 호출: from_tile이 우라늄이면 열원 제거
func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if size == Vector2i.ZERO:
		return
	var idx: int = _cell_to_index(cell)
	if idx < 0 or idx >= T.size():
		return

	# from이 우라늄이면 열원 제거
	if from_tile == TILE_URANIUM:
		var p: int = _uranium_cells.find(idx)
		if p != -1:
			_uranium_cells.remove_at(p)

	match to_tile:
		TILE_AIR:
			solid_mask[idx] = 0
			alpha[idx] = 0.0
			T[idx] = 0.0
		TILE_GROUND:
			solid_mask[idx] = 1
			alpha[idx] = k_ground / max(0.0001, c_ground)
			if T[idx] == 0.0:
				T[idx] = t_ground_init
		TILE_ICE:
			solid_mask[idx] = 1
			alpha[idx] = k_ice / max(0.0001, c_ice)
			if T[idx] == 0.0:
				T[idx] = t_ice_init
		TILE_URANIUM:
			solid_mask[idx] = 1
			alpha[idx] = k_uranium / max(0.0001, c_uranium)
			if T[idx] == 0.0:
				T[idx] = t_uranium_init
			if _uranium_cells.find(idx) == -1:
				_uranium_cells.append(idx)

	emit_signal("temperature_updated")

func get_last_delta() -> PackedFloat32Array:
	return _last_delta
