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

# ── Rule Cache ───────────────────────────────────────────────────
var _rule_cache: SubstanceRuleCache

# ── Substance IDs ────────────────────────────────────────────────
var _sid_water : int
var _sid_ice   : int
var _sid_ground: int
var _sid_uran  : int
var _sid_copper: int
const SID_VACUUM := 0

# °cC(= °C*100) → cK: cK = cC + 27315
const CK_0C := 27315
static func _cc_to_ck(cC: int) -> int:
	return cC + CK_0C

# ══════════════════════════════════════════════════════════════════
# Setup & Generation Entry Point
# ══════════════════════════════════════════════════════════════════

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rule_cache = cache

func generate() -> void:
	if profile == null: push_error("[WorldGen.generate] profile not found")
	if _rule_cache == null:
		push_error("[WorldGen] rule_cache not bound")
		return

	size = profile.size

	# SID 캐시
	_sid_water  = _rule_cache.sid_of("liquid/water")
	_sid_ice    = _rule_cache.sid_of("solid/ice")
	_sid_ground = _rule_cache.sid_of("solid/soil")
	_sid_uran   = _rule_cache.sid_of("solid/uranium")
	_sid_copper = _rule_cache.sid_of("solid/copper")

	# ── 1) 소스 레이어 생성 ───────────────────────────────────────────────
	var hmap := generate_heightmap()
	var base := build_base_solid_layer(hmap)        # PackedInt32Array (sid)
	var mask_cave := build_mask_cave(hmap)          # PackedByteArray  (0/1)
	var feat_u := build_feat_uranium(hmap, base)    # PackedByteArray  (0/1)
	var feat_c := build_feat_copper(hmap, base)     # PackedByteArray  (0/1)
	var liquid := build_liquid_layer(hmap)          # {amount, springs}

	# ── 2) 레이어 합성(타일용 고체/진공만 확정) ───────────────────────────
	var tiles_composed: PackedInt32Array = base.duplicate()  # 고체/진공 결과(액체는 별도)
	var n := tiles_composed.size()
	for i in n:
		# 2-1) 동굴 마스크: 비우기(진공)
		if mask_cave[i] == 1:
			tiles_composed[i] = SID_VACUUM
			continue

		# 2-2) 피처 덮어쓰기(우선순위: 우라늄 > 구리), 진공은 제외
		if tiles_composed[i] != SID_VACUUM:
			if feat_u[i] == 1:
				tiles_composed[i] = _sid_uran
			elif feat_c[i] == 1:
				tiles_composed[i] = _sid_copper
	# 이제 tiles_composed = (Base → Mask → Feature) 합성 결과

	# ── 3) 최종 배열 확정(액체는 최종 단계에서 우선 적용) ────────────────
	var phases := PackedByteArray();   phases.resize(n)
	var mass := PackedInt64Array();    mass.resize(n)
	var substances := PackedInt32Array(); substances.resize(n)
	var temperatures := PackedInt32Array(); temperatures.resize(n)

	for i in n:
		var liq: int = liquid.amount[i]

		# 3-1) 액체가 있으면 최종적으로 물/액체로 확정
		if liq > 0:
			phases[i] = PhaseStore.Phase.LIQUID
			mass[i] = liq
			substances[i] = _sid_water
			temperatures[i] = _cc_to_ck(profile.water_temp_init_cC)
			continue

		# 3-2) 액체가 없으면 합성된 tiles를 기준으로 상/질량/온도 확정
		match tiles_composed[i]:
			_sid_ground:
				phases[i] = PhaseStore.Phase.SOLID
				mass[i] = profile.ground_mass_mg_per_cell
				substances[i] = _sid_ground
				temperatures[i] = _cc_to_ck(profile.ground_temp_init_cC)
			_sid_ice:
				phases[i] = PhaseStore.Phase.SOLID
				mass[i] = profile.ice_mass_mg_per_cell
				substances[i] = _sid_ice
				temperatures[i] = _cc_to_ck(profile.ice_temp_init_cC)
			_sid_uran:
				phases[i] = PhaseStore.Phase.SOLID
				mass[i] = profile.uranium_mass_mg_per_cell
				substances[i] = _sid_uran
				temperatures[i] = _cc_to_ck(profile.uranium_temp_init_cC)
			_sid_copper:
				phases[i] = PhaseStore.Phase.SOLID
				mass[i] = profile.copper_mass_mg_per_cell
				substances[i] = _sid_copper
				temperatures[i] = _cc_to_ck(profile.copper_temp_init_cC)
			_:
				phases[i] = PhaseStore.Phase.VACUUM
				mass[i] = 0
				substances[i] = SID_VACUUM
				temperatures[i] = 0

	_assert_world_arrays(substances, phases, mass, temperatures, tiles_composed)

	generated.emit(size, substances, phases, mass, temperatures, tiles_composed, liquid.springs)

