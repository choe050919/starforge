extends Node
class_name WorldGen

signal generated(
	size: Vector2i,
	substances: PackedInt32Array,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	temperatures: PackedInt32Array,
	tile_types: PackedInt32Array,
	springs: PackedVector2Array
)

@export var size: Vector2i = Vector2i(256, 128)

# 초기 온도(°cC)
@export var t_ice_init_cc: int = -500
@export var t_ground_init_cc: int = 1200
@export var t_uranium_init_cc: int = 1200
@export var t_copper_init_cc: int = 800
@export var t_water_init_cc: int = 1500

# 노이즈/분포 파라미터
@export var seed_height: int = 12345
@export var seed_ice: int = 98765
@export var height_freq: float = 0.02
@export var ice_freq: float = 0.08
@export var ice_threshold: float = 0.35
@export var ice_max_depth: int = 6
@export var ice_edge_bonus: float = 0.15

# 타일 질량 파라미터
@export var mass_ice_mg_per_cell: int = 900_000         # 0.9 kg
@export var mass_ground_mg_per_cell: int = 1_200_000    # 1.2 kg
@export var mass_uranium_mg_per_cell: int = 1_900_000   # 1.9 kg
@export var mass_copper_mg_per_cell: int = 1_400_000    # 1.4 kg
@export var water_capacity_mg_per_cell: int = 1_000_000 # 1 kg

# 우라늄 분포 파라미터
@export var uranium_seed: int = 24680
@export var uranium_freq: float = 0.06          # 클러스터 크기(작을수록 더 큰 덩어리)
@export var uranium_threshold: float = 0.72     # 노이즈 임계(낮출수록 많아짐)
@export var uranium_density: float = 0.006      # 추가 난수 확률(전역 희귀도; 0.6%)
@export var uranium_depth_min: int = 8          # 지표선 아래 최소 깊이
@export var uranium_depth_max: int = 24         # 지표선 아래 최대 깊이

# 구리 분포 파라미터
@export var copper_seed: int = 13579
@export var copper_freq: float = 0.05
@export var copper_threshold: float = 0.65
@export var copper_density: float = 0.01
@export var copper_depth_min: int = 3
@export var copper_depth_max: int = 15

var _rule_cache: SubstanceRuleCache

var _sid_water : int
var _sid_ice   : int
var _sid_ground: int
var _sid_uran  : int
var _sid_copper: int
var _sid_vac   : int = 0   # VACUUM은 보통 0 고정

# 초기 액체 배치 파라미터
@export var water_level_ratio: float = 0.4
@export var min_lake_size: int = 4
@export var depth_scale: float = 4.0
@export var springs_per_k: float = 1.0

# °cC → cK(centiKelvin) 변환: cK = round(°C*100 + 27315)
const CK_0C := 27315
static func _cc_to_ck(c: int) -> int:
	return int(c + CK_0C)

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rule_cache = cache

