extends Node
class_name Liquid

# Holds initial liquid amount and spring markers. No simulation yet.

var size: Vector2i
var amounts: PackedFloat32Array = PackedFloat32Array()
var springs: PackedVector2Array = PackedVector2Array()

func setup(initial_amounts: PackedFloat32Array, spring_cells: PackedVector2Array, grid_size: Vector2i) -> void:
	# Store liquid distribution and spring positions
	size = grid_size
	amounts = PackedFloat32Array(initial_amounts)
	springs = PackedVector2Array(spring_cells)
