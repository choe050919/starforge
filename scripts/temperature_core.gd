## 순수 온도 로직만 담당.
extends RefCounted
class_name TemperatureCore
## - 저장은 TemperatureStore(cK, int32)를 사용
## - 읽기/쓰기 모두 인덱스 기반 I/O
## - 규칙(전도율/초기온도/발열)은 SID 테이블로 관리

# 외부 enum과 일치해야 함: SubstanceId Legacy !!!!!
const SID = { "VACUUM":0, "ICE":10001, "GROUND":10002, "URANIUM":10003, "WATER":20001 }

# 4방 탐색
const DIRS := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

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
# 규칙 셋업: 기본값 제공 (GROUND/ICE/URANIUM만 사용)
func setup_rules(
	alpha_ground := 0.9, alpha_ice := 0.4, alpha_uranium := 0.8, alpha_water := 0.6,
	c_ground := 1.0, c_ice := 0.8, c_uranium := 1.0, c_water := 4.18,
	uranium_power_c_per_s := 3.0 # °C/s → 내부에서 cK/s로 환산
) -> void:
	alpha_per_sid     = PackedFloat32Array([0, alpha_ice / max(0.0001, c_ice), alpha_ground / max(0.0001, c_ground), alpha_uranium / max(0.0001, c_uranium), alpha_water / max(0.0001, c_water)])
	heat_ckps_per_sid = PackedFloat32Array([0, 0, 0, uranium_power_c_per_s * 100.0, 0])

# ─────────────────────────────────────────────────────────
# 한 틱 풀스캔(확산 + 발열):
# - temp_store: TemperatureStore (cK). begin_write/commit은 내부에서 처리.
# - phase_store: 전도 가능 여부 판정(기본: SOLID만 전달).
# - substance_store: sid → α/발열 룰 조회.
# - index: GridIndex
# - dt: float(초)
# 반환: 간단 통계(평균 ΔT, 최대 |ΔT| in °C)
func tick_fullscan(
	temp_store: TemperatureStore,
	substance_store: SubstanceStore,
	mass_store: MassStore,
	index: GridIndex,
	dt: float
) -> Dictionary:
	var w := index.size.x
	var h := index.size.y
	var n := w * h

	var T := temp_store.get_raw_read()
	var S := substance_store.get_raw_read()
	var M := mass_store.get_raw_read()
	var K # TODO

	if T.size() != n or S.size() != n:
		push_error("[TemperatureCore.tick_fullscan] Size mismatch")
		return {} # TODO 에러 시 반환값 임시조치

	var deltaQ := compute_deltaQ(w, h, n, T, S, K, dt)

	#apply_deltaQ_to_T()

	return {}

"""

	#if n <= 0 or dt <= 0.0:
		#last_avg_delta_c = 0.0
		#last_max_abs_delta_c = 0.0
		#return { "avg_delta_c": 0.0, "max_abs_delta_c": 0.0 }

	#temp_store.begin_write()

	var sum_delta_c := 0.0
	var max_abs_delta_c := 0.0

	for y in h:
		for x in w:
			var i := y * w + x
			var ph: int = phase_store.get_by_index(i)
			if ph == PhaseStore.Phase.VACUUM:
				continue # VACCUM 상태는 무시

			var sid: int = substance_store.get_by_index(i)
			var alpha := alpha_per_sid[sid]

			# 중심 및 이웃 읽기(모두 SOLID만 전달)
			var t_center_ck := float(temp_store.get_by_index(i))
			var sum_n_ck := 0.0
			var cnt := 0

			for d in DIRS:
				var nx := clampi(x + d.x, 0, w - 1)
				var ny := clampi(y + d.y, 0, h - 1)
				var j := ny * w + nx
				if phase_store.get_by_index(j) != PhaseStore.Phase.VACUUM:
					sum_n_ck += float(temp_store.get_by_index(j))
					cnt += 1

			var t_new_ck := t_center_ck
			if cnt > 0:
				var avg_n_ck := sum_n_ck / float(cnt)
				var blend := clampf(dt * alpha * float(cnt), 0.0, 1.0)
				t_new_ck = lerpf(t_center_ck, avg_n_ck, blend)

			# 발열 적용(동일 틱 내에 합산)
			var heat_ck := heat_ckps_per_sid[sid] * dt
			if heat_ck != 0.0:
				t_new_ck += heat_ck

			# 기록 및 통계(°C 기준)
			temp_store.set_by_index(i, int(round(t_new_ck)))
			var delta_c := _ck_to_c(int(round(t_new_ck)) - int(t_center_ck))
			sum_delta_c += delta_c
			var absd := absf(delta_c)
			if absd > max_abs_delta_c:
				max_abs_delta_c = absd


	#temp_store.commit()

	last_avg_delta_c = sum_delta_c / float(n)
	last_max_abs_delta_c = max_abs_delta_c
	return { "avg_delta_c": last_avg_delta_c, "max_abs_delta_c": last_max_abs_delta_c }

"""

## 타일별로 열량 변화량을 계산하고 결과를 PackedFloat64Array로 반환한다.
static func compute_deltaQ(
	w: int, h: int, n: int,
	T: PackedInt32Array, S: PackedInt32Array, K,
	dt: float
) -> PackedFloat64Array:

	var deltaQ := PackedFloat64Array()
	deltaQ.resize(n)
	for i in n: deltaQ[i] = 0.0

	for y in h:
		for x in w:
			var i := y * w + x

			var si := S[i]
			if si == 0: # VACCUM일시 스킵
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
				if sj == 0: # VACCUM일시 스킵
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

static func apply_deltaQ_to_T(
	w: int, h: int, n: int,
	T: PackedInt32Array, S: PackedInt32Array, K,

	temp: TemperatureStore,
	substance: SubstanceStore,
	mass: MassStore,
	phase: PhaseStore,

	deltaQ: PackedFloat64Array
):
	pass

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
