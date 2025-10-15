## 순수 온도 로직만 담당.
## - 저장은 TemperatureStore(cK, int32)를 사용
extends RefCounted
class_name TemperatureCore

const TILE_LEN_M := 0.1  # 0.1이라면 한 변의 길이가 0.1m
const GEOM_ORTHO := TILE_LEN_M  # A/d = L

## 저질량 처리의 기준값 (mg)
const MIN_MASS_FOR_CONDUCTION := 10_000

# 4방 탐색
const DIRS := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

## ΔQ 누적 버퍼. 단위: cJ(센티줄)
var heat_buffer: PackedFloat64Array = PackedFloat64Array()

func _ensure_capacity(n: int) -> void:
	if heat_buffer.size() != n:
		heat_buffer.resize(n)
		for i in n:
			heat_buffer[i] = 0.0

var k_per_sid: Dictionary[int, float] # 내부용: k_eff (이미 보정된 값)
var c_per_sid: Dictionary[int, float] # 내부용: SI 그 자체

# cache의 SI 테이블을, 내부에서 쓰기 좋은 딕셔너리로 1회 변환
func setup_thermal_from_cache(cache: SubstanceRuleCache) -> void:
	k_per_sid.clear()
	c_per_sid.clear()

	var loaded_count := 0
	for sid in cache.phase_of_sid.keys():
		var k_si := float(cache.k_by_sid.get(sid, 0.0)) # [W/m·K]
		var c_si := float(cache.c_by_sid.get(sid, 0.0)) # [J/kg·K]

		# 모든 sid를 등록 (0.0도 유효한 값 - 열전도 없음을 의미)
		k_per_sid[sid] = k_si
		c_per_sid[sid] = c_si * 1e-6 # 1mg을 1cK 변화시키는 데 필요한 열량(cJ)
		
		if k_si > 0.0 or c_si > 0.0:
			loaded_count += 1

	print("[TemperatureCore] Loaded thermal data for %d/%d substances (with properties)" 
		% [loaded_count, k_per_sid.size()])
	
	if k_per_sid.is_empty():
		push_warning("[TemperatureCore] No thermal data loaded! Check substance cache")
	
	# 샘플 출력
	if false:
		print("[TemperatureCore] Sample ICE: c=%.6f k=%.2f" 
			% [c_per_sid.get(10001, -999.0), k_per_sid.get(10001, -999.0)])

# ─────────────────────────────────────────────────────────
# 규칙 테이블 (sid 인덱스 접근)
# alpha_per_sid: α = k/c (무차원, 상대값). 확산 블렌딩에 사용.
# init_c_per_sid: 초기 온도(°C)
# heat_ckps_per_sid: 발열( cK/s )
var alpha_per_sid: PackedFloat32Array
var heat_ckps_per_sid: PackedFloat32Array

# 통계
var last_avg_delta_c := 0.0
var last_max_abs_delta_c := 0.0

# ─────────────────────────────────────────────────────────
# 한 틱 풀스캔(확산 + 발열):
# - phase_store: 전도 가능 여부 판정(기본: SOLID만 전달).
# - substance_store: sid → α/발열 룰 조회.
# - index: GridIndex
# - dt: float(초)
## 반환: 새로운 온도 배열
func tick_fullscan(
	T: PackedInt32Array, # 온도, 최초 온도 조회용.
	S: PackedInt32Array, # 물질 id, K와 C 조회용.
	M: PackedInt64Array, # 질량, 온도 변화량 계산용.
	index: GridIndex,
	dt: float
) -> PackedInt32Array:
	var w := index.size.x
	var h := index.size.y
	var n := w * h

	if T.size() != n or S.size() != n or M.size() != n:
		push_error("[TemperatureCore.tick_fullscan] Size mismatch")
		return PackedInt32Array() # TODO 에러 시 반환값 임시조치

	_ensure_capacity(n)

	var dQ := compute_deltaQ(w, h, n, T, S, M, k_per_sid, dt)
	if false: # 디버그
		print("[TemperatureCore] mean|dQ|=", _mean_abs(dQ))

	for i in n:
		heat_buffer[i] += dQ[i]

	var T_new := T.duplicate()

	var result := _apply_energy_to_temperature_no_latent(n, heat_buffer, T_new, S, M, c_per_sid)
	T_new = result["temperature"]
	heat_buffer = result["energy"]

	#var T_new := apply_deltaQ_to_T(n, T, S, M, c_per_sid, dQ)
	return T_new

