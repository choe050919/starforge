## 순수 온도 로직 담당
##
## 열전도 시뮬레이션의 핵심 계산을 수행합니다.
## - 타일 간 열 확산 계산 (compute_deltaQ)
## - 열량을 온도로 변환 (heat_buffer 사용)
## - 소수점 에너지 이월로 정밀도 유지
##
## 저장소: TemperatureStore (단위: cK, int32)
extends RefCounted
class_name TemperatureCore

# ═══════════════════════════════════════════════════════════
# 상수
# ═══════════════════════════════════════════════════════════

## 타일 한 변의 길이 (m)
const TILE_LENGTH_M := 0.1

## 열전도 기하학 계수 (A/d = L)
const GEOMETRY_FACTOR := TILE_LENGTH_M

## 저질량 타일의 열전도 스로틀링 기준값 (mg)
const MIN_MASS_FOR_CONDUCTION := 10_000

## 4방향 탐색 벡터
const DIRS := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

# ═══════════════════════════════════════════════════════════
# 내부 타입
# ═══════════════════════════════════════════════════════════

## 열 적용 결과를 담는 컨테이너
class HeatApplicationResult:
	var temperature: PackedInt32Array ## 갱신된 온도 배열 (cK)
	var heat_buffer: PackedFloat64Array ## 남은 열량 버퍼 (cJ)
	
	func _init(t: PackedInt32Array, h: PackedFloat64Array):
		temperature = t
		heat_buffer = h

# ═══════════════════════════════════════════════════════════
# 상태
# ═══════════════════════════════════════════════════════════

## 타일별 미반영 열량 누적 버퍼 (cJ)
## 정수 온도 변화로 소비되지 못한 에너지를 다음 틱으로 이월
var heat_buffer: PackedFloat64Array = PackedFloat64Array()

## 물질별 열전도율 (W/m·K)
var k_by_sid: Dictionary[int, float]

## 물질별 비열 (cJ/mg·cK)
var c_by_sid: Dictionary[int, float]

# 미사용 (TODO: 제거 검토)
var last_avg_delta_c := 0.0
var last_max_abs_delta_c := 0.0

# ═══════════════════════════════════════════════════════════
# 초기화
# ═══════════════════════════════════════════════════════════

## 물질 캐시로부터 열적 속성 로드
func setup_thermal_from_cache(cache: SubstanceRuleCache) -> void:
	k_by_sid.clear()
	c_by_sid.clear()

	var loaded_count := 0
	for sid in cache.phase_of_sid.keys():
		var k_si := float(cache.k_by_sid.get(sid, 0.0)) # [W/m·K]
		var c_si := float(cache.c_by_sid.get(sid, 0.0)) # [J/kg·K]

		# 모든 sid를 등록 (0.0도 유효한 값 - 열전도 없음을 의미)
		k_by_sid[sid] = k_si
		c_by_sid[sid] = c_si * 1e-6 # 1mg을 1cK 변화시키는 데 필요한 열량(cJ)
		
		if k_si > 0.0 or c_si > 0.0:
			loaded_count += 1

	print("[TemperatureCore] Loaded thermal data for %d/%d substances (with properties)" 
		% [loaded_count, k_by_sid.size()])
	
	if k_by_sid.is_empty():
		push_warning("[TemperatureCore] No thermal data loaded! Check substance cache")
	
	# 샘플 출력
	if false:
		print("[TemperatureCore] Sample ICE: c=%.6f k=%.2f" 
			% [c_by_sid.get(10001, -999.0), k_by_sid.get(10001, -999.0)])

## heat_buffer 크기를 n으로 조정
func _ensure_capacity(n: int) -> void:
	if heat_buffer.size() != n:
		heat_buffer.resize(n)
		for i in n:
			heat_buffer[i] = 0.0

# ═══════════════════════════════════════════════════════════
# 메인 시뮬레이션 루프
# ═══════════════════════════════════════════════════════════

