@icon("res://icon.svg")
extends Resource
class_name WorldGenProfile

# ─────────────────────────────────────────────────────────────────────────────
# Schema
#  - P0: 값 보관 전용. 어떤 계산/변환/유효성검사도 하지 않음.
#  - 단위:
#     * temp_*_cC : 섭씨×100 (예: 12.34°C => 1234)
#     * mass_*_mg_per_cell : mg
# ─────────────────────────────────────────────────────────────────────────────

@export var schema_version: int = 1

## SID 조회용 키 (rule_cache.sid_of 로 사용)
##  - 오타나 변경이 있으면 물질 배치 실패 → VACUUM으로 나올 수 있음
@export var id_keys := {
	"solid/soil":   "solid/soil",
	"solid/ice":    "solid/ice",
	"solid/uranium":"solid/uranium",
	"solid/copper": "solid/copper",
	"liquid/water": "liquid/water"
	# "vacuum": "vacuum" # 보통 0 고정이라 미사용
}

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Global Settings", "")
# ══════════════════════════════════════════════════════════════════════════════

## 월드 격자 크기(타일 단위). X=가로, Y=세로. 생성되는 모든 배열의 크기를 결정.
@export var size: Vector2i = Vector2i(256, 128)

## 지형선(heightmap) 노이즈 시드. 같은 시드는 같은 지형을 재현.
@export var seed_height: int = 12345

## 지형선 노이즈의 공간 주파수. 값↑ → 기복이 촘촘/급변, 값↓ → 완만/큰 스케일.
@export_range(0.001, 0.1, 0.001, "or_greater") var height_freq: float = 0.02

## 전역 수면 높이 비율(0~1). min/max 지형선 사이를 보간해 수면을 정함. 값↑ → 수면이 더 높음.
@export_range(0.0, 1.0, 0.01) var water_level_ratio: float = 0.4

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Ground (Soil)", "ground_")
# ══════════════════════════════════════════════════════════════════════════════

## GROUND 초기 온도(°C×100). 내부에서 cK(센티켈빈)로 변환해 저장.
@export_range(-5000, 10000, 1, "suffix:cC") var ground_temp_init_cC: int = 1200

## 셀당 GROUND 질량(mg). 타일 초기 질량을 결정.
@export_range(100000, 5000000, 10000, "suffix:mg") var ground_mass_mg_per_cell: int = 1_200_000

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Ice", "ice_")
# ══════════════════════════════════════════════════════════════════════════════

## ICE 초기 온도(°C×100). 내부에서 cK로 변환.
@export_range(-5000, 5000, 1, "suffix:cC") var ice_temp_init_cC: int = -500

## 셀당 ICE 질량(mg). 타일 초기 질량을 결정.
@export_range(100000, 3000000, 10000, "suffix:mg") var ice_mass_mg_per_cell: int = 900_000

## 얼음 분포 노이즈 시드. 같은 시드면 같은 얼음 패턴 재현.
@export var ice_seed: int = 98765

## 얼음 분포 노이즈의 공간 주파수. 값↑ → 얼음 패턴이 촘촘해짐.
@export_range(0.001, 0.2, 0.001, "or_greater") var ice_freq: float = 0.08

## 얼음 마스크 임계값(0~1). (노이즈+표면보너스) ≥ 임계이면 ICE로 분류.
@export_range(0.0, 1.0, 0.01) var ice_threshold: float = 0.45

## 지표선 아래 표면 보너스가 적용되는 최대 깊이(타일). 얕을수록 보너스 큼.
@export_range(1, 20, 1, "suffix:tiles") var ice_max_depth: int = 6

## 표면 보너스 강도(권장 0~1). 깊이가 얕을수록 가산되는 값.
@export_range(0.0, 1.0, 0.01) var ice_edge_bonus: float = 0.15

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Uranium Ore", "uranium_")
# ══════════════════════════════════════════════════════════════════════════════

## 우라늄 초기 온도(°C×100). 내부에서 cK로 변환.
@export_range(-5000, 10000, 1, "suffix:cC") var uranium_temp_init_cC: int = 1200

