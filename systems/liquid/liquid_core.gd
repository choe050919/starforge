## 압력 구배 기반 액체 유동 시뮬레이터
##
## 물리 모델:
## - 정수압 근사 (Hydrostatic approximation): P = ρgh
## - 밀도-온도 관계 (Thermal expansion): ρ(T) = ρ₀(1 - β·ΔT)
## - 유동 법칙: flow ∝ ∇P (압력 구배에 비례)
##
## 통일된 원리:
## 모든 유동(중력, 확산, 부력)은 압력 불균형 해소로 설명됨
##
## 입력:
## - mass: 직접적으로 압력 결정
## - temp: 밀도 변화를 통해 압력 영향
##
## 출력:
## - flows: 압력 구배가 만드는 질량 이동
extends RefCounted
class_name LiquidCore

# ═══════════════════════════════════════════════════════════
# 물리 상수
# ═══════════════════════════════════════════════════════════

## 중력 가속도 [m/s²]
const GRAVITY := 9.8

## 타일 한 변 길이 [m]
const TILE_LENGTH := 0.1

## 타일 부피 [m³]
const TILE_VOLUME := TILE_LENGTH * TILE_LENGTH * TILE_LENGTH

## 기준 온도 [cK] (20°C)
const REFERENCE_TEMP := 29315

## 물의 열팽창 계수 [1/K] (임시값, 추후 substance에서 로드)
const WATER_THERMAL_EXPANSION := 2.07e-4

## 최소 압력 차이 임계값 [Pa]
## 이보다 작은 압력차는 무시 (수치 안정성)
const MIN_PRESSURE_DIFF := 1.0

# ═══════════════════════════════════════════════════════════
# 상수
# ═══════════════════════════════════════════════════════════

const PH_VACUUM := 0
const PH_SOLID  := 1
const PH_LIQUID := 2

# ═══════════════════════════════════════════════════════════
# 내부 타입
# ═══════════════════════════════════════════════════════════

class Flow:
	var from: int
	var to: int
	var amount: int  # mg
	var temp: int    # cK
	
	func _init(f: int, t: int, a: int, T: int):
		from = f
		to = t
		amount = a
		temp = T

# ═══════════════════════════════════════════════════════════
# 메인 시뮬레이션
# ═══════════════════════════════════════════════════════════

## 한 틱의 압력 기반 유동 계산
##
## 알고리즘:
## 1. 각 셀의 압력 계산 (질량, 온도, 높이 고려)
## 2. 인접 셀 간 압력 구배 계산
## 3. 압력 구배 → 유량 결정 (용량 제한 고려)
##
## 반환: Array[Flow]
func compute_diff(
	phase: PackedByteArray,
	mass: PackedInt64Array,
	temp: PackedInt32Array,
	index: GridIndex,
	capacity: int,  # mg
	dt: float
) -> Array[Flow]:
	var w := index.size.x
	var h := index.size.y
	var n := w * h
	
	if phase.size() != n or mass.size() != n or temp.size() != n:
		push_error("[LiquidCore] Size mismatch")
		return []
	
	# 1. 압력 계산
	var pressure := _compute_pressure_field(mass, temp, phase, w, h)
	
	# 2. 용량 계산
	var free := _compute_free_space(phase, mass, capacity, n)
	
	# 3. 압력 구배 → 유동
	var flows: Array[Flow] = []
	_compute_flows_from_pressure(
		flows, pressure, free,
		phase, mass, temp,
		w, h, dt
	)
	
	return flows

# ═══════════════════════════════════════════════════════════
# 핵심 계산 (순수 함수)
# ═══════════════════════════════════════════════════════════

## 압력장 계산
##
## 각 셀의 압력을 계산합니다.
## P = ρgh (정수압 근사)
## 여기서 ρ = ρ(mass, temp) (열팽창 고려)
static func _compute_pressure_field(
	mass: PackedInt64Array,
	temp: PackedInt32Array,
	phase: PackedByteArray,
	w: int, h: int
) -> PackedFloat64Array:
	var n := w * h
	var P := PackedFloat64Array()
	P.resize(n)
	
	for y in h:
		for x in w:
			var i := y * w + x
			
			if phase[i] != PH_LIQUID or mass[i] <= 0:
				P[i] = 0.0
				continue
			
			# 밀도 계산 [kg/m³]
			var rho := _compute_density(mass[i], temp[i])
			
			# 높이 (바닥부터의 거리) [m]
			# y=0이 위, y=h-1이 아래이므로 (h-1-y)
			var height := float(h - 1 - y) * TILE_LENGTH
			
			# 압력 = ρgh [Pa = kg/(m·s²)]
			P[i] = rho * GRAVITY * height
	
	return P

