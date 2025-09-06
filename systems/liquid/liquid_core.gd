extends RefCounted
class_name LiquidCore

const PH_VACUUM := 0
const PH_SOLID  := 1
const PH_LIQUID := 2

## 클래스 레벨 헬퍼: 액체로 인정되는 양만 반환
func _liq_at(i: int, ph_read: PackedByteArray, m_read: PackedInt64Array) -> int:
	return m_read[i] if ph_read[i] == PH_LIQUID else 0

func compute_diff(R: Dictionary, _dt: float) -> Dictionary:
	var idx: GridIndex             = R["idx"]
	var ph_read: PackedByteArray   = R["ph"]
	var m_read: PackedInt64Array   = R["m"]
	var T_read: PackedInt32Array   = R["T"]
	var cap: int                   = int(R["cap"])

	var w: int = idx.size.x
	var h: int = idx.size.y
	var n: int = w * h

	## 각 셀의 질량 변화량(유입은 +, 유출은 −)을 누적할 배열.
	var mass_delta := PackedInt64Array(); mass_delta.resize(n)
	for i in n: mass_delta[i] = 0

	var temp_writes: Array = []
	var temp_written := PackedByteArray(); temp_written.resize(n)
	for i in n: temp_written[i] = 0

	var moved_total: int = 0

	var touched_mask := PackedByteArray(); touched_mask.resize(n)
	for i in n: touched_mask[i] = 0

	# 수신 잔여 용량(헤드룸) 예약용 버퍼
	var free := PackedInt64Array(); free.resize(n)
	for i in n:
		if ph_read[i] == PH_SOLID:
			free[i] = 0
		else:
			free[i] = cap - _liq_at(i, ph_read, m_read)  # VACUUM이면 cap, LIQUID면 cap - 현재양

	for y in range(h - 1, -1, -1):
		for x in range(w):
			var i: int = idx.idx(Vector2i(x, y))

			# 고체 셀 스킵
			if ph_read[i] == PH_SOLID:
				continue

			var m_here: int = _liq_at(i, ph_read, m_read)
			if m_here <= 0:
				continue

			# ── 1) 아래로 낙하
			var sent: int = 0
			var down := Vector2i(x, y + 1)
			if idx.in_bounds_cell(down):
				var di := idx.idx(down)
				if ph_read[di] != PH_SOLID:
					var can := int(min(m_here - sent, free[di]))
					if can > 0:
						if _liq_at(di, ph_read, m_read) == 0 and temp_written[di] == 0:
							temp_writes.push_back({ "i": di, "T": T_read[i] })
							temp_written[di] = 1
						mass_delta[di] += can
						mass_delta[i]  -= can
						sent          += can
						moved_total   += can
						free[di]      -= can

			# ── 2) 좌/우 평형
			var remain := m_here - sent
			if remain > 0:
				if remain < 1000:
					continue
				# ← 왼쪽
				var left := Vector2i(x - 1, y)
				if idx.in_bounds_cell(left):
					var li := idx.idx(left)
					if ph_read[li] != PH_SOLID:
						var m_l := _liq_at(li, ph_read, m_read)
						var diff_l := (remain - m_l) / 2
						if diff_l > 0:
							var can_l := int(min(diff_l, remain, free[li]))
							if can_l > 0:
								if m_l == 0 and temp_written[li] == 0:
									temp_writes.push_back({ "i": li, "T": T_read[i] })
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
							var m_r := _liq_at(ri, ph_read, m_read)
							var diff_r := (remain - m_r) / 2
							if diff_r > 0:
								var can_r := int(min(diff_r, remain, free[ri]))
								if can_r > 0:
									if m_r == 0 and temp_written[ri] == 0:
										temp_writes.push_back({ "i": ri, "T": T_read[i] })
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
		"touched_mask": touched_mask,
	}
