extends Node
class_name WorldGen

signal generated(tile_types: PackedInt32Array, size: Vector2i)

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

func generate() -> void:
	var hmap := generate_heightmap()
	var tiles := classify_tiles(hmap)
	place_uranium(tiles, hmap)
	emit_signal("generated", tiles, size)

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
	var n_u := FastNoiseLite.new()
	n_u.seed = uranium_seed
	n_u.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_u.frequency = uranium_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(uranium_seed)  # 재현성

	for y in size.y:
		for x in size.x:
			var idx2: int = y * size.x + x
			if tiles[idx2] != TILE_GROUND:
				continue  # 얼음/공기는 제외(원하면 얼음에도 드물게 허용 가능)

			var depth2: int = y - hmap[x]
			if depth2 < uranium_depth_min or depth2 > uranium_depth_max:
				continue

			# 노이즈 기반 클러스터 + 낮은 전역 확률로 약간 가산
			var nu: float = (n_u.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # [0,1]
			var hit_noise: bool = (nu >= uranium_threshold)         # 클러스터 내부
			var hit_rand: bool = (rng.randf() < uranium_density)    # 희귀 난수

			if hit_noise or hit_rand:
				tiles[idx2] = TILE_URANIUM
