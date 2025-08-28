extends RefCounted
class_name TemperatureCore
## 순수 온도 로직만 담당. 씬 트리와 무관.
## - 저장은 TemperatureStore(cK, int32)를 사용
## - 읽기/쓰기 모두 인덱스 기반 I/O
## - 규칙(전도율/초기온도/발열)은 SID 테이블로 관리

# 외부 enum과 일치해야 함: SubstanceId
const SID = { "VACUUM":0, "ICE":1, "GROUND":2, "URANIUM":3, "WATER":4 }

# 4방 탐색
const DIRS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

# ─────────────────────────────────────────────────────────
# 규칙 테이블 (sid 인덱스 접근)
# alpha_per_sid: α = k/c (무차원, 상대값). 확산 블렌딩에 사용.
# init_c_per_sid: 초기 온도(°C)
# heat_ckps_per_sid: 발열( cK/s )
var alpha_per_sid: PackedFloat32Array
var init_c_per_sid: PackedFloat32Array
var heat_ckps_per_sid: PackedFloat32Array

# 통계
var last_avg_delta_c := 0.0
var last_max_abs_delta_c := 0.0

# ─────────────────────────────────────────────────────────
# 규칙 셋업: 기본값 제공 (GROUND/ICE/URANIUM만 사용)
func setup_rules(
	alpha_ground := 0.9, alpha_ice := 0.4, alpha_uranium := 0.8,
	c_ground := 1.0, c_ice := 0.8, c_uranium := 1.0,
	t_ground_init_c := 12.0, t_ice_init_c := -5.0, t_uranium_init_c := 12.0,
	uranium_power_c_per_s := 3.0 # °C/s → 내부에서 cK/s로 환산
) -> void:
	alpha_per_sid     = PackedFloat32Array([0, alpha_ice / max(0.0001, c_ice), alpha_ground / max(0.0001, c_ground), alpha_uranium / max(0.0001, c_uranium), 0])
	init_c_per_sid    = PackedFloat32Array([0, t_ice_init_c, t_ground_init_c, t_uranium_init_c, 0])
	heat_ckps_per_sid = PackedFloat32Array([0, 0, 0, uranium_power_c_per_s * 100.0, 0])

# ─────────────────────────────────────────────────────────
# 초기 온도 세팅:
# - temp_store: TemperatureStore (cK)
# - substance_store: sid 조회에 사용
# - index: GridIndex(size)
# - overwrite_if_zero: true면 0K(미사용값)에만 초기값 기입
func initialize_from_substances(temp_store, substance_store, index, overwrite_if_zero := true) -> void:
	var n: int = index.size.x * index.size.y
	temp_store.begin_write()
	for i in n:
		var sid: int = substance_store.get_by_index(i)
		var tgt_ck := _c_to_ck(init_c_per_sid[sid])
		if overwrite_if_zero:
			if temp_store.get_by_index(i) == 0:
				temp_store.set_by_index(i, tgt_ck)
		else:
			temp_store.set_by_index(i, tgt_ck)
	temp_store.commit()

# ─────────────────────────────────────────────────────────
# 한 틱 풀스캔(확산 + 발열):
# - temp_store: TemperatureStore (cK). begin_write/commit은 내부에서 처리.
# - phase_store: 전도 가능 여부 판정(기본: SOLID만 전달).
# - substance_store: sid → α/발열 룰 조회.
# - index: GridIndex
# - dt: float(초)
# 반환: 간단 통계(평균 ΔT, 최대 |ΔT| in °C)
func tick_fullscan(temp_store, phase_store, substance_store, index, dt: float) -> Dictionary:
	var n: int = index.size.x * index.size.y
	if n <= 0 or dt <= 0.0:
		last_avg_delta_c = 0.0
		last_max_abs_delta_c = 0.0
		return { "avg_delta_c": 0.0, "max_abs_delta_c": 0.0 }

	temp_store.begin_write()

	var w: int= index.size.x
	var h: int = index.size.y
	var sum_delta_c := 0.0
	var max_abs_delta_c := 0.0

	for y in h:
		for x in w:
			var i := y * w + x
			var ph: int = phase_store.get_by_index(i)
			if ph != PhaseStore.Phase.SOLID:
				# 전달 비활성: 그대로 유지
				var t_keep: int = temp_store.get_by_index(i) # read
				temp_store.set_by_index(i, t_keep)       # write
				continue

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
				if phase_store.get_by_index(j) == PhaseStore.Phase.SOLID:
					sum_n_ck += float(temp_store.get_by_index(j))
					cnt += 1

			var t_new_ck := t_center_ck
			if cnt > 0 and alpha > 0.0:
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

	temp_store.commit()

	last_avg_delta_c = sum_delta_c / float(n)
	last_max_abs_delta_c = max_abs_delta_c
	return { "avg_delta_c": last_avg_delta_c, "max_abs_delta_c": last_max_abs_delta_c }

# ─────────────────────────────────────────
# 유틸(단위 변환)
static func _c_to_ck(c: float) -> int:
	return int(round(c * 100.0 + TemperatureStore.CK_0C))

static func _ck_to_c(ck_delta: int) -> float:
	# 입력은 '차이' 사용이 많아서 0점(0K) 기준 델타로 처리
	return float(ck_delta) / 100.0
