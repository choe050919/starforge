extends Node
class_name Durability

signal break_requested(cell: Vector2i)
signal hp_changed(cell: Vector2i, hp: float, max_hp: float)

var size: Vector2i
var hp: PackedFloat32Array = PackedFloat32Array()
var max_hp: PackedFloat32Array = PackedFloat32Array()
var _broken: PackedByteArray = PackedByteArray()

const TILE_AIR := 0
const TILE_ICE := 1
const TILE_GROUND := 2
const TILE_URANIUM := 3

@export var hp_air_default: float = 0.0
@export var hp_ice_default: float = 6.0
@export var hp_ground_default: float = 10.0
@export var hp_uranium_default: float = 25.0

func setup_from_tiles(tile_types: PackedInt32Array, grid_size: Vector2i) -> void:
		size = grid_size
		var total := size.x * size.y
		hp = PackedFloat32Array(); hp.resize(total)
		max_hp = PackedFloat32Array(); max_hp.resize(total)
		_broken = PackedByteArray(); _broken.resize(total)

		for y in size.y:
				for x in size.x:
						var idx := y * size.x + x
						var tt := tile_types[idx]
						var m := _default_hp(tt)
						max_hp[idx] = m
						hp[idx] = m
						_broken[idx] = 0

func _default_hp(tt: int) -> float:
		match tt:
				TILE_GROUND:
						return hp_ground_default
				TILE_ICE:
						return hp_ice_default
				TILE_URANIUM:
						return hp_uranium_default
				_:
						return hp_air_default

func _cell_index(cell: Vector2i) -> int:
		return cell.y * size.x + cell.x

func apply_damage(cell: Vector2i, amount: float, _type: StringName = &"generic") -> void:
		if size == Vector2i.ZERO:
				return
		if amount <= 0.0:
				return
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
				return
		var idx := _cell_index(cell)
		if idx < 0 or idx >= hp.size():
				return
		if max_hp[idx] <= 0.0:
				return
		hp[idx] -= amount
		if hp[idx] < 0.0:
				hp[idx] = 0.0
		emit_signal("hp_changed", cell, hp[idx], max_hp[idx])
		if hp[idx] <= 0.0 and _broken[idx] == 0:
				_broken[idx] = 1
				emit_signal("break_requested", cell)

func get_hp(cell: Vector2i) -> float:
		var idx := _cell_index(cell)
		if idx < 0 or idx >= hp.size():
				return 0.0
		return hp[idx]

func get_max_hp(cell: Vector2i) -> float:
		var idx := _cell_index(cell)
		if idx < 0 or idx >= max_hp.size():
				return 0.0
		return max_hp[idx]

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
		if size == Vector2i.ZERO:
				return
		var idx := _cell_index(cell)
		if idx < 0 or idx >= hp.size():
				return
		var m := _default_hp(to_tile)
		max_hp[idx] = m
		hp[idx] = m
		_broken[idx] = 0
		if m <= 0.0:
				hp[idx] = 0.0
		emit_signal("hp_changed", cell, hp[idx], max_hp[idx])

 
