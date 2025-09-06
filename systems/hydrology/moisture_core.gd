# 순수 계산 전용: 침투 → 누수(1층) → 수평/수직 확산(간선 중복 방지: 우/하만 처리)
extends RefCounted
class_name MoistureCore

static func step(
	w: int, h: int, n: int,
	soil_indices: PackedInt32Array,
	soil_mask: PackedByteArray,
	moisture: PackedInt32Array,
	capacity: PackedInt32Array,
	infil: PackedInt32Array,
	leak: PackedInt32Array,
	diffu: PackedInt32Array,
	liquid_mg: PackedInt64Array
) -> Dictionary:
	var d_soil: PackedInt32Array = PackedInt32Array()
	d_soil.resize(n); d_soil.fill(0)

	var d_liquid: PackedInt64Array = PackedInt64Array()
	d_liquid.resize(n); d_liquid.fill(0)

	# ── 1) 침투: 같은 칸의 액체 → 토양
	for ii in soil_indices:
		var i: int = ii
		var cap_rem: int = capacity[i] - moisture[i]
		if cap_rem <= 0:
			continue
		var take_max: int = infil[i]
		if take_max <= 0:
			continue
		# 표면 액체(같은 칸)
		var surf_liq: int = int(liquid_mg[i]) if i >= 0 and i < liquid_mg.size() else 0
		if surf_liq <= 0:
			continue
		var take: int = cap_rem
		if take > take_max: take = take_max
		if take > surf_liq: take = surf_liq
		if take <= 0:
			continue
		d_soil[i] += take
		d_liquid[i] -= int(take)

	# ── 2) 누수(중력, 1층): 토양 → 아래칸(토양이면 그쪽으로, 아니면 액체로 용출)
	for ii in soil_indices:
		var i: int = ii
		var give_max: int = leak[i]
		if give_max <= 0: continue
		var have: int = moisture[i]
		if have <= 0: continue

		var y: int = i / w
		if y >= h - 1:
			continue  # 맵 바깥으로는 누수하지 않음

		var down: int = i + w
		var to_soil: bool = (down >= 0 and down < n and soil_mask[down] == 1)

		if to_soil:
			var down_cap: int = capacity[down] - moisture[down] - d_soil[down]  # 동틱 유입 고려
			if down_cap <= 0: continue
			var give: int = give_max
			if give > have: give = have
			if give > down_cap: give = down_cap
			if give <= 0: continue
			d_soil[i] -= give
			d_soil[down] += give
		else:
			var give2: int = give_max
			if give2 > have: give2 = have
			if give2 <= 0: continue
			d_soil[i] -= give2
			# 아래 칸의 액체로 전환(용출)
			if down >= 0 and down < n:
				d_liquid[down] += int(give2)
			# down이 맵 밖이면 버림(희귀); v0에선 무시

	# ── 3) 확산(토양↔토양): 좌우/상하 모두 다루되, 간선 중복을 피하려고 '우/하'만 처리
	for ii in soil_indices:
		var i: int = ii
		var x: int = i % w
		var y2: int = i / w

		# (a) 우측 이웃
		if x < w - 1:
			var r: int = i + 1
			if soil_mask[r] == 1:
				var di: int = moisture[i] + d_soil[i]
				var dj: int = moisture[r] + d_soil[r]
				var diff: int = di - dj
				if diff > 0:
					var lim_edge: int = diffu[i]
					if lim_edge > diffu[r]: lim_edge = diffu[r]
					var flux: int = diff / 2
					if flux > lim_edge: flux = lim_edge
					if flux > 0:
						d_soil[i] -= flux
						d_soil[r] += flux

		# (b) 하측 이웃
		if y2 < h - 1:
			var d: int = i + w
			if soil_mask[d] == 1:
				var di2: int = moisture[i] + d_soil[i]
				var dj2: int = moisture[d] + d_soil[d]
				var diff2: int = di2 - dj2
				if diff2 > 0:
					var lim_edge2: int = diffu[i]
					if lim_edge2 > diffu[d]: lim_edge2 = diffu[d]
					var flux2: int = diff2 / 2
					if flux2 > lim_edge2: flux2 = lim_edge2
					if flux2 > 0:
						d_soil[i] -= flux2
						d_soil[d] += flux2

	return {
		"d_soil": d_soil,
		"d_liquid": d_liquid,
	}
