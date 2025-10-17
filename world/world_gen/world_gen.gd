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

# ── Constants ────────────────────────────────────────────────────
const CK_0C := 27315  # Conversion offset: °C*100 → cK
const CAVE_MIN_DEPTH := 6
const CAVE_INIT_FILL := 0.42
const CAVE_SURVIVE_LIMIT := 4
const CAVE_BIRTH_LIMIT := 5
const CAVE_SMOOTH_STEPS := 4

# ══════════════════════════════════════════════════════════════════
# Setup & Generation Entry Point
# ══════════════════════════════════════════════════════════════════

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rule_cache = cache

func generate() -> void:
	if not _validate_setup():
		return
	
	size = profile.size
	_cache_substance_ids()

	var world_data := _generate_world_data()
	_emit_generated_signal(world_data)

# ── Validation ───────────────────────────────────────────────────

func _validate_setup() -> bool:
	if profile == null:
		push_error("[WorldGen] Profile not found")
		return false
	
	if _rule_cache == null:
		push_error("[WorldGen] Rule cache not bound")
		return false
	
	return true

func _cache_substance_ids() -> void:
	_sid_water = _rule_cache.sid_of("liquid/water")
	_sid_ice = _rule_cache.sid_of("solid/ice")
	_sid_ground = _rule_cache.sid_of("solid/soil")
	_sid_uran = _rule_cache.sid_of("solid/uranium")
	_sid_copper = _rule_cache.sid_of("solid/copper")

# ══════════════════════════════════════════════════════════════════
# World Data Generation
# ══════════════════════════════════════════════════════════════════

func _generate_world_data() -> Dictionary:
	# 1) Generate source layers
	var hmap := _generate_heightmap()
	var base := _build_base_solid_layer(hmap)
	var mask_cave := _build_mask_cave(hmap)
	var feat_uranium := _build_feat_uranium(hmap, base)
	var feat_copper := _build_feat_copper(hmap, base)
	var liquid := _build_liquid_layer(hmap)
	
	# 2) Compose layers (solid/vacuum only, liquid handled separately)
	var tiles_composed := _compose_tile_layers(base, mask_cave, feat_uranium, feat_copper)
	
	# 3) Finalize arrays (apply liquid priority)
	return _finalize_world_arrays(tiles_composed, liquid)

func _compose_tile_layers(
	base: PackedInt32Array,
	mask_cave: PackedByteArray,
	feat_uranium: PackedByteArray,
	feat_copper: PackedByteArray
) -> PackedInt32Array:
	var tiles := base.duplicate()
	var n := tiles.size()
	
	for i in n:
		# Apply cave mask (vacuum)
		if mask_cave[i] == 1:
			tiles[i] = SID_VACUUM
			continue
		
		# Apply feature overlays (priority: uranium > copper), skip vacuum
		if tiles[i] != SID_VACUUM:
			if feat_uranium[i] == 1:
				tiles[i] = _sid_uran
			elif feat_copper[i] == 1:
				tiles[i] = _sid_copper
	
	return tiles

func _finalize_world_arrays(tiles_composed: PackedInt32Array, liquid: Dictionary) -> Dictionary:
	var n := tiles_composed.size()
	
	var phases := PackedByteArray()
	var mass := PackedInt64Array()
	var substances := PackedInt32Array()
	var temperatures := PackedInt32Array()
	
	phases.resize(n)
	mass.resize(n)
	substances.resize(n)
	temperatures.resize(n)
	
	for i in n:
		var liq_amount: int = liquid.amount[i]
		
		# Liquid has final priority
		if liq_amount > 0:
			_set_cell_as_liquid(i, liq_amount, phases, mass, substances, temperatures)
		else:
			_set_cell_from_tile(i, tiles_composed[i], phases, mass, substances, temperatures)
	
	_assert_world_arrays(substances, phases, mass, temperatures, tiles_composed)
	
	return {
		"substances": substances,
		"phases": phases,
		"mass": mass,
		"temperatures": temperatures,
		"tiles": tiles_composed,
		"springs": liquid.springs
	}

func _set_cell_as_liquid(
	idx: int,
	liq_amount: int,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	substances: PackedInt32Array,
	temperatures: PackedInt32Array
) -> void:
	phases[idx] = PhaseStore.Phase.LIQUID
	mass[idx] = liq_amount
	substances[idx] = _sid_water
	temperatures[idx] = _cc_to_ck(profile.water_temp_init_cC)

