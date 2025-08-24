extends Node
class_name Liquid

# 여기도 있고 liquid_overlay에도 있음. 문제!!!!
@export var water_capacity_mg_per_cell: int = 1_000_000

var data: DataLayer
var springs: PackedVector2Array = PackedVector2Array()

func setup(layer: DataLayer, spring_cells: PackedVector2Array) -> void:
	data = layer
	if data == null:
		push_error("[Liquid]")
	springs = PackedVector2Array(spring_cells)

func tick_liquid(_dt: float) -> void:
	var idx := data.index
	var phases := data.phase
	var mass := data.mass
	var w := idx.size.x
	var h := idx.size.y

	var read := mass.get_read()         # 읽기 스냅샷
	mass.begin_write()                  # 쓰기 시작

	for y in range(h - 1, -1, -1):
		for x in range(w):
			var cell := Vector2i(x, y)
			var i := idx.idx(cell)

			# 고체 셀은 스킵
			if phases.get_by_index(i) == PhaseStore.Phase.SOLID:
				continue

			# 현재 셀의 '액체로 인정되는 양'만 사용
			var m: int = _liq_at_index(i, read)
			if m <= 0:
				continue

			# ↓ 아래로
			var sent := 0
			var down := Vector2i(x, y + 1)
			if idx.in_bounds_cell(down) and phases.get_by_index(idx.idx(down)) != PhaseStore.Phase.SOLID:
				var di := idx.idx(down)
				var down_liq: int = _liq_at_index(di, read)
				var cap_down: int = water_capacity_mg_per_cell - down_liq
				if cap_down > 0:
					var flow_down = min(m, cap_down)
					if flow_down > 0:
						mass.add(di, flow_down)
						mass.add(i, -flow_down)
						sent += flow_down

			# ←→ 좌/우 평형은 남은 양 기준으로
			var remain := m - sent
			if remain > 0:
				# ← 왼쪽
				var left := Vector2i(x - 1, y)
				if idx.in_bounds_cell(left) and phases.get_by_index(idx.idx(left)) != PhaseStore.Phase.SOLID:
					var li := idx.idx(left)
					var l_liq: int = _liq_at_index(li, read)
					var diff_l: int = (remain - l_liq) / 2  # integer div OK
					if diff_l > 0:
						var cap_l: int = water_capacity_mg_per_cell - l_liq
						var flow_l = min(diff_l, remain, cap_l)
						if flow_l > 0:
							mass.add(li, flow_l)
							mass.add(i, -flow_l)
							remain -= flow_l

				# → 오른쪽 (왼쪽 이후 갱신된 remain 기준)
				if remain > 0:
					var right := Vector2i(x + 1, y)
					if idx.in_bounds_cell(right) and phases.get_by_index(idx.idx(right)) != PhaseStore.Phase.SOLID:
						var ri := idx.idx(right)
						var r_liq: int = _liq_at_index(ri, read)
						var diff_r: int = (remain - r_liq) / 2
						if diff_r > 0:
							var cap_r: int = water_capacity_mg_per_cell - r_liq
							var flow_r = min(diff_r, remain, cap_r)
							if flow_r > 0:
								mass.add(ri, flow_r)
								mass.add(i, -flow_r)
								remain -= flow_r

	# --- 질량 쓰기 반영 ---
	mass.commit()

	# --- 최종 질량 기준으로 Phase 한 번에 정리(Phase는 단일버퍼라 바로 set) ---
	var final := mass.get_read()
	for i in final.size():
		var ph := phases.get_by_index(i)
		if ph == PhaseStore.Phase.SOLID:
			continue
		if final[i] > 0:
			if ph != PhaseStore.Phase.LIQUID:
				# set_phase(cell, phase)가 있으면 그걸 쓰고, 없으면 _set_internal 임시 사용
				if phases.has_method("set_phase"):
					phases.set_phase(idx.cell(i), PhaseStore.Phase.LIQUID)
				else:
					phases._set_internal(idx.cell(i), PhaseStore.Phase.LIQUID)
		else:
			if ph != PhaseStore.Phase.VACUUM:
				if phases.has_method("set_phase"):
					phases.set_phase(idx.cell(i), PhaseStore.Phase.VACUUM)
				else:
					phases._set_internal(idx.cell(i), PhaseStore.Phase.VACUUM)

func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	var read := data.mass.get_read()
	var p := data.phase
	var out := PackedInt64Array()
	out.resize(read.size())
	for i in read.size():
		out[i] = read[i] if p.get_by_index(i) == PhaseStore.Phase.LIQUID else 0
	return out

func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if data == null:
		return
	# 질량 0으로
	data.mass.begin_write()
	data.mass.set_cell(cell, 0) # 정수 mg
	data.mass.commit()
	# Phase 즉시 반영 (단일버퍼 가정)
	if data.phase.has_method("set_phase"):
		data.phase.set_phase(cell, PhaseStore.Phase.VACUUM)
	else:
		data.phase._set_internal(cell, PhaseStore.Phase.VACUUM)

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if data == null:
		return
	data.mass.begin_write()
	data.mass.set_cell(cell, 0)
	data.mass.commit()
	var phase := PhaseStore.Phase.SOLID if to_tile != 0 else PhaseStore.Phase.VACUUM
	if data.phase.has_method("set_phase"):
		data.phase.set_phase(cell, phase)
	else:
		data.phase._set_internal(cell, phase)

func _liq_at_index(i: int, read: PackedInt64Array) -> int:
	return read[i] if data.phase.get_by_index(i) == PhaseStore.Phase.LIQUID else 0

func _liq_at_cell(cell: Vector2i, read: PackedInt64Array) -> int:
	return _liq_at_index(data.index.idx(cell), read)
