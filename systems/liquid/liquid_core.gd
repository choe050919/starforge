# liquid_core.gd
extends RefCounted
class_name LiquidCore

## 표면장력에 의해 옆으로 완전히 흐르지 않고 남는 액체의 질량 값
const RESIDUAL_SURFACE_MASS := 1000

const PH_VACUUM := 0
const PH_SOLID  := 1
const PH_LIQUID := 2

## 활성 액체 셀 추적
var _active_cells: Array[int] = []  # PackedInt32Array → Array[int]

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

	# 활성 셀 재구축
	rebuild_active_cells(ph_read, m_read)

	var mass_delta := PackedInt64Array()
	mass_delta.resize(n)
	for i in n: 
		mass_delta[i] = 0

	var temp_writes: Array = []
	var temp_written := PackedByteArray()
	temp_written.resize(n)
	for i in n: 
		temp_written[i] = 0

	var moved_total: int = 0

	# 수신 잔여 용량 버퍼
	var free := PackedInt64Array()
	free.resize(n)
	for i in n:
		if ph_read[i] == PH_SOLID:
			free[i] = 0
		else:
			var liquid_mass := m_read[i] if ph_read[i] == PH_LIQUID else 0
			free[i] = cap - liquid_mass

	# ── Y좌표 기준 정렬 (하단부터) ──
	_active_cells.sort_custom(func(a: int, b: int) -> bool:
		var ya := a / w
		var yb := b / w
		return ya > yb  # 내림차순
	)

	# ── 활성 셀만 순회 ──
	for i in _active_cells:
		# 이미 비워진 경우 스킵
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
					if m_read[di] == 0 and temp_written[di] == 0:
						temp_writes.push_back({"i": di, "T": T_read[i]})
						temp_written[di] = 1
					
					mass_delta[di] += can
					mass_delta[i]  -= can
					sent          += can
					moved_total   += can
					free[di]      -= can

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
							if m_l == 0 and temp_written[li] == 0:
								temp_writes.push_back({"i": li, "T": T_read[i]})
								temp_written[li] = 1
							
							mass_delta[li] += can_l
							mass_delta[i]  -= can_l
							remain         -= can_l
							moved_total    += can_l
							free[li]       -= can_l

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
								if m_r == 0 and temp_written[ri] == 0:
									temp_writes.push_back({"i": ri, "T": T_read[i]})
									temp_written[ri] = 1
								
								mass_delta[ri] += can_r
								mass_delta[i]  -= can_r
								remain         -= can_r
								moved_total    += can_r
								free[ri]       -= can_r

	return {
		"mass_delta": mass_delta,
		"temp_writes": temp_writes,
		"moved_total": moved_total,
	}
