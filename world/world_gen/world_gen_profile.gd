@icon("res://icon.svg")
extends Resource
class_name WorldGenProfile

## ─────────────────────────────────────────────────────────────────────────────
## Schema
##  - P0: 값 보관 전용. 어떤 계산/변환/유효성검사도 하지 않음.
##  - 단위:
##     * temp_*_cC : 섭씨×100 (예: 12.34°C => 1234)
##     * mass_*_mg_per_cell : mg
## ─────────────────────────────────────────────────────────────────────────────

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

## ── Global ───────────────────────────────────────────────────────────────────
@export var size: Vector2i = Vector2i(256, 128)
@export var seed_height: int = 12345
@export var height_freq: float = 0.02
@export var water_level_ratio: float = 0.4

## ── Solids: Ground ───────────────────────────────────────────────────────────
@export var ground_temp_init_cC: int = 1200
@export var ground_mass_mg_per_cell: int = 1_200_000

## ── Solids: Ice ──────────────────────────────────────────────────────────────
@export var ice_temp_init_cC: int = -500
@export var ice_mass_mg_per_cell: int = 900_000
@export var ice_seed: int = 98765
@export var ice_freq: float = 0.08
@export var ice_threshold: float = 0.35
@export var ice_max_depth: int = 6
@export var ice_edge_bonus: float = 0.15

## ── Solids: Uranium ──────────────────────────────────────────────────────────
@export var uranium_temp_init_cC: int = 1200
@export var uranium_mass_mg_per_cell: int = 1_900_000
@export var uranium_seed: int = 24680
@export var uranium_freq: float = 0.06
@export var uranium_threshold: float = 0.72
@export var uranium_density: float = 0.006
@export var uranium_depth_min: int = 8
@export var uranium_depth_max: int = 24

## ── Solids: Copper ───────────────────────────────────────────────────────────
@export var copper_temp_init_cC: int = 800
@export var copper_mass_mg_per_cell: int = 1_400_000
@export var copper_seed: int = 13579
@export var copper_freq: float = 0.05
@export var copper_threshold: float = 0.65
@export var copper_density: float = 0.01
@export var copper_depth_min: int = 3
@export var copper_depth_max: int = 15

## ── Liquid: Water ────────────────────────────────────────────────────────────
@export var water_temp_init_cC: int = 800
@export var water_capacity_mg_per_cell: int = 1_000_000
@export var min_lake_size: int = 4
@export var depth_scale: float = 4.0
@export var springs_per_k: float = 1.0
