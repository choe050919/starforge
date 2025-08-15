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

const TILE_AIR: int = 0
const TILE_ICE: int = 1
const TILE_GROUND: int = 2

func generate() -> void:
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

	emit_signal("generated", tiles, size)