# ─────────────────────────────────────────────────────────────────────────────
## Build a 1D heightmap representing surface level per column
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

# ─────────────────────────────────────────────────────────────────────────────
## Base Layer: ground/ice/vac 결정 (기존 classify_tiles)
func build_base_solid_layer(hmap: PackedInt32Array) -> PackedInt32Array:
	var n_ice := FastNoiseLite.new()
	n_ice.seed = profile.ice_seed
	n_ice.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ice.frequency = profile.ice_freq

	var tiles_base: PackedInt32Array = PackedInt32Array()
	tiles_base.resize(size.x * size.y)

	for y in size.y:
		for x in size.x:
			var idx:int = y * size.x + x
			if y < hmap[x]:
				tiles_base[idx] = SID_VACUUM
				continue

			var depth:int = y - hmap[x]
			var surface_bonus: float = 0.0
			if depth <= profile.ice_max_depth:
				var t: float = 1.0 - (float(depth) / float(profile.ice_max_depth))
				surface_bonus = t * profile.ice_edge_bonus

			var m: float = (n_ice.get_noise_2d(float(x), float(y)) + 1.0) * 0.5 # [0,1]
			var score: float = m + surface_bonus
			tiles_base[idx] = _sid_ice if score >= profile.ice_threshold else _sid_ground

	return tiles_base

# ─────────────────────────────────────────────────────────────────────────────
## Mask: Cave (기존 compute_cave_mask)
func build_mask_cave(hmap: PackedInt32Array) -> PackedByteArray:
	const MIN_DEPTH := 6
	const INIT_FILL := 0.42
	const SURVIVE_LIMIT := 4
	const BIRTH_LIMIT := 5
	const STEPS := 4

	var w := size.x
	var h := size.y
	var n := w * h

	var mask_cave := PackedByteArray(); mask_cave.resize(n)
	for i in n: mask_cave[i] = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.seed_height) ^ String("cave").hash()

	for x in w:
		var start_y: float = clamp(hmap[x] + MIN_DEPTH, 0, h)
		for y in range(start_y, h):
			var idx := y * w + x
			mask_cave[idx] = 1 if rng.randf() < INIT_FILL else 0

	var neigh := [
		Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
		Vector2i(-1, 0),                 Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
	]
	for _step in STEPS:
		var mask_next := PackedByteArray(); mask_next.resize(n) ## temporary buffer for smoothing step
		for i in n: mask_next[i] = 0

		for y in h:
			for x in w:
				if y < hmap[x] + MIN_DEPTH:
					continue
				var idx := y * w + x
				var cur := int(mask_cave[idx])
				var cnt := 0
				for d in neigh:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or nx >= w or ny < 0 or ny >= h:
						continue
					if ny >= hmap[nx] + MIN_DEPTH and mask_cave[ny * w + nx] == 1:
						cnt += 1
				if cur == 1 and cnt >= SURVIVE_LIMIT:
					mask_next[idx] = 1
				elif cur == 0 and cnt >= BIRTH_LIMIT:
					mask_next[idx] = 1
				else:
					mask_next[idx] = 0
		mask_cave = mask_next

	# 표면 연결 제거(입구 봉인)
	var stack := []
	var visited := PackedByteArray(); visited.resize(n)
	for i in n: visited[i] = 0

	for x in w:
		var y0 := hmap[x] + MIN_DEPTH
		if y0 < 0 or y0 >= h: continue
		var i0 := y0 * w + x
		if mask_cave[i0] != 1: continue
		stack.clear()
		stack.append(i0)
		while stack.size() > 0:
			var ii: int = stack.pop_back()
			if ii < 0 or ii >= n: continue
			if visited[ii] == 1: continue
			visited[ii] = 1
			if mask_cave[ii] != 1: continue
			mask_cave[ii] = 0
			var cx := ii % w
			@warning_ignore("integer_division")
			var cy := ii / w
			if cx > 0:         stack.append(ii - 1)
			if cx < w - 1:     stack.append(ii + 1)
			if cy > 0:         stack.append(ii - w)
			if cy < h - 1:     stack.append(ii + w)

	# 외곽 0
	for y in h:
		mask_cave[y * w + 0] = 0
		mask_cave[y * w + (w - 1)] = 0
	for x in w:
		mask_cave[(h - 1) * w + x] = 0

	return mask_cave