## 한 틱의 열전도 시뮬레이션 수행
##
## 타일 간 열 확산을 계산하고, heat_buffer에 누적된 열량을
## 정수 온도로 변환합니다. 소수점 에너지는 다음 틱으로 이월됩니다.
##
## T: 현재 온도 (cK)
## S: 물질 ID
## M: 질량 (mg)
## index: 그리드 인덱스
## dt: 시간 간격 (초)
##
## 반환: 갱신된 온도 배열 (cK)
func tick_fullscan(
	T: PackedInt32Array,
	S: PackedInt32Array,
	M: PackedInt64Array,
	index: GridIndex,
	dt: float,
	flows: Array = []
) -> PackedInt32Array:
	var w := index.size.x
	var h := index.size.y
	var n := w * h

	if T.size() != n or S.size() != n or M.size() != n:
		push_error("[TemperatureCore.tick_fullscan] Size mismatch")
		return PackedInt32Array()

	_ensure_capacity(n)

	var dQ_conduction := compute_deltaQ(w, h, n, T, S, M, k_by_sid, dt)
	if false: # 디버그
		print("[TemperatureCore] mean|dQ|=", _mean_abs(dQ_conduction ))

	var dQ_advection = _compute_advective_heat(flows, T, S, c_by_sid)

	for i in n:
		heat_buffer[i] += dQ_conduction[i] + dQ_advection[i]

	var result := _consume_heat_buffer(n, heat_buffer, T, S, M, c_by_sid)

	heat_buffer = result.heat_buffer
	return result.temperature

# ═══════════════════════════════════════════════════════════
# 핵심 계산 (순수 함수)
# ═══════════════════════════════════════════════════════════

## 타일별 열량 변화 계산
##
## 4방향 이웃과의 열전도를 계산하여 각 타일이 얻거나 잃는 열량을 반환합니다.
## 저질량 타일은 열전도가 스로틀링됩니다.
##
## 최적화: 오른쪽(→)과 아래(↓) 방향만 탐색하여 중복 계산을 방지합니다.
## 각 셀 쌍 (i, j)에 대해 열류를 한 번만 계산하고 양쪽에 동시 반영합니다.
## 예: i→j 열류가 +10이면, deltaQ[i]+=10, deltaQ[j]-=10 (에너지 보존)
## 이를 통해 연산량을 약 50% 감소시킵니다.
static func compute_deltaQ(
	w: int, h: int, n: int,
	T: PackedInt32Array, # 온도 (cK)
	S: PackedInt32Array, # 물질 ID
	M: PackedInt64Array, # 질량 (mg)
	K: Dictionary[int, float], # 물질별 열전도율
	dt: float
) -> PackedFloat64Array: # 타일별 열량 변화 (cJ)
	var deltaQ := PackedFloat64Array()
	deltaQ.resize(n)
	for i in n: deltaQ[i] = 0.0

	# 오른쪽(→), 아래(↓) 방향만 탐색 (중복 계산 방지)
	# 왼쪽(←), 위(↑)는 이미 반대편 셀에서 처리됨
	const HALF_DIRS := [Vector2i(1, 0), Vector2i(0, 1)]

	for y in h:
		for x in w:
			var i := y * w + x

			var si := S[i]
			if si == 0: # VACUUM인 경우 스킵
				continue
			var Ti := float(T[i])
			var ki := float(K.get(si, 0.0))
			if ki <= 0.0:
				continue

			var mi := float(M[i])

			# 오른쪽과 아래 이웃만 검사
			for d in HALF_DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				
				# 경계 밖은 스킵 (오른쪽/아래만 체크하므로 상한만 검사)
				if nx >= w or ny >= h:
					continue
				
				var j := ny * w + nx

				var sj := S[j]
				if sj == 0: # VACUUM인 경우 스킵
					continue

				var kj := float(K[sj])
				# 유효 전도율: 조화평균
				var kij = _harmonic_mean(ki, kj)
				if kij <= 0.0:
					continue

				var Tj := float(T[j])

				# i→j 열류 계산 (푸리에 법칙: Q = k·A/d·ΔT·dt)
				var dq = kij * GEOMETRY_FACTOR * (Tj - Ti) * dt

				# 저질량 선형 스로틀 (10g 미만 셀은 열전도 감소)
				var mj := float(M[j])
				var min_m = min(mi, mj)
				var t = min(1.0, min_m / MIN_MASS_FOR_CONDUCTION) # [0,1]
				dq *= t

				# 양쪽 셀에 동시 반영 (에너지 보존 법칙)
				# i는 dq만큼 열을 얻고, j는 dq만큼 열을 잃음
				deltaQ[i] += dq
				deltaQ[j] -= dq

	return deltaQ

