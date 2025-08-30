extends Node
class_name Liquid

# 여기도 있고 liquid_overlay에도 있음. 문제!!!!
@export var water_capacity_mg_per_cell: int = 1_000_000_000

var data: DataLayer
var springs: PackedVector2Array = PackedVector2Array()

func setup(layer: DataLayer, spring_cells: PackedVector2Array) -> void:
	data = layer
	if data == null:
		push_error("[Liquid]")
	springs = PackedVector2Array(spring_cells)

func tick_liquid(_dt: float) -> void:
	var idx := data.index
	var substance := data.substance
	var phase := data.phase
	var mass := data.mass
	var w := idx.size.x
	var h := idx.size.y

	# ── 스냅샷 잡기 ──────────────────────────────────────
	var read_mass := mass.get_read()          # 질량 읽기 버퍼 스냅샷
	var ph_read := phase.get_raw_read()      # phase 읽기 버퍼 스냅샷

	# ── 쓰기 시작 ────────────────────────────────────────
	mass.begin_write()

	for y in range(h - 1, -1, -1):
		for x in range(w):
			var cell := Vector2i(x, y)
			var i := idx.idx(cell)

			# 고체 셀은 스킵
			if ph_read[i] == PhaseStore.Phase.SOLID:
				continue

			# 현재 셀의 '액체로 인정되는 양'
			var m: int = _liq_at_index(i, read_mass, ph_read)
			if m <= 0:
				continue

			# ↓ 아래로
			var sent := 0
			var down := Vector2i(x, y + 1)
			if idx.in_bounds_cell(down):
				var di := idx.idx(down)
				if ph_read[di] != PhaseStore.Phase.SOLID:
					var down_liq: int = _liq_at_index(di, read_mass, ph_read)
					var cap_down: int = water_capacity_mg_per_cell - down_liq
					if cap_down > 0:
						var flow_down = min(m, cap_down)
						if flow_down > 0:
							mass.add(di, flow_down)
							mass.add(i, -flow_down)
							sent += flow_down

			# ←→ 좌/우 평형 (남은 양 기준)
			var remain := m - sent
			if remain > 0:
				# ← 왼쪽
				var left := Vector2i(x - 1, y)
				if idx.in_bounds_cell(left):
					var li := idx.idx(left)
					if ph_read[li] != PhaseStore.Phase.SOLID:
						var l_liq: int = _liq_at_index(li, read_mass, ph_read)
						var diff_l: int = (remain - l_liq) / 2
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
					if idx.in_bounds_cell(right):
						var ri := idx.idx(right)
						if ph_read[ri] != PhaseStore.Phase.SOLID:
							var r_liq: int = _liq_at_index(ri, read_mass, ph_read)
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

	# --- 최종 질량 기준으로 Phase/Substance 일괄 정리 ---
	var final := mass.get_read()    # 읽기 스냅샷
	ph_read = phase.get_raw_read() # 현재 확정된 phase 스냅샷(배치 비교용)

	substance.begin_write()
	phase.begin_write()

	for i in final.size():
		if ph_read[i] == PhaseStore.Phase.SOLID:
			continue
		var has := final[i] > 0
		var want_ph = PhaseStore.Phase.LIQUID if has else PhaseStore.Phase.VACUUM
		if ph_read[i] != want_ph:
			phase.set_by_index(i, want_ph)

		# Substance도 동기화 (물만 다룸)
		var cur_sid := substance.get_by_index(i)
		var want_sid = SubstanceStore.SubstanceId.WATER if has else SubstanceStore.SubstanceId.VACUUM
		if cur_sid != want_sid:
			substance.set_by_index(i, want_sid)

	substance.commit()
	phase.commit()

func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	var read_mass := data.mass.get_read()
	var ph_read := data.phase.get_raw_read()
	var out := PackedInt64Array()
	out.resize(read_mass.size())
	for i in read_mass.size():
		out[i] = read_mass[i] if ph_read[i] == PhaseStore.Phase.LIQUID else 0
	return out

func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	print("[Liquid.on_tile_destroyed]")
	if data == null: return

	# 질량 0으로
	data.mass.begin_write()
	data.mass.set_cell(cell, 0) # 정수 mg
	data.mass.commit()

	# Phase도 트랜잭션으로
	data.phase.begin_write()
	data.phase.set_phase(cell, PhaseStore.Phase.VACUUM)
	data.phase.commit()

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	print("[Liquid.on_tile_replaced]")
	if data == null: return

	data.mass.begin_write()
	data.mass.set_cell(cell, 0)
	data.mass.commit()

	var phase := PhaseStore.Phase.SOLID if to_tile != 0 else PhaseStore.Phase.VACUUM
	data.phase.begin_write()
	data.phase.set_phase(cell, phase)
	data.phase.commit()

func _liq_at_index(i: int, read: PackedInt64Array, ph_read: PackedByteArray) -> int:
	return read[i] if ph_read[i] == PhaseStore.Phase.LIQUID else 0

func _liq_at_cell(cell: Vector2i, read_mass: PackedInt64Array, ph_read: PackedByteArray) -> int:
	return _liq_at_index(data.index.idx(cell), read_mass, ph_read)
