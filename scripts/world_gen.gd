extends Node
class_name WorldGen

signal generated(tile_types: PackedInt32Array, size: Vector2i, liquid_amount: PackedFloat32Array, springs: PackedVector2Array)

@export var size: Vector2i = Vector2i(256, 128)

# 노이즈/분포 파라미터
@export var seed_height: int = 12345
@export var seed_ice: int = 98765
@export var height_freq: float = 0.02
@export var ice_freq: float = 0.08
@export var ice_threshold: float = 0.45
@export var ice_max_depth: int = 6
@export var ice_edge_bonus: float = 0.15

# ── 우라늄 분포 파라미터 ──
@export var uranium_seed: int = 24680
@export var uranium_freq: float = 0.06          # 클러스터 크기(작을수록 더 큰 덩어리)
@export var uranium_threshold: float = 0.72     # 노이즈 임계(낮출수록 많아짐)
@export var uranium_density: float = 0.006      # 추가 난수 확률(전역 희귀도; 0.6%)
@export var uranium_depth_min: int = 6          # 지표선 아래 최소 깊이
@export var uranium_depth_max: int = 24         # 지표선 아래 최대 깊이

const TILE_AIR: int = 0
const TILE_ICE: int = 1
const TILE_GROUND: int = 2
const TILE_URANIUM: int = 3

# ── 초기 액체 배치 파라미터 ──
@export var water_level_ratio: float = 0.4
@export var min_lake_size: int = 4
@export var depth_scale: float = 4.0
@export var springs_per_k: float = 1.0

func generate() -> void:
	var hmap := generate_heightmap()
	var tiles := classify_tiles(hmap)
	place_uranium(tiles, hmap)
	var liquid := generate_liquids(hmap)
	emit_signal("generated", tiles, size, liquid.amount, liquid.springs)

# Build a 1D heightmap representing surface level per column
func generate_heightmap() -> PackedInt32Array:
	var hmap: PackedInt32Array = PackedInt32Array()
	hmap.resize(size.x)

	var n_height := FastNoiseLite.new()
	n_height.seed = seed_height
	n_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_height.frequency = height_freq

	for x in size.x:
		var h:int = int(n_height.get_noise_1d(float(x)) * 12.0) + int(size.y * 0.55)
		h = clamp(h, 16, size.y - 8)
		hmap[x] = h

	return hmap

func classify_tiles(hmap: PackedInt32Array) -> PackedInt32Array:
	# Assign AIR/ICE/GROUND based on height and ice noise
	var n_ice := FastNoiseLite.new()
	n_ice.seed = seed_ice
	n_ice.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ice.frequency = ice_freq

	var tiles: PackedInt32Array = PackedInt32Array()
	tiles.resize(size.x * size.y)

	for y in size.y:
		for x in size.x:
			var idx:int = y * size.x + x
			if y < hmap[x]:
				tiles[idx] = TILE_AIR
				continue

			var depth:int = y - hmap[x]
			var surface_bonus: float = 0.0
			if depth <= ice_max_depth:
				var t: float = 1.0 - (float(depth) / float(ice_max_depth))
				surface_bonus = t * ice_edge_bonus

			var m: float = (n_ice.get_noise_2d(float(x), float(y)) + 1.0) * 0.5 # [0,1]
			var score: float = m + surface_bonus
			tiles[idx] = TILE_ICE if score >= ice_threshold else TILE_GROUND

	return tiles

func place_uranium(tiles: PackedInt32Array, hmap: PackedInt32Array) -> void:
	# Scatter uranium veins using noise with a small random chance
	var n_u := FastNoiseLite.new()
	n_u.seed = uranium_seed
	n_u.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_u.frequency = uranium_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(uranium_seed) # 재현성

	for y in size.y:
		for x in size.x:
			var idx2: int = y * size.x + x
			if tiles[idx2] != TILE_GROUND:
				continue # skip non-ground tiles

			var depth2: int = y - hmap[x]
			if depth2 < uranium_depth_min or depth2 > uranium_depth_max:
				continue

			# 노이즈 기반 클러스터 + 낮은 전역 확률로 약간 가산
			var nu: float = (n_u.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # [0,1]
			var hit_noise: bool = (nu >= uranium_threshold)         # 클러스터 내부
			var hit_rand: bool = (rng.randf() < uranium_density)    # 희귀 난수

			if hit_noise or hit_rand:
				tiles[idx2] = TILE_URANIUM

func generate_liquids(hmap: PackedInt32Array) -> Dictionary:
	var amount := PackedFloat32Array()
	amount.resize(size.x * size.y)
	var springs := PackedVector2Array()
	var min_h: int = hmap[0]
	var max_h: int = hmap[0]
	for x in size.x:
		min_h = min(min_h, hmap[x])
		max_h = max(max_h, hmap[x])
	var water_level: int = int(lerp(float(min_h), float(max_h), water_level_ratio))
	var seg_start: int = -1
	for x in size.x:
		if hmap[x] >= water_level:
			if seg_start == -1:
					seg_start = x
		else:
			if seg_start != -1:
				_fill_lake(amount, hmap, seg_start, x - 1, water_level)
				seg_start = -1
	if seg_start != -1:
		_fill_lake(amount, hmap, seg_start, size.x - 1, water_level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_height
	var prob: float = springs_per_k / 1000.0
	for x in range(1, size.x - 1):
		var h0: int = hmap[x]
		if h0 >= water_level:
			continue
		var slope_l: float = abs(h0 - hmap[x - 1])
		var slope_r: float = abs(h0 - hmap[x + 1])
		if max(slope_l, slope_r) < 2:
			continue
		if rng.randf() < prob:
			springs.append(Vector2i(x, h0))
	return {"amount": amount, "springs": springs}

func _fill_lake(amount: PackedFloat32Array, hmap: PackedInt32Array, sx: int, ex: int, water_level: int) -> void:
	var width: int = ex - sx + 1
	if width < min_lake_size:
		return
	for x in range(sx, ex + 1):
		var ground: int = hmap[x]
		for y in range(water_level, ground):
			var depth_from_surface: int = y - water_level + 1
			var fill: float = clamp(float(depth_from_surface) / depth_scale, 0.0, 1.0)
			var idx: int = y * size.x + x
			amount[idx] = fill
