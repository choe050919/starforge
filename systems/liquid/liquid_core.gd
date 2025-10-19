extends RefCounted
class_name LiquidCore

const RESIDUAL_SURFACE_MASS := 1000
const PH_VACUUM := 0
const PH_SOLID  := 1
const PH_LIQUID := 2

var _active_cells: Array[int] = []

func rebuild_active_cells(ph: PackedByteArray, m: PackedInt64Array) -> void:
	_active_cells.clear()
	
	for i in ph.size():
		if ph[i] == PH_LIQUID and m[i] > 0:
			_active_cells.append(i)

func compute_diff(R: Dictionary, _dt: float) -> Dictionary:
	var idx: GridIndex             = R["idx"]
	var ph_read: PackedByteArray   = R["ph"]
	var m_read: PackedInt64Array   = R["m"]
	var T_read: PackedInt32Array   = R["T"]
	var cap: int                   = int(R["cap"])

	var w: int = idx.size.x
	var h: int = idx.size.y
	var n: int = w * h

	rebuild_active_cells(ph_read, m_read)

	var mass_delta := PackedInt64Array()
	mass_delta.resize(n)
	for i in n: 
		mass_delta[i] = 0

	var flows: Array = []
	var moved_total: int = 0

	var free := PackedInt64Array()
	free.resize(n)
	for i in n:
		if ph_read[i] == PH_SOLID:
			free[i] = 0
		else:
			var liquid_mass := m_read[i] if ph_read[i] == PH_LIQUID else 0
			free[i] = cap - liquid_mass

	_active_cells.sort_custom(func(a: int, b: int) -> bool:
		var ya := a / w
		var yb := b / w
		return ya > yb
	)

	for i in _active_cells:
		if ph_read[i] != PH_LIQUID or m_read[i] <= 0:
			continue

		var cell := idx.cell(i)
		var x := cell.x
		var y := cell.y
		var m_here: int = m_read[i]

		# ── 1) 아래로 낙하 ──
		var sent: int = 0
		var down := Vector2i(x, y + 1)
		if idx.in_bounds_cell(down):
			var di := idx.idx(down)
			if ph_read[di] != PH_SOLID:
				var can := int(min(m_here - sent, free[di]))
				if can > 0:
					mass_delta[di] += can
					mass_delta[i]  -= can
					sent          += can
					moved_total   += can
					free[di]      -= can
					
					flows.append({
						"from": i,
						"to": di,
						"amount": can,
						"temp": T_read[i]
					})

		# ── 2) 좌/우 평형 ──
		var remain := m_here - sent
		if remain > 0 and remain >= RESIDUAL_SURFACE_MASS:
			# ← 왼쪽
			var left := Vector2i(x - 1, y)
			if idx.in_bounds_cell(left):
				var li := idx.idx(left)
				if ph_read[li] != PH_SOLID:
					var m_l := m_read[li] if ph_read[li] == PH_LIQUID else 0
					var diff_l := (remain - m_l) / 2
					if diff_l > 0:
						var can_l := int(min(diff_l, remain, free[li]))
						if can_l > 0:
							mass_delta[li] += can_l
							mass_delta[i]  -= can_l
							remain         -= can_l
							moved_total    += can_l
							free[li]       -= can_l
							
							flows.append({
								"from": i,
								"to": li,
								"amount": can_l,
								"temp": T_read[i]
							})

			# → 오른쪽
			if remain > 0:
				var right := Vector2i(x + 1, y)
				if idx.in_bounds_cell(right):
					var ri := idx.idx(right)
					if ph_read[ri] != PH_SOLID:
						var m_r := m_read[ri] if ph_read[ri] == PH_LIQUID else 0
						var diff_r := (remain - m_r) / 2
						if diff_r > 0:
							var can_r := int(min(diff_r, remain, free[ri]))
							if can_r > 0:
								mass_delta[ri] += can_r
								mass_delta[i]  -= can_r
								remain         -= can_r
								moved_total    += can_r
								free[ri]       -= can_r
								
								flows.append({
									"from": i,
									"to": ri,
									"amount": can_r,
									"temp": T_read[i]
								})

	# 새 질량 계산
	var m_new := PackedInt64Array()
	m_new.resize(n)
	for i in n:
		var v := m_read[i] + mass_delta[i]
		if v < 0: v = 0
		elif v > cap: v = cap
		m_new[i] = v

	# 새 온도 계산
	var T_new := _compute_temperatures(ph_read, m_read, T_read, m_new, flows)

	return {
		"mass_new": m_new,
		"temp_new": T_new,
		"moved_total": moved_total,
	}

func _compute_temperatures(
	ph: PackedByteArray,
	m_old: PackedInt64Array,
	T_old: PackedInt32Array,
	m_new: PackedInt64Array,
	flows: Array
) -> PackedInt32Array:
	var n := m_old.size()
	var T_new := T_old.duplicate()
	
	var energy_map: Dictionary = {}
	
	# 기존 액체 에너지
	for i in n:
		if ph[i] == PH_LIQUID and m_old[i] > 0:
			energy_map[i] = {
				"energy": float(m_old[i]) * float(T_old[i]),
				"mass": m_old[i]
			}
	
	# 유동 에너지 합산
	for flow in flows:
		var from_i: int = flow["from"]
		var to_i: int = flow["to"]
		var amount: int = flow["amount"]
		var temp: int = flow["temp"]
		
		# 출발지에서 에너지 제거
		if energy_map.has(from_i):
			energy_map[from_i]["energy"] -= float(amount) * float(temp)
			energy_map[from_i]["mass"] -= amount
		
		# 도착지에 에너지 추가
		if not energy_map.has(to_i):
			energy_map[to_i] = {"energy": 0.0, "mass": 0}
		
		energy_map[to_i]["energy"] += float(amount) * float(temp)
		energy_map[to_i]["mass"] += amount
	
	# 최종 온도 계산
	for i in energy_map:
		var data = energy_map[i]
		if data["mass"] > 0:
			T_new[i] = int(round(data["energy"] / float(data["mass"])))
		else:
			T_new[i] = 0
	
	# 비워진 셀은 0
	for i in n:
		if m_new[i] <= 0:
			T_new[i] = 0
	
	return T_new