# ─────────────────────────────────────────────────────────────────────────────
## Feature: Uranium (0/1 마스크로 출력, ground에만 스폰)
func build_feat_uranium(hmap: PackedInt32Array, base: PackedInt32Array) -> PackedByteArray:
	var w := size.x
	var h := size.y
	var n := w * h

	var mask_feat_uranium := PackedByteArray(); mask_feat_uranium.resize(n)
	for i in n: mask_feat_uranium[i] = 0

	var n_u := FastNoiseLite.new()
	n_u.seed = profile.uranium_seed
	n_u.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_u.frequency = profile.uranium_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.uranium_seed)

	for y in h:
		for x in w:
			var idx := y * w + x
			if base[idx] != _sid_ground:
				continue

			var depth2: int = y - hmap[x]
			if depth2 < profile.uranium_depth_min or depth2 > profile.uranium_depth_max:
				continue

			var nu: float = (n_u.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hit_noise: bool = (nu >= profile.uranium_threshold)
			var hit_rand: bool = (rng.randf() < profile.uranium_density)
			if hit_noise or hit_rand:
				mask_feat_uranium[idx] = 1
	return mask_feat_uranium

# ─────────────────────────────────────────────────────────────────────────────
## Feature: Copper (0/1 마스크로 출력, ground에만 스폰)
func build_feat_copper(hmap: PackedInt32Array, base: PackedInt32Array) -> PackedByteArray:
	var w := size.x
	var h := size.y
	var n := w * h

	var mask_feat_copper := PackedByteArray(); mask_feat_copper.resize(n)
	for i in n: mask_feat_copper[i] = 0

	var n_c := FastNoiseLite.new()
	n_c.seed = profile.copper_seed
	n_c.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_c.frequency = profile.copper_freq

	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.copper_seed)

	for y in h:
		for x in w:
			var idx := y * w + x
			if base[idx] != _sid_ground:
				continue

			var depth: int = y - hmap[x]
			if depth < profile.copper_depth_min or depth > profile.copper_depth_max:
				continue

			var nc: float = (n_c.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hit_noise: bool = (nc >= profile.copper_threshold)
			var hit_rand: bool = (rng.randf() < profile.copper_density)
			if hit_noise or hit_rand:
				mask_feat_copper[idx] = 1
	return mask_feat_copper

# ─────────────────────────────────────────────────────────────────────────────
# Liquid Layer (기존 generate_liquids)
func build_liquid_layer(hmap: PackedInt32Array) -> Dictionary:
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

	# 로그
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
