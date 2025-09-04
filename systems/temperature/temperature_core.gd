## 순수 온도 로직만 담당.
## - 저장은 TemperatureStore(cK, int32)를 사용
extends RefCounted
class_name TemperatureCore

# 4방 탐색
const DIRS := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]


var k_per_sid: PackedFloat64Array # 내부용: k_eff (이미 보정된 값)
var c_per_sid: PackedFloat64Array # 내부용: SI 그 자체

# cache의 SI 테이블을, 내부에서 쓰기 좋은 테이블로 1회 변환
func setup_thermal_from_cache(cache: SubstanceRuleCache) -> void:
	# sid 최대치 찾기
	var max_sid := 0
	for sid in cache.phase_of_sid.keys():
		if sid > max_sid: max_sid = sid

	k_per_sid = PackedFloat64Array(); k_per_sid.resize(max_sid + 1)
	c_per_sid = PackedFloat64Array(); c_per_sid.resize(max_sid + 1)

	for i in max_sid + 1:
		k_per_sid[i] = 0.0
		c_per_sid[i] = 0.0

	# k_eff = k_SI * 0.01 * (A/L)
	for sid in cache.phase_of_sid.keys():
		var k_si := float(cache.k_by_sid.get(sid, 0.0)) # [W/m·K]
		var c_si := float(cache.c_by_sid.get(sid, 0.0)) # [J/kg·K]
		k_per_sid[sid] = k_si # * 0.01 TODO ?? # ΔT[cK]와 곱해도 J 나오도록 보정
		c_per_sid[sid] = c_si        # apply_deltaQ_to_T는 SI 그대로 사용

	if false: # 디버그
		print("[Thermal] sample: ICE c=", c_per_sid.get(10001), " k_eff=", k_per_sid.get(10001))
		print("[Thermal] sample: WATER c=", c_per_sid.get(20001), " k_eff=", k_per_sid.get(20001))


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
# - temp_store: TemperatureStore (cK). begin_write/commit은 내부에서 처리.
# - phase_store: 전도 가능 여부 판정(기본: SOLID만 전달).
# - substance_store: sid → α/발열 룰 조회.
# - index: GridIndex
# - dt: float(초)
## 반환: 새로운 온도 배열
func tick_fullscan(
	temp_store: TemperatureStore,
	substance_store: SubstanceStore,
	mass_store: MassStore,
	index: GridIndex,
	dt: float
) -> PackedInt32Array:
	var w := index.size.x
	var h := index.size.y
	var n := w * h

	var T := temp_store.get_raw_read()      # 온도, 최초 온도 조회용. 주의!! 여기서는 값을 수정하지 않음.
	var S := substance_store.get_raw_read() # 물질 id, K와 C 조회용.
	var M := mass_store.get_raw_read()      # 질량, 온도 변화량 계산용.
	# K: S값에 따른 열전도율, 열량 이동량 계산의 계수
	# C: S값에 따른 비열, 온도 변화량 계산의 계수

	if T.size() != n or S.size() != n or M.size() != n:
		push_error("[TemperatureCore.tick_fullscan] Size mismatch")
		return PackedInt32Array() # TODO 에러 시 반환값 임시조치

	var dQ := compute_deltaQ(w, h, n, T, S, k_per_sid, dt)
	if true: # 디버그
		print("[Temp] dt=", dt)
		print("[Temp] mean|dQ|=", _mean_abs(dQ))
		print("[Temp] sample ΔT_cK≈", int(round(dQ[0] * 1e8 / max(1.0, float(M[0]) * max(1.0, c_per_sid[S[0]])))))
	var T_new := apply_deltaQ_to_T(n, T, S, M, c_per_sid, dQ)
	return T_new

## 타일별로 열량 변화량을 계산하고 결과를 PackedFloat64Array로 반환한다.
static func compute_deltaQ(
	w: int, h: int, n: int,
	T: PackedInt32Array, S: PackedInt32Array,
	K,
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
			var ki := float(K[si])

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
				sum_Q += kij * (Tj - Ti) * dt
			# 이 셀에 들어온 열량(순합)
			deltaQ[i] += sum_Q
	return deltaQ

## deltaQ를 비열(cp)과 질량(m)으로 나눠 ΔT를 구하고,
## 기존 온도 배열(T_read)에 적용해 새로운 온도 배열을 반환한다.
static func apply_deltaQ_to_T(
	n: int,
	T: PackedInt32Array, S: PackedInt32Array, M: PackedInt64Array,
	C: PackedFloat64Array,
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

		# ΔT[cK] = ΔQ * 1e8 / (mi[mg] * ci[J/kg·K])
		var deltaT_cK := int(round(deltaQ[i] * 1e8 / (mi * ci)))

		T_new[i] += deltaT_cK

	return T_new

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