## 셀당 우라늄 질량(mg). 타일 초기 질량을 결정.
@export_range(100000, 5000000, 10000, "suffix:mg") var uranium_mass_mg_per_cell: int = 1_900_000

## 우라늄 분포 노이즈 시드. 같은 시드면 같은 광맥 패턴 재현.
@export var uranium_seed: int = 24680

## 우라늄 분포 노이즈 주파수. 값↓ → 더 큰 클러스터(덩어리), 값↑ → 잘게 분산.
@export_range(0.001, 0.2, 0.001, "or_greater") var uranium_freq: float = 0.06

## 노이즈 임계값(0~1). 임계 이상이면 클러스터 내부로 간주되어 스폰 후보.
@export_range(0.0, 1.0, 0.01) var uranium_threshold: float = 0.72

## 전역 희귀 난수 가산 확률(0~1). 노이즈 미달이어도 이 확률로 드물게 스폰.
@export_range(0.0, 0.1, 0.001) var uranium_density: float = 0.006

## 지표선 아래 배치 허용 최소 깊이(타일). 이보다 얕으면 스폰 안 함.
@export_range(0, 50, 1, "suffix:tiles") var uranium_depth_min: int = 8

## 지표선 아래 배치 허용 최대 깊이(타일). 이보다 깊으면 스폰 안 함.
@export_range(0, 100, 1, "suffix:tiles") var uranium_depth_max: int = 24

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Copper Ore", "copper_")
# ══════════════════════════════════════════════════════════════════════════════

## 구리 초기 온도(°C×100). 내부에서 cK로 변환.
@export_range(-5000, 10000, 1, "suffix:cC") var copper_temp_init_cC: int = 800

## 셀당 구리 질량(mg). 타일 초기 질량을 결정.
@export_range(100000, 5000000, 10000, "suffix:mg") var copper_mass_mg_per_cell: int = 1_400_000

## 구리 분포 노이즈 시드. 같은 시드면 같은 패턴 재현.
@export var copper_seed: int = 13579

## 구리 분포 노이즈 주파수. 값↓ → 큰 클러스터, 값↑ → 미세한 분포.
@export_range(0.001, 0.2, 0.001, "or_greater") var copper_freq: float = 0.05

## 노이즈 임계값(0~1). 임계 이상이면 스폰 후보.
@export_range(0.0, 1.0, 0.01) var copper_threshold: float = 0.65

## 전역 희귀 난수 가산 확률(0~1). 임계 미달이어도 이 확률로 드물게 스폰.
@export_range(0.0, 0.1, 0.001) var copper_density: float = 0.01

## 지표선 아래 배치 허용 최소 깊이(타일).
@export_range(0, 50, 1, "suffix:tiles") var copper_depth_min: int = 3

## 지표선 아래 배치 허용 최대 깊이(타일).
@export_range(0, 100, 1, "suffix:tiles") var copper_depth_max: int = 15

# ══════════════════════════════════════════════════════════════════════════════
@export_group("Water (Liquid)", "water_")
# ══════════════════════════════════════════════════════════════════════════════

## 물 초기 온도(°C×100). 내부에서 cK로 변환.
@export_range(-5000, 10000, 1, "suffix:cC") var water_temp_init_cC: int = 800

## 셀당 물 최대 용량(mg). 호수 채움량과 시뮬레이션 상한에 사용.
@export_range(100000, 3000000, 10000, "suffix:mg") var water_capacity_mg_per_cell: int = 1_000_000

## 호수로 인정되는 최소 가로 너비(타일). 이보다 좁은 구간은 무시.
@export_range(1, 20, 1, "suffix:tiles") var water_min_lake_size: int = 4

## 호수 채움 강도 스케일. 수면에서 d칸 아래일 때 fill≈clamp(d/scale,0..1). 값↑ → 얕은 층 위주로 채움.
@export_range(1.0, 20.0, 0.1) var water_depth_scale: float = 4.0

## 샘물 발생 밀도(1,000열 좌표당 기대 개수). 값↑ → 샘물 더 자주 생성.
@export_range(0.0, 10.0, 0.1, "suffix:/k columns") var water_springs_per_k: float = 1.0