## heat_buffer를 소비해 온도로 변환
##
## 정수 cK 변화에 필요한 에너지만큼 버퍼에서 차감합니다.
## 남은 소수점 에너지는 다음 틱으로 이월됩니다.
static func _consume_heat_buffer(
	n: int,
	E_cJ: PackedFloat64Array, # 열량 버퍼 (cJ)
	T_ck: PackedInt32Array, # 현재 온도 (cK)
	S: PackedInt32Array, # 물질 ID
	M_mg: PackedInt64Array, # 질량 (mg)
	C_cJ_per_mg_cK: Dictionary[int, float] # 물질별 비열
) -> HeatApplicationResult: # 갱신된 온도와 남은 열량
	var heat_new := E_cJ.duplicate()
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
		# (c_by_sid를 cJ/(mg·cK)로 세팅했으므로 단순 곱)
		var dE_per_cK: float = float(mi) * ci
		if dE_per_cK <= 0.0:
			continue

		# 이번 틱에 반영 가능한 cK의 '정수' 크기
		var dT_ck_f: float = heat_new[i] / dE_per_cK
		var step_ck: int = int(floor(dT_ck_f)) if (dT_ck_f >= 0.0) else int(ceil(dT_ck_f))

		if step_ck != 0:
			T_new[i] += step_ck
			heat_new[i] -= float(step_ck) * dE_per_cK

	return HeatApplicationResult.new(T_new, heat_new)

## 질량 이동에 따른 열 운반 계산
##
## 물리 원리:
## 질량이 이동할 때 그 질량의 열도 함께 이동
## ΔQ = Δm × c × T
##
## flows: Liquid가 계산한 질량 이동 정보
## T: 현재 온도 [cK]
## S: 물질 ID
## C: 물질별 비열 [cJ/(mg·cK)]
##
## 반환: 각 셀의 열량 변화 [cJ]
static func _compute_advective_heat(
	flows: Array,
	T: PackedInt32Array,
	S: PackedInt32Array,
	C: Dictionary[int, float]
) -> PackedFloat64Array:
	var n := T.size()
	var dQ := PackedFloat64Array()
	dQ.resize(n)
	for i in n:
		dQ[i] = 0.0
	
	# flows가 비어있으면 (액체 이동 없음)
	if flows.is_empty():
		return dQ
	
	# 각 flow에 대해 열 이동 계산
	for flow in flows:
		var from_i: int = flow.from
		var to_i: int = flow.to
		var amount: int = flow.amount  # mg
		var temp: int = flow.temp      # cK (출발지 온도)
		
		var sid := S[from_i]
		var c: float = C.get(sid, 0.0)  # cJ/(mg·cK)
		
		if c <= 0.0:
			continue
		
		# 이동하는 질량이 운반하는 열량 [cJ]
		# Q = m × c × T
		var heat_carried := float(amount) * c * float(temp)
		
		# 출발지: 열 손실
		dQ[from_i] -= heat_carried
		
		# 도착지: 열 획득
		dQ[to_i] += heat_carried
	
	return dQ

# ═══════════════════════════════════════════════════════════
# 유틸리티
# ═══════════════════════════════════════════════════════════

## 섭씨 → 센티켈빈 변환
static func _c_to_ck(c: float) -> int:
	return int(round(c * 100.0 + TemperatureStore.CK_0C))

## 센티켈빈 → 섭씨 변환 (델타값)
static func _ck_to_c(ck_delta: int) -> float:
	return float(ck_delta) / 100.0

## 조화평균 계산
static func _harmonic_mean(a: float, b: float) -> float:
	if a <= 0.0 or b <= 0.0:
		return 0.0
	return 2.0 / ((1.0 / a) + (1.0 / b))

## 배열 절댓값의 평균
static func _mean_abs(a: PackedFloat64Array) -> float:
	var s := 0.0
	for i in a.size(): 
		s += absf(a[i])
	return s / a.size() if a.size() > 0 else 0.0
