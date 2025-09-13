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

@export var profile: WorldGenProfile

var size: Vector2i

var _rule_cache: SubstanceRuleCache

var _sid_water : int
var _sid_ice   : int
var _sid_ground: int
var _sid_uran  : int
var _sid_copper: int
var _sid_vac   : int = 0   # VACUUM은 보통 0 고정

# °cC(= °C*100) → cK: cK = cC + 27315
const CK_0C := 27315
static func _cc_to_ck(cC: int) -> int:
	return cC + CK_0C

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rule_cache = cache

func generate() -> void:
	if profile == null: push_error("[WorldGen.generate] profile not found")
	size = profile.size
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

	var cave_mask := compute_cave_mask(hmap)
	apply_caves_to_tiles(tiles, cave_mask)

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
			temperatures[i] = _cc_to_ck(profile.water_temp_init_cC)
			continue

		# 2) 액체가 없으면 고체/진공 판정
		if tile == _sid_ground:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = profile.ground_mass_mg_per_cell
			substances[i] = _sid_ground
			temperatures[i] = _cc_to_ck(profile.ground_temp_init_cC)
		elif tile == _sid_ice:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = profile.ice_mass_mg_per_cell
			substances[i] = _sid_ice
			temperatures[i] = _cc_to_ck(profile.ice_temp_init_cC)
		elif tile == _sid_uran:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = profile.uranium_mass_mg_per_cell
			substances[i] = _sid_uran
			temperatures[i] = _cc_to_ck(profile.uranium_temp_init_cC)
		elif tile == _sid_copper:
			phases[i] = PhaseStore.Phase.SOLID
			mass[i] = profile.copper_mass_mg_per_cell
			substances[i] = _sid_copper
			temperatures[i] = _cc_to_ck(profile.copper_temp_init_cC)
		else:
			phases[i] = PhaseStore.Phase.VACUUM
			mass[i] = 0
			substances[i] = _sid_vac
			temperatures[i] = 0

	_assert_world_arrays(substances, phases, mass, temperatures, tiles)

	emit_signal("generated", size, substances, phases, mass, temperatures, tiles, liquid.springs)

# Build a 1D heightmap representing surface level per column
func generate_heightmap() -> PackedInt32Array:
	var hmap: PackedInt32Array = PackedInt32Array()
	hmap.resize(size.x)

	var n_height := FastNoiseLite.new()
	n_height.seed = profile.seed_height
	n_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_height.frequency = profile.height_freq

	for x in size.x:
		var h:int = int(n_height.get_noise_1d(float(x)) * 12.0) + int(size.y * 0.55)
		h = clamp(h, 16, size.y - 8)
		hmap[x] = h

	return hmap

func classify_tiles(hmap: PackedInt32Array) -> PackedInt32Array:
	# Assign VACCUM/ICE/GROUND based on height and ice noise
	var n_ice := FastNoiseLite.new()
	n_ice.seed = profile.ice_seed
	n_ice.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ice.frequency = profile.ice_freq

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
			if depth <= profile.ice_max_depth:
				var t: float = 1.0 - (float(depth) / float(profile.ice_max_depth))
				surface_bonus = t * profile.ice_edge_bonus

			var m: float = (n_ice.get_noise_2d(float(x), float(y)) + 1.0) * 0.5 # [0,1]
			var score: float = m + surface_bonus
			tiles[idx] = _sid_ice if score >= profile.ice_threshold else _sid_ground

	return tiles