func _set_cell_from_tile(
	idx: int,
	tile_sid: int,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	substances: PackedInt32Array,
	temperatures: PackedInt32Array
) -> void:
	match tile_sid:
		_sid_ground:
			_set_cell_data(idx, PhaseStore.Phase.SOLID, profile.ground_mass_mg_per_cell,
				_sid_ground, profile.ground_temp_init_cC, phases, mass, substances, temperatures)
		_sid_ice:
			_set_cell_data(idx, PhaseStore.Phase.SOLID, profile.ice_mass_mg_per_cell,
				_sid_ice, profile.ice_temp_init_cC, phases, mass, substances, temperatures)
		_sid_uran:
			_set_cell_data(idx, PhaseStore.Phase.SOLID, profile.uranium_mass_mg_per_cell,
				_sid_uran, profile.uranium_temp_init_cC, phases, mass, substances, temperatures)
		_sid_copper:
			_set_cell_data(idx, PhaseStore.Phase.SOLID, profile.copper_mass_mg_per_cell,
				_sid_copper, profile.copper_temp_init_cC, phases, mass, substances, temperatures)
		_:
			_set_cell_data(idx, PhaseStore.Phase.VACUUM, 0, SID_VACUUM, 0,
				phases, mass, substances, temperatures)

func _set_cell_data(
	idx: int,
	phase: int,
	cell_mass: int,
	sid: int,
	temp_cC: int,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	substances: PackedInt32Array,
	temperatures: PackedInt32Array
) -> void:
	phases[idx] = phase
	mass[idx] = cell_mass
	substances[idx] = sid
	temperatures[idx] = _cc_to_ck(temp_cC)

func _emit_generated_signal(data: Dictionary) -> void:
	generated.emit(
		size,
		data.substances,
		data.phases,
		data.mass,
		data.temperatures,
		data.tiles,
		data.springs
	)

# ══════════════════════════════════════════════════════════════════
# Layer Generators
# ══════════════════════════════════════════════════════════════════

## Build a 1D heightmap representing surface level per column
func _generate_heightmap() -> PackedInt32Array:
	var hmap := PackedInt32Array()
	hmap.resize(size.x)
	
	var noise := _create_noise(profile.seed_height, profile.height_freq)
	
	for x in size.x:
		var h := int(noise.get_noise_1d(float(x)) * 12.0) + int(size.y * 0.55)
		hmap[x] = clamp(h, 16, size.y - 8)
	
	return hmap

## Base Layer: ground/ice/vacuum determination
func _build_base_solid_layer(hmap: PackedInt32Array) -> PackedInt32Array:
	var noise := _create_noise(profile.ice_seed, profile.ice_freq)
	var tiles_base := PackedInt32Array()
	tiles_base.resize(size.x * size.y)
	
	for y in size.y:
		for x in size.x:
			var idx := y * size.x + x
			
			if y < hmap[x]:
				tiles_base[idx] = SID_VACUUM
				continue
			
			var depth := y - hmap[x]
			var ice_score := _calculate_ice_score(noise, x, y, depth)
			tiles_base[idx] = _sid_ice if ice_score >= profile.ice_threshold else _sid_ground
	
	return tiles_base

func _calculate_ice_score(noise: FastNoiseLite, x: int, y: int, depth: int) -> float:
	var surface_bonus := 0.0
	
	if depth <= profile.ice_max_depth:
		var t := 1.0 - (float(depth) / float(profile.ice_max_depth))
		surface_bonus = t * profile.ice_edge_bonus
	
	var noise_value := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # Normalize to [0,1]
	return noise_value + surface_bonus

## Mask: Cave generation with cellular automata
func _build_mask_cave(hmap: PackedInt32Array) -> PackedByteArray:
	var mask := _initialize_cave_mask(hmap)
	mask = _smooth_cave_mask(mask, hmap)
	_seal_surface_connections(mask, hmap)
	_seal_boundaries(mask)
	
	return mask

func _initialize_cave_mask(hmap: PackedInt32Array) -> PackedByteArray:
	var w := size.x
	var h := size.y
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.seed_height) ^ String("cave").hash()
	
	for x in w:
		var start_y := int(clamp(hmap[x] + CAVE_MIN_DEPTH, 0, h))
		for y in range(start_y, h):
			var idx := y * w + x
			mask[idx] = 1 if rng.randf() < CAVE_INIT_FILL else 0
	
	return mask

func _smooth_cave_mask(mask: PackedByteArray, hmap: PackedInt32Array) -> PackedByteArray:
	var current_mask := mask
	
	for _step in CAVE_SMOOTH_STEPS:
		current_mask = _apply_cellular_automata_step(current_mask, hmap)
	
	return current_mask