## 밀도 계산 (온도 의존)
##
## ρ(T) = ρ₀(1 - β·ΔT)
## 
## mass: 질량 [mg]
## temp: 온도 [cK]
## 반환: 밀도 [kg/m³]
static func _compute_density(mass: int, temp: int) -> float:
	# 기준 밀도 [kg/m³]
	var mass_kg := float(mass) * 1e-6  # mg → kg
	var rho_base := mass_kg / TILE_VOLUME
	
	# 온도 보정
	var T_delta := float(temp - REFERENCE_TEMP) / 100.0  # cK → K
	var thermal_factor := 1.0 - WATER_THERMAL_EXPANSION * T_delta
	
	return rho_base * thermal_factor

## 여유 공간 계산
static func _compute_free_space(
	phase: PackedByteArray,
	mass: PackedInt64Array,
	capacity: int,
	n: int
) -> PackedInt64Array:
	var free := PackedInt64Array()
	free.resize(n)
	
	for i in n:
		if phase[i] == PH_SOLID:
			free[i] = 0
		else:
			var liquid_mass := mass[i] if phase[i] == PH_LIQUID else 0
			free[i] = capacity - liquid_mass
	
	return free

## 압력 구배로부터 유동 계산
##
## 4방향 인접 셀을 검사하여 압력 차이가 있으면 유동 생성
static func _compute_flows_from_pressure(
	flows: Array[Flow],
	pressure: PackedFloat64Array,
	free: PackedInt64Array,
	phase: PackedByteArray,
	mass: PackedInt64Array,
	temp: PackedInt32Array,
	w: int, h: int,
	dt: float
) -> void:
	# ✅ 수정: 4방향 전부 검사
	const ALL_DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	
	for y in h:
		for x in w:
			var i := y * w + x
			
			if phase[i] != PH_LIQUID or mass[i] <= 0:
				continue
			
			var Pi := pressure[i]
			
			for d in ALL_DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				
				# ✅ 수정: 경계 체크 (음수 포함)
				if nx < 0 or nx >= w or ny < 0 or ny >= h:
					continue
				
				var j := ny * w + nx
				
				# 고체는 통과 불가
				if phase[j] == PH_SOLID:
					continue
				
				var Pj := pressure[j]
				
				# 압력 차이 계산
				var dP := Pi - Pj
				
				# 압력이 높은 쪽 → 낮은 쪽 유동
				if abs(dP) < MIN_PRESSURE_DIFF:
					continue
				
				var source := i if dP > 0.0 else j
				var target := j if dP > 0.0 else i
				
				# 유량 계산
				var flow_amount := _compute_flow_amount(
					abs(dP), 
					mass[source],
					free[target],
					dt
				)
				
				if flow_amount > 0:
					flows.append(Flow.new(
						source, target, 
						flow_amount, 
						temp[source]
					))
					
					# 용량 갱신 (내부 일관성)
					free[source] += flow_amount
					free[target] -= flow_amount

## 압력차로부터 유량 계산
##
## 단순화된 모델:
## flow ∝ ΔP × dt
##
## 실제로는 Darcy's law나 Poiseuille's law 사용 가능하지만
## 게임 시뮬레이션에서는 선형 근사로 충분
static func _compute_flow_amount(
	pressure_diff: float,  # Pa
	available_mass: int,   # mg
	available_space: int,  # mg
	dt: float
) -> int:
	# 압력차 → 유속 (단순 선형)
	# 차원 분석: [Pa] × [s] × [상수] → [mg]
	const FLOW_COEFFICIENT := 100.0  # 튜닝 파라미터
	
	var ideal_flow := pressure_diff * dt * FLOW_COEFFICIENT
	
	# 물리적 제약 (mini는 2개 인자만 받음)
	var max_flow := mini(available_mass, available_space)
	max_flow = mini(max_flow, int(ideal_flow))
	
	return max(0, max_flow)