## 타일별로 열량 변화량을 계산하고 결과를 PackedFloat64Array로 반환한다.
## 반환하는 열량값의 단위는 cJ(센티줄)이다.
static func compute_deltaQ(
	w: int, h: int, n: int,
	T: PackedInt32Array, S: PackedInt32Array, M:PackedInt64Array,
	K: Dictionary[int, float],
	dt: float
) -> PackedFloat64Array:
	var deltaQ := PackedFloat64Array()
	deltaQ.resize(n)
	for i in n: deltaQ[i] = 0.0

	for y in h:
		for x in w:
			var i := y * w + x

			var si := S[i]
			if si == 0: # VACCUM인 경우 스킵
				continue
			var Ti := float(T[i])
			var ki := float(K.get(si, 0.0))
			if ki <= 0.0:
				continue

			var sum_Q := 0.0
			for d in DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				# 경계 밖은 스킵 (clamp 금지)
				if nx < 0 or nx >= w or ny < 0 or ny >= h:
					continue
				var j := ny * w + nx

				var sj := S[j]
				if sj == 0: # VACCUM인 경우 스킵
					continue

				var kj := float(K[sj])
				# 유효 전도율: 조화평균
				var kij = _harmonic_mean(ki, kj)
				if kij <= 0.0:
					continue

				var Tj := float(T[j])

				var dq = kij * GEOM_ORTHO * (Tj - Ti) * dt

				# 저질량 선형 스로틀
				var mi := float(M[i])
				var mj := float(M[j])
				var min_m = min(mi, mj)
				var t = min(1.0, min_m / MIN_MASS_FOR_CONDUCTION) # [0,1]
				dq *= t

				sum_Q += dq

			# 이 셀에 들어온 열량(순합)
			deltaQ[i] += sum_Q
	return deltaQ

## deltaQ를 비열(cp)과 질량(m)으로 나눠 ΔT를 구하고,
## 기존 온도 배열(T_read)에 적용해 새로운 온도 배열을 반환한다.
static func apply_deltaQ_to_T(
	n: int,
	T: PackedInt32Array, S: PackedInt32Array, M: PackedInt64Array,
	C: Dictionary[int, float],
	deltaQ: PackedFloat64Array
) -> PackedInt32Array:
	var T_new := T.duplicate()

	for i in n:
		var si: int = S[i]
		if si == 0: # VACCUM인 경우 스킵
			continue

		var ci: float = float(C[si])
		if ci <= 0.0: # 비열이 없는 경우 스킵
			continue

		var mi := M[i]
		if mi <= 0: # 질량이 없는 경우 스킵
			continue

		# ΔT[cK] = ΔQ[cJ] / (mi[mg] * ci[cJ/mg·cK])
		var deltaT_cK := int(round(deltaQ[i] / (mi * ci)))

		T_new[i] += deltaT_cK

		if T_new[i] <= 0:
			push_error("[TemperatureCore] 비정상 온도. 셀 index: ", i, " 변화량: ", deltaT_cK, " 결과값: ", T_new[i])

	return T_new

# 에너지 버퍼(heat_buffer)에서 정수 cK만큼만 온도로 털고,
# 사용된 에너지만큼 heat_buffer에서 차감. 남은 소수 에너지는 다음 틱으로 이월.
static func _apply_energy_to_temperature_no_latent(
	n: int,
	E_cJ: PackedFloat64Array,
	T_ck: PackedInt32Array,
	S: PackedInt32Array,
	M_mg: PackedInt64Array,
	C_cJ_per_mg_cK: Dictionary[int, float]
) -> Dictionary:
	var E_new := E_cJ.duplicate()
	var T_new := T_ck.duplicate()

	for i in n:
		var sid: int = S[i]
		if sid == 0: # VACUUM
			continue

		var ci: float = float(C_cJ_per_mg_cK.get(sid, 0.0))
		if ci <= 0.0:
			continue

		var mi: int = M_mg[i]
		if mi <= 0:
			continue

		# 1 cK 올리는 데 필요한 에너지 [cJ]
		# (c_per_sid를 cJ/(mg·cK)로 세팅했으므로 단순 곱)
		var dE_per_cK: float = float(mi) * ci
		if dE_per_cK <= 0.0:
			continue

		# 이번 틱에 반영 가능한 cK의 '정수' 크기
		var dT_ck_f: float = E_cJ[i] / dE_per_cK
		var step_ck: int = int(floor(dT_ck_f)) if (dT_ck_f >= 0.0) else int(ceil(dT_ck_f))

		if step_ck != 0:
			T_new[i] += step_ck
			E_new[i] -= float(step_ck) * dE_per_cK

	return {
		"temperature": T_new,
		"energy": E_new
	}

# ─────────────────────────────────────────
# 유틸(단위 변환)
static func _c_to_ck(c: float) -> int:
	return int(round(c * 100.0 + TemperatureStore.CK_0C))

static func _ck_to_c(ck_delta: int) -> float:
	# 입력은 '차이' 사용이 많아서 0점(0K) 기준 델타로 처리
	return float(ck_delta) / 100.0

## a와 b의 조화평균을 출력한다.
static func _harmonic_mean(a: float, b: float) -> float:
	# a==0 or b==0이면 유효 전도율 0
	if a <= 0.0 or b <= 0.0:
		return 0.0
	return 2.0 / ((1.0 / a) + (1.0 / b))

static func _mean_abs(a: PackedFloat64Array) -> float:
	var s := 0.0
	for i in a.size(): s += absf(a[i])
	return s / a.size() if (a.size() > 0) else 0.0