func _apply_cellular_automata_step(mask: PackedByteArray, hmap: PackedInt32Array) -> PackedByteArray:
	var w := size.x
	var h := size.y
	var next_mask := PackedByteArray()
	next_mask.resize(w * h)
	next_mask.fill(0)
	
	const NEIGHBORS := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                  Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
	]
	
	for y in h:
		for x in w:
			if y < hmap[x] + CAVE_MIN_DEPTH:
				continue
			
			var idx := y * w + x
			var is_cave := mask[idx] == 1
			var cave_neighbors := _count_cave_neighbors(mask, hmap, x, y, NEIGHBORS)
			
			if is_cave and cave_neighbors >= CAVE_SURVIVE_LIMIT:
				next_mask[idx] = 1
			elif not is_cave and cave_neighbors >= CAVE_BIRTH_LIMIT:
				next_mask[idx] = 1
	
	return next_mask

func _count_cave_neighbors(
	mask: PackedByteArray,
	hmap: PackedInt32Array,
	x: int,
	y: int,
	neighbors: Array
) -> int:
	var w := size.x
	var h := size.y
	var count := 0
	
	for delta in neighbors:
		var nx: int = x + delta.x
		var ny: int = y + delta.y
		
		if nx < 0 or nx >= w or ny < 0 or ny >= h:
			continue
		
		if ny >= hmap[nx] + CAVE_MIN_DEPTH and mask[ny * w + nx] == 1:
			count += 1
	
	return count

func _seal_surface_connections(mask: PackedByteArray, hmap: PackedInt32Array) -> void:
	var w := size.x
	var h := size.y
	var n := w * h
	var visited := PackedByteArray()
	visited.resize(n)
	visited.fill(0)
	
	for x in w:
		var surface_y := hmap[x] + CAVE_MIN_DEPTH
		if surface_y < 0 or surface_y >= h:
			continue
		
		var surface_idx := surface_y * w + x
		if mask[surface_idx] != 1:
			continue
		
		_flood_fill_remove_cave(mask, visited, surface_idx, w, h)

func _flood_fill_remove_cave(
	mask: PackedByteArray,
	visited: PackedByteArray,
	start_idx: int,
	w: int,
	h: int
) -> void:
	var stack := [start_idx]
	var n := w * h
	
	while stack.size() > 0:
		var idx: int = stack.pop_back()
		
		if idx < 0 or idx >= n or visited[idx] == 1:
			continue
		
		visited[idx] = 1
		
		if mask[idx] != 1:
			continue
		
		mask[idx] = 0
		
		var cx: int = idx % w
		var cy: int = idx / w
		
		if cx > 0:
			stack.append(idx - 1)
		if cx < w - 1:
			stack.append(idx + 1)
		if cy > 0:
			stack.append(idx - w)
		if cy < h - 1:
			stack.append(idx + w)

func _seal_boundaries(mask: PackedByteArray) -> void:
	var w := size.x
	var h := size.y
	
	# Seal left and right edges
	for y in h:
		mask[y * w] = 0
		mask[y * w + (w - 1)] = 0
	
	# Seal bottom edge
	for x in w:
		mask[(h - 1) * w + x] = 0

## Feature: Uranium ore generation
func _build_feat_uranium(hmap: PackedInt32Array, base: PackedInt32Array) -> PackedByteArray:
	return _build_feature_layer(
		hmap,
		base,
		profile.uranium_seed,
		profile.uranium_freq,
		profile.uranium_depth_min,
		profile.uranium_depth_max,
		profile.uranium_threshold,
		profile.uranium_density
	)

## Feature: Copper ore generation
func _build_feat_copper(hmap: PackedInt32Array, base: PackedInt32Array) -> PackedByteArray:
	return _build_feature_layer(
		hmap,
		base,
		profile.copper_seed,
		profile.copper_freq,
		profile.copper_depth_min,
		profile.copper_depth_max,
		profile.copper_threshold,
		profile.copper_density
	)