func place_uranium(tiles: PackedInt32Array, hmap: PackedInt32Array) -> void:
	# Scatter uranium veins using noise with a small random chance
	var n_u := FastNoiseLite.new()
	n_u.seed = profile.uranium_seed
	n_u.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_u.frequency = profile.uranium_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.uranium_seed) # 재현성

	for y in size.y:
		for x in size.x:
			var idx2: int = y * size.x + x
			if tiles[idx2] != _sid_ground:
				continue # skip non-ground tiles

			var depth2: int = y - hmap[x]
			if depth2 < profile.uranium_depth_min or depth2 > profile.uranium_depth_max:
				continue

			# 노이즈 기반 클러스터 + 낮은 전역 확률로 약간 가산
			var nu: float = (n_u.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # [0,1]
			var hit_noise: bool = (nu >= profile.uranium_threshold)         # 클러스터 내부
			var hit_rand: bool = (rng.randf() < profile.uranium_density)    # 희귀 난수

			if hit_noise or hit_rand:
				tiles[idx2] = _sid_uran

func place_copper(tiles: PackedInt32Array, hmap: PackedInt32Array) -> void:
	var n_c := FastNoiseLite.new()
	n_c.seed = profile.copper_seed
	n_c.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_c.frequency = profile.copper_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.copper_seed)

	for y in size.y:
		for x in size.x:
			var idx: int = y * size.x + x
			if tiles[idx] != _sid_ground:
				continue

			var depth: int = y - hmap[x]
			if depth < profile.copper_depth_min or depth > profile.copper_depth_max:
				continue

			var nc: float = (n_c.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hit_noise: bool = (nc >= profile.copper_threshold)
			var hit_rand: bool = (rng.randf() < profile.copper_density)

			if hit_noise or hit_rand:
				tiles[idx] = _sid_copper

## ─────────────────────────────────────────────────────────────────────────────
## 동굴 생성: 마스크 계산 → 타일 절삭
##  - compute_cave_mask: 지하 빈공간(동굴) 후보를 0/1로 만들기
##  - apply_caves_to_tiles: 마스크=1인 셀을 전부 VACUUM(SID=0)로 치환
##  - 내부 상수만 사용(MIN_DEPTH 등), 추가 옵션/보존 처리 없음
## ─────────────────────────────────────────────────────────────────────────────

## 지하 동굴 마스크 계산
## 반환: PackedByteArray (0/1), 길이=size.x*size.y
func compute_cave_mask(hmap: PackedInt32Array) -> PackedByteArray:
	# 내부 상수(간단 튜닝 포인트)
	const MIN_DEPTH := 6            # 지표선 아래 이 깊이부터만 동굴 후보
	const INIT_FILL := 0.42         # 초기 랜덤 채움 비율
	const SURVIVE_LIMIT := 4        # CA: 살아남는 임계(이웃 1의 수)
	const BIRTH_LIMIT := 5          # CA: 탄생 임계(이웃 1의 수)
	const STEPS := 4                # CA 스무딩 반복 횟수

	var w := size.x
	var h := size.y
	var n := w * h

	# 0) 마스크 초기화
	var mask := PackedByteArray(); mask.resize(n)
	for i in n: mask[i] = 0

	# RNG (재현성): height 시드에서 파생
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.seed_height) ^ String("cave").hash()

	# 1) 후보 영역 초기 랜덤 채움
	for x in w:
		var start_y: float = clamp(hmap[x] + MIN_DEPTH, 0, h)
		for y in range(start_y, h):
			var idx := y * w + x
			mask[idx] = 1 if rng.randf() < INIT_FILL else 0

	# 2) 셀룰러 오토마타 스무딩(8이웃)
	var neigh := [
		Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
		Vector2i(-1, 0),                 Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
	]
	for _step in STEPS:
		var next := PackedByteArray(); next.resize(n)
		for i in n: next[i] = 0

		for y in h:
			for x in w:
				# 후보 영역 밖(얕은 곳)은 항상 0 유지
				if y < hmap[x] + MIN_DEPTH:
					continue

				var idx := y * w + x
				var cur := int(mask[idx])
				var cnt := 0
				for d in neigh:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or nx >= w or ny < 0 or ny >= h:
						continue
					# 이웃도 후보 영역 안에서만 카운트
					if ny >= hmap[nx] + MIN_DEPTH and mask[ny * w + nx] == 1:
						cnt += 1
				if cur == 1 and cnt >= SURVIVE_LIMIT:
					next[idx] = 1
				elif cur == 0 and cnt >= BIRTH_LIMIT:
					next[idx] = 1
				else:
					next[idx] = 0
		mask = next

	# 3) 표면 연결 제거(입구 봉인): 지표 바로 아래 띠에서 4방 flood fill로 연결된 1 → 0
	var stack := []        # int(idx) 스택
	var visited := PackedByteArray(); visited.resize(n)
	for i in n: visited[i] = 0

	# 시작점: 각 x의 y0 = hmap[x] + MIN_DEPTH (후보 띠)
	for x in w:
		var y0 := hmap[x] + MIN_DEPTH
		if y0 < 0 or y0 >= h:
			continue
		var i0 := y0 * w + x
		if mask[i0] != 1:
			continue
		# flood fill
		stack.clear()
		stack.append(i0)
		while stack.size() > 0:
			var ii: int = stack.pop_back()
			if ii < 0 or ii >= n: continue
			if visited[ii] == 1: continue
			visited[ii] = 1
			if mask[ii] != 1: continue
			# 표면 연결된 빈공간은 제거
			mask[ii] = 0
			var cx := ii % w
			var cy := ii / w
			# 4방
			if cx > 0:         stack.append(ii - 1)
			if cx < w - 1:     stack.append(ii + 1)
			if cy > 0:         stack.append(ii - w)
			if cy < h - 1:     stack.append(ii + w)

	# 4) 외곽 안전장치: 맵 가장자리(좌/우/바닥)는 0으로 강제
	for y in h:
		var iL := y * w + 0
		var iR := y * w + (w - 1)
		mask[iL] = 0
		mask[iR] = 0
	for x in w:
		var iB := (h - 1) * w + x
		mask[iB] = 0

	return mask

## 마스크가 1인 셀은 전부 VACUUM(SID=0)으로 절삭
func apply_caves_to_tiles(tiles: PackedInt32Array, cave_mask: PackedByteArray) -> void:
	var n := tiles.size()
	if cave_mask.size() != n:
		push_error("[WorldGen] cave_mask size mismatch")
		return
	for i in n:
		if cave_mask[i] == 1:
			tiles[i] = _sid_vac

func generate_liquids(hmap: PackedInt32Array) -> Dictionary:
	var amount := PackedInt64Array()
	amount.resize(size.x * size.y)
	var springs := PackedVector2Array()
	var min_h: int = hmap[0]
	var max_h: int = hmap[0]
	for x in size.x:
		min_h = min(min_h, hmap[x])
		max_h = max(max_h, hmap[x])
	var water_level: int = int(lerp(float(min_h), float(max_h), profile.water_level_ratio))
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
	rng.seed = profile.seed_height
	var prob: float = profile.springs_per_k / 1000.0
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
	if width < profile.min_lake_size:
		return
	for x in range(sx, ex + 1):
		var ground: int = hmap[x]
		for y in range(water_level, ground):
			var depth_from_surface: int = y - water_level + 1
			var fill: float = clamp(float(depth_from_surface) / profile.depth_scale, 0.0, 1.0)
			var idx: int = y * size.x + x
			amount[idx] = int(round(fill * profile.water_capacity_mg_per_cell))

func _assert_world_arrays(
	substances: PackedInt32Array, phases: PackedByteArray,
	mass: PackedInt64Array, temperatures: PackedInt32Array, tiles: PackedInt32Array
) -> void:
	var n := size.x * size.y
	if [substances.size(), phases.size(), mass.size(), temperatures.size(), tiles.size()].any(func(s): return s != n):
		push_error("[WorldGen] array size mismatch")
