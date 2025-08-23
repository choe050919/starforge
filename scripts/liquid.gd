extends Node
class_name Liquid

# 여기도 있고 liquid_overlay에도 있음. 문제!!!!
@export var water_capacity_mg_per_cell: int = 1_000_000

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

			# 고체 셀은 스킵
			if phases.get_by_index(i) == PhaseStore.SOLID:
				continue

			# 현재 셀의 '액체로 인정되는 양'만 사용
			var m: int = _liq_at_index(i, read)
			if m <= 0:
				continue

			var moved := false

			# ↓ 아래로 흐름 (중력)
			var down := Vector2i(x, y + 1)
			if idx.in_bounds(down) and not phases.is_solid(down):
				var di := idx.idx(down)
				var down_liq: int = _liq_at_index(di, read)
				var cap: int = water_capacity_mg_per_cell - down_liq
				if cap > 0:
					var flow: int = min(m, cap)
					if flow > 0:
						mass.add(di, flow)
						mass.add(i, -flow)
						if not phases.is_liquid(down):
							phases._set_internal(down, PhaseStore.LIQUID)
						moved = true

			# ←→ 좌우 평형 흐름
			if not moved:
				var left := Vector2i(x - 1, y)
				if idx.in_bounds(left) and not phases.is_solid(left):
					var li := idx.idx(left)
					var l_liq: int = _liq_at_index(li, read)
					var diff_l: int = (m - l_liq) / 2
					if diff_l > 0:
						var cap_l: int = water_capacity_mg_per_cell - l_liq
						var flow_l: int = min(diff_l, m, cap_l)
						if flow_l > 0:
							mass.add(li, flow_l)
							mass.add(i, -flow_l)
							if not phases.is_liquid(left):
								phases._set_internal(left, PhaseStore.LIQUID)

				var right := Vector2i(x + 1, y)
				if idx.in_bounds(right) and not phases.is_solid(right):
					var ri := idx.idx(right)
					var r_liq: int = _liq_at_index(ri, read)
					var diff_r: int = (m - r_liq) / 2
					if diff_r > 0:
						var cap_r: int = water_capacity_mg_per_cell - r_liq
						var flow_r: int = min(diff_r, m, cap_r)
						if flow_r > 0:
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
	var read := data.mass.get_read()
	var p := data.phase
	var out := PackedInt64Array()
	out.resize(read.size())
	for i in read.size():
		out[i] = read[i] if p.get_by_index(i) == PhaseStore.LIQUID else 0
	return out

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

func _liq_at_index(i: int, read: PackedInt64Array) -> int:
	return read[i] if data.phase.get_by_index(i) == PhaseStore.LIQUID else 0

func _liq_at_cell(cell: Vector2i, read: PackedInt64Array) -> int:
	return _liq_at_index(data.index.idx(cell), read)