func _build_feature_layer(
	hmap: PackedInt32Array,
	base: PackedInt32Array,
	seed: int,
	freq: float,
	depth_min: int,
	depth_max: int,
	threshold: float,
	density: float
) -> PackedByteArray:
	var w := size.x
	var h := size.y
	var n := w * h
	
	var mask := PackedByteArray()
	mask.resize(n)
	mask.fill(0)
	
	var noise := _create_noise(seed, freq)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	
	for y in h:
		for x in w:
			var idx := y * w + x
			
			# Only spawn on ground tiles
			if base[idx] != _sid_ground:
				continue
			
			# Check depth range
			var depth := y - hmap[x]
			if depth < depth_min or depth > depth_max:
				continue
			
			# Check noise and random thresholds
			var noise_value := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hit_noise := noise_value >= threshold
			var hit_random := rng.randf() < density
			
			if hit_noise or hit_random:
				mask[idx] = 1
	
	return mask

## Liquid Layer: water bodies and springs
func _build_liquid_layer(hmap: PackedInt32Array) -> Dictionary:
	var amount := PackedInt64Array()
	amount.resize(size.x * size.y)
	
	var water_level := _calculate_water_level(hmap)
	var springs := _generate_springs(hmap, water_level)
	
	_fill_water_bodies(amount, hmap, water_level)
	_log_liquid_stats(amount, springs, water_level)
	
	return {"amount": amount, "springs": springs}

func _calculate_water_level(hmap: PackedInt32Array) -> int:
	var min_h := hmap[0]
	var max_h := hmap[0]
	
	for x in size.x:
		min_h = min(min_h, hmap[x])
		max_h = max(max_h, hmap[x])
	
	return int(lerp(float(min_h), float(max_h), profile.water_level_ratio))

func _fill_water_bodies(amount: PackedInt64Array, hmap: PackedInt32Array, water_level: int) -> void:
	var seg_start := -1
	
	for x in size.x:
		if hmap[x] >= water_level:
			if seg_start == -1:
				seg_start = x
		else:
			if seg_start != -1:
				_fill_lake(amount, hmap, seg_start, x - 1, water_level)
				seg_start = -1
	
	# Handle segment extending to right edge
	if seg_start != -1:
		_fill_lake(amount, hmap, seg_start, size.x - 1, water_level)

func _fill_lake(
	amount: PackedInt64Array,
	hmap: PackedInt32Array,
	start_x: int,
	end_x: int,
	water_level: int
) -> void:
	var width := end_x - start_x + 1
	
	if width < profile.water_min_lake_size:
		return
	
	for x in range(start_x, end_x + 1):
		var ground_y := hmap[x]
		for y in range(water_level, ground_y):
			var depth_from_surface := y - water_level + 1
			var fill_ratio: float = clamp(float(depth_from_surface) / profile.water_depth_scale, 0.0, 1.0)
			var idx := y * size.x + x
			amount[idx] = int(round(fill_ratio * profile.water_capacity_mg_per_cell))

func _generate_springs(hmap: PackedInt32Array, water_level: int) -> PackedVector2Array:
	var springs := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_height
	var spawn_prob := profile.water_springs_per_k / 1000.0
	
	for x in range(1, size.x - 1):
		var h := hmap[x]
		
		# Only generate springs above water level with sufficient slope
		if h >= water_level:
			continue
		
		var slope_left: int = abs(h - hmap[x - 1])
		var slope_right: int = abs(h - hmap[x + 1])
		
		if max(slope_left, slope_right) < 2:
			continue
		
		if rng.randf() < spawn_prob:
			springs.append(Vector2i(x, h))
	
	return springs

func _log_liquid_stats(amount: PackedInt64Array, springs: PackedVector2Array, water_level: int) -> void:
	var cell_count := 0
	var min_amount := 0
	var max_amount := 0
	
	for i in amount.size():
		var v := amount[i]
		if v > 0:
			cell_count += 1
			if min_amount == 0 or v < min_amount:
				min_amount = v
			if v > max_amount:
				max_amount = v
	
	print("[WorldGen] Liquids: cells=%d min=%d max=%d springs=%d water_level=%d"
		% [cell_count, min_amount, max_amount, springs.size(), water_level])

# ══════════════════════════════════════════════════════════════════
# Utilities
# ══════════════════════════════════════════════════════════════════

func _create_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	return noise

static func _cc_to_ck(cC: int) -> int:
	return cC + CK_0C

func _assert_world_arrays(
	substances: PackedInt32Array,
	phases: PackedByteArray,
	mass: PackedInt64Array,
	temperatures: PackedInt32Array,
	tiles: PackedInt32Array
) -> void:
	var expected_size := size.x * size.y
	var sizes := [
		substances.size(),
		phases.size(),
		mass.size(),
		temperatures.size(),
		tiles.size()
	]
	
	if sizes.any(func(s): return s != expected_size):
		push_error("[WorldGen] Array size mismatch: expected=%d" % expected_size)
