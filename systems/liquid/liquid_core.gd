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

	# 부력 추가
	var buoyancy_moved := _apply_buoyancy(
		idx, ph_read, m_read, T_read, 
		mass_delta, flows, w, h,
		free
	)
	moved_total += buoyancy_moved

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

func _apply_buoyancy(
	idx: GridIndex,
	ph: PackedByteArray,
	m: PackedInt64Array,
	T: PackedInt32Array,
	mass_delta: PackedInt64Array,
	flows: Array,
	w: int, h: int,
	free: PackedInt64Array
) -> int:
	const VERTICAL_STRENGTH := 0.3
	const HORIZONTAL_STRENGTH := 0.2
	const MIN_MASS_THRESHOLD := 100
	const MIN_TEMP_DIFF := 50
	
	var buoyancy_moved := 0
	
	# 현재 질량 추적
	var m_current := PackedInt64Array()
	m_current.resize(m.size())
	for i in m.size():
		m_current[i] = m[i]
	
	# ═══ 1. 수직 부력 ═══
	for y in range(h - 2, -1, -1):
		for x in w:
			var i := y * w + x
			var down_i := (y + 1) * w + x
			
			if ph[i] != PH_LIQUID or ph[down_i] != PH_LIQUID:
				continue
			if m_current[i] <= MIN_MASS_THRESHOLD or m_current[down_i] <= MIN_MASS_THRESHOLD:
				continue
			
			if T[down_i] > T[i]:
				var temp_diff_c := float(T[down_i] - T[i]) / 100.0
				var avg_mass := (m_current[i] + m_current[down_i]) / 2.0
				var swap_ratio : float= min(temp_diff_c * 0.01, 1.0) * VERTICAL_STRENGTH
				var swap_amount := int(avg_mass * swap_ratio)
				
				swap_amount = clampi(swap_amount, 0, min(m_current[i], m_current[down_i]))
				
				if swap_amount > 0:
					# 뜨거운 것(아래) → 위로
					m_current[i] += swap_amount
					m_current[down_i] -= swap_amount
					free[i] += swap_amount
					free[down_i] -= swap_amount
					
					mass_delta[i] += swap_amount
					mass_delta[down_i] -= swap_amount
					flows.append({"from": down_i, "to": i, "amount": swap_amount, "temp": T[down_i]})
					
					# 차가운 것(위) → 아래로
					m_current[down_i] += swap_amount
					m_current[i] -= swap_amount
					free[down_i] += swap_amount
					free[i] -= swap_amount
					
					mass_delta[down_i] += swap_amount
					mass_delta[i] -= swap_amount
					flows.append({"from": i, "to": down_i, "amount": swap_amount, "temp": T[i]})
					
					buoyancy_moved += swap_amount * 2
	
	# ═══ 2. 수평 확산 (교환 방식) ═══
	for y in h:
		for x in range(w - 1):
			var left_i := y * w + x
			var right_i := y * w + (x + 1)
			
			if ph[left_i] != PH_LIQUID or ph[right_i] != PH_LIQUID:
				continue
			if m_current[left_i] <= MIN_MASS_THRESHOLD or m_current[right_i] <= MIN_MASS_THRESHOLD:
				continue
			
			var temp_diff := T[left_i] - T[right_i]
			if abs(temp_diff) < MIN_TEMP_DIFF:
				continue
			
			var hot_i := left_i if temp_diff > 0 else right_i
			var cold_i := right_i if hot_i == left_i else left_i
			
			# 교환 방식: 양쪽 질량의 일부를 맞교환
			var swap_amount := int(min(m_current[hot_i], m_current[cold_i]) * HORIZONTAL_STRENGTH)
			swap_amount = clampi(swap_amount, 0, min(m_current[hot_i], m_current[cold_i]))
			
			if swap_amount > 0:
				# 뜨거운 것 → 차가운 쪽으로
				mass_delta[cold_i] += swap_amount
				mass_delta[hot_i] -= swap_amount
				m_current[cold_i] += swap_amount
				m_current[hot_i] -= swap_amount
				
				flows.append({
					"from": hot_i,
					"to": cold_i,
					"amount": swap_amount,
					"temp": T[hot_i]
				})
				
				# 차가운 것 → 뜨거운 쪽으로
				mass_delta[hot_i] += swap_amount
				mass_delta[cold_i] -= swap_amount
				m_current[hot_i] += swap_amount
				m_current[cold_i] -= swap_amount
				
				flows.append({
					"from": cold_i,
					"to": hot_i,
					"amount": swap_amount,
					"temp": T[cold_i]
				})
				
				buoyancy_moved += swap_amount * 2
	
	return buoyancy_moved

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