func generate() -> void:
	if _rule_cache == null:
		push_error("[WorldGen] rule_cache not bound")
		return
	_sid_water  = _rule_cache.sid_of("liquid/water")
	_sid_ice    = _rule_cache.sid_of("solid/ice")
	_sid_ground = _rule_cache.sid_of("solid/soil")
	_sid_uran   = _rule_cache.sid_of("solid/uranium")
	_sid_copper = _rule_cache.sid_of("solid/copper")
	var hmap := generate_heightmap()
	var tiles := classify_tiles(hmap)
	place_uranium(tiles, hmap)
	place_copper(tiles, hmap)
	var liquid := generate_liquids(hmap)

	var total := size.x * size.y
	var phases := PackedByteArray(); phases.resize(total)
	var mass := PackedInt64Array(); mass.resize(total)
	var substances := PackedInt32Array(); substances.resize(total)
	var temperatures := PackedInt32Array(); temperatures.resize(total)

	for i in total:
		var tile := tiles[i]
		var liq = liquid.amount[i]  # 복사한 mass[i] 대신 원본 참조로 판정이 명확함

		# 1) 물이 있으면 LIQUID + WATER로 고정
		if liq > 0:
			phases[i] = PhaseStore.Phase.LIQUID
			mass[i] = liq
			substances[i] = _sid_water
			temperatures[i] = _cc_to_ck(t_water_init_cc)
			continue

		# 2) 액체가 없으면 고체/진공 판정
		if tile == _sid_ground:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = mass_ground_mg_per_cell
			substances[i] = _sid_ground
			temperatures[i] = _cc_to_ck(t_ground_init_cc)
		elif tile == _sid_ice:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = mass_ice_mg_per_cell
			substances[i] = _sid_ice
			temperatures[i] = _cc_to_ck(t_ice_init_cc)
		elif tile == _sid_uran:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = mass_uranium_mg_per_cell
			substances[i] = _sid_uran
			temperatures[i] = _cc_to_ck(t_uranium_init_cc)
		elif tile == _sid_copper:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = mass_copper_mg_per_cell
			substances[i] = _sid_copper
			temperatures[i] = _cc_to_ck(t_copper_init_cc)
		else:
			phases[i] = PhaseStore.Phase.VACUUM
			mass[i] = 0
			substances[i] = _sid_vac
			temperatures[i] = 0

	emit_signal("generated", size, substances, phases, mass, temperatures, tiles, liquid.springs)

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
	# Assign VACCUM/ICE/GROUND based on height and ice noise
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
				tiles[idx] = _sid_vac
				continue

			var depth:int = y - hmap[x]
			var surface_bonus: float = 0.0
			if depth <= ice_max_depth:
				var t: float = 1.0 - (float(depth) / float(ice_max_depth))
				surface_bonus = t * ice_edge_bonus

			var m: float = (n_ice.get_noise_2d(float(x), float(y)) + 1.0) * 0.5 # [0,1]
			var score: float = m + surface_bonus
			tiles[idx] = _sid_ice if score >= ice_threshold else _sid_ground

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
			if tiles[idx2] != _sid_ground:
				continue # skip non-ground tiles

			var depth2: int = y - hmap[x]
			if depth2 < uranium_depth_min or depth2 > uranium_depth_max:
				continue

			# 노이즈 기반 클러스터 + 낮은 전역 확률로 약간 가산
			var nu: float = (n_u.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # [0,1]
			var hit_noise: bool = (nu >= uranium_threshold)         # 클러스터 내부
			var hit_rand: bool = (rng.randf() < uranium_density)    # 희귀 난수

			if hit_noise or hit_rand:
				tiles[idx2] = _sid_uran

func place_copper(tiles: PackedInt32Array, hmap: PackedInt32Array) -> void:
	var n_c := FastNoiseLite.new()
	n_c.seed = copper_seed
	n_c.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_c.frequency = copper_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(copper_seed)

	for y in size.y:
		for x in size.x:
			var idx: int = y * size.x + x
			if tiles[idx] != _sid_ground:
				continue

			var depth: int = y - hmap[x]
			if depth < copper_depth_min or depth > copper_depth_max:
				continue

			var nc: float = (n_c.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hit_noise: bool = (nc >= copper_threshold)
			var hit_rand: bool = (rng.randf() < copper_density)

			if hit_noise or hit_rand:
				tiles[idx] = _sid_copper

func generate_liquids(hmap: PackedInt32Array) -> Dictionary:
	var amount := PackedInt64Array()
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

	var cnt:int = 0
	var minv:int = 0
	var maxv:int = 0
	for i in amount.size():
		var v:int = amount[i]
		if v > 0:
			cnt += 1
			if minv == 0 or v < minv: minv = v
			if v > maxv: maxv = v
	print("[WorldGen] liquids: cells=%d min=%d max=%d springs=%d water_level=%d"
		% [cnt, minv, maxv, springs.size(), water_level])

	return {"amount": amount, "springs": springs}

func _fill_lake(amount: PackedInt64Array, hmap: PackedInt32Array, sx: int, ex: int, water_level: int) -> void:
	var width: int = ex - sx + 1
	if width < min_lake_size:
		return
	for x in range(sx, ex + 1):
		var ground: int = hmap[x]
		for y in range(water_level, ground):
			var depth_from_surface: int = y - water_level + 1
			var fill: float = clamp(float(depth_from_surface) / depth_scale, 0.0, 1.0)
			var idx: int = y * size.x + x
			amount[idx] = int(round(fill * water_capacity_mg_per_cell))
