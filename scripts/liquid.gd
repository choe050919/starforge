extends Node
class_name Liquid

var data: DataLayer
var springs: PackedVector2Array = PackedVector2Array()

func setup(layer: DataLayer, spring_cells: PackedVector2Array) -> void:
	data = layer
	springs = PackedVector2Array(spring_cells)

func tick_liquid(_dt: float) -> void:
	if data == null:
			return
	var idx := data.index
	var phases := data.phase
	var mass := data.mass
	var w := idx.size.x
	var h := idx.size.y
	var read := mass.get_read()
	mass.begin_write()
	for y in range(h - 1, -1, -1):
		for x in range(w):
			var cell := Vector2i(x, y)
			var i := idx.idx(cell)
			var m := read[i]
			if m <= 0.0:
				continue
			if phases.get_by_index(i) == PhaseStore.SOLID:
				mass.set_mass(i, 0.0)
				continue
			var moved := false
			var down := Vector2i(x, y + 1)
			if idx.in_bounds(down) and not phases.is_solid(down):
				var di := idx.idx(down)
				var cap := 1.0 - read[di]
				if cap > 0.0:
					var flow = min(m, cap)
					if flow > 0.0:
						mass.add(di, flow)
						mass.add(i, -flow)
						if not phases.is_liquid(down):
							phases._set_internal(down, PhaseStore.LIQUID)
						moved = true
			if not moved:
				var left := Vector2i(x - 1, y)
				if idx.in_bounds(left) and not phases.is_solid(left):
					var li := idx.idx(left)
					var diff_l := (read[i] - read[li]) * 0.5
					var flow_l = min(diff_l, m, 1.0 - read[li])
					if flow_l > 0.0:
						mass.add(li, flow_l)
						mass.add(i, -flow_l)
						if not phases.is_liquid(left):
							phases._set_internal(left, PhaseStore.LIQUID)
				var right := Vector2i(x + 1, y)
				if idx.in_bounds(right) and not phases.is_solid(right):
					var ri := idx.idx(right)
					var diff_r := (read[i] - read[ri]) * 0.5
					var flow_r = min(diff_r, m, 1.0 - read[ri])
					if flow_r > 0.0:
						mass.add(ri, flow_r)
						mass.add(i, -flow_r)
						if not phases.is_liquid(right):
							phases._set_internal(right, PhaseStore.LIQUID)
	mass.commit()
	var final := mass.get_read()
	for i in final.size():
		if final[i] <= 0.0 and phases.get_by_index(i) == PhaseStore.LIQUID:
			phases._set_internal(idx.cell(i), PhaseStore.VACUUM)

func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	return data.mass.get_read()

func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if data == null:
		return
	data.phase._set_internal(cell, PhaseStore.VACUUM)
	var i := data.index.idx(cell)
	data.mass.set_mass(i, 0.0)

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if data == null:
		return
	var phase := PhaseStore.SOLID if to_tile != 0 else PhaseStore.VACUUM
	data.phase._set_internal(cell, phase)
	var i := data.index.idx(cell)
	data.mass.set_mass(i, 0.0)
