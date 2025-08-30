## 순수 상전이 로직만 담당.
extends RefCounted
class_name PhaseChangeCore

# ─────────────────────────────────────────────────────────
# 외부 enum과 일치해야 함 (프로젝트 기준)
# Phase: 0=VACUUM, 1=SOLID, 2=LIQUID, 3=GAS
const PH = { "VACUUM":0, "SOLID":1, "LIQUID":2, "GAS":3 }
# SubstanceId: 0=VACUUM, 1=ICE, 2=GROUND, 3=URANIUM, 4=WATER
const SID = { "VACUUM":0, "ICE":1, "GROUND":2, "URANIUM":3, "WATER":4 }

# ─────────────────────────────────────────────────────────
# 임계값 테이블 (sid 인덱스 접근)
# 방향성 규칙:
#  - 융해(melt_up): SOLID→LIQUID는  T >= melt_up[sid]
#  - 응고(freeze_down): LIQUID→SOLID는 T <= freeze_down[sid]
#  - (지금은 ICE/WATER만 사용. 나머지는 불가능값으로 차단)
var melt_up: PackedInt32Array
var freeze_down: PackedInt32Array

# 선택: 전이 카운터(틱 통계)
var last_tick_transitions_ice_to_water := 0
var last_tick_transitions_water_to_ice := 0

# ─────────────────────────────────────────────────────────
# 규칙 셋업: 히스테리시스 포함
func setup_rules(
	hyst_c := 1,   # ICE/WATER 공용 히스테리시스 폭
	melt_c := 27315,   # 얼음(고체)의 융해 기준 온도(상향 문턱의 중심)
	freeze_c := 27314 # 물(액체)의 응고 기준 온도(하향 문턱의 중심)
	) -> void:
	# sid 최대치 고려해 배열 준비(간단히 5칸)
	melt_up = PackedInt32Array([0, 0, 0, 0, 0])
	freeze_down = PackedInt32Array([0, 0, 0, 0, 0])

	# 불가능값(충분히 큰 1000000000)로 초기화
	for i in melt_up.size():
		melt_up[i] = 1000000000
		freeze_down[i] = -1000000000

	# ICE(고체 물): SOLID→LIQUID를 허용 (WATER로 물질 전환 예정)
	# 히스테리시스: 상향 문턱을 melt_c + (hyst)로 잡고, 하향 문턱은 WATER 쪽에 둔다.
	melt_up[SID.ICE] = melt_c + hyst_c

	# WATER(액체 물): LIQUID→SOLID를 허용 (ICE로 물질 전환 예정)
	freeze_down[SID.WATER] = freeze_c - hyst_c

	# GROUND/URANIUM: 불가능값 유지 → 상전이 차단
	# (명시적 주석으로 의도 남김)
	# melt_up[SID.GROUND]  = 1e9
	# freeze_down[SID.GROUND] = -1e9
	# melt_up[SID.URANIUM] = 1e9
	# freeze_down[SID.URANIUM] = -1e9

	# 기본 통계 리셋
	last_tick_transitions_ice_to_water = 0
	last_tick_transitions_water_to_ice = 0

# ─────────────────────────────────────────────────────────
# 풀 스캔 실행:
# - phase_store: get_phase_i(i), set_phase_i(i), begin_write(), commit()
# - substance_store: get_sid_i(i), set_sid_i(i), begin_write(), commit()
# - temperature: get_celsius_i(i) !!!!!!!!!!!!
# - index: GridIndex(size)
func tick_fullscan(phase_store, substance_store, temperature_store, index) -> Dictionary:
	var n = index.size.x * index.size.y
	var ice_to_water := 0
	var water_to_ice := 0

	phase_store.begin_write()
	substance_store.begin_write()

	for i in n:
		var sid = substance_store.get_by_index(i)
		var ph = phase_store.get_by_index(i)

		# 빠른 배제: 현재 phase별로 단일 비교만 수행
		if ph == PH.SOLID:
			# 고체가 액체로 융해 가능한지(ICE만 실질적으로 허용)
			var t = temperature_store.get_by_index(i)
			if t >= melt_up[sid]:
				# ICE → WATER 로 substance 전환 + phase LIQUID
				if sid == SID.ICE:
					substance_store.set_by_index(i, SID.WATER)
					phase_store.set_by_index(i, PH.LIQUID)
					ice_to_water += 1
				# (다른 sid는 melt_up가 불가능값이라 도달 불가)
		elif ph == PH.LIQUID:
			# 액체가 고체로 응고 가능한지(WATER만 실질적으로 허용)
			var t2 = temperature_store.get_by_index(i)
			if t2 <= freeze_down[sid]:
				if sid == SID.WATER:
					substance_store.set_by_index(i, SID.ICE)
					phase_store.set_by_index(i, PH.SOLID)
					water_to_ice += 1
		else:
			# VACUUM/GAS 단계는 현재 상전이 없음(무시)
			pass

	substance_store.commit()
	phase_store.commit()

	last_tick_transitions_ice_to_water = ice_to_water
	last_tick_transitions_water_to_ice = water_to_ice
	return {
		"ice_to_water": ice_to_water,
		"water_to_ice": water_to_ice,
		"total": ice_to_water + water_to_ice
	}
