extends RefCounted
class_name SubstanceDef
## SubstanceId → 기본 속성(phase, default_mass_mg) 매핑 테이블
## - phase: PhaseStore.Phase.* (프로젝트 enum과 일치해야 함)
## - default_mass_mg: 셀 기본 질량(mg). 필요 시 0 허용.

# 단위: mg
const MG := 1

# 요구: SubstanceStore.SubstanceId 와 PhaseStore.Phase 가 이미 정의돼 있다고 가정
const DEFS := {
	SubstanceStore.SubstanceId.VACUUM: {
		"phase": PhaseStore.Phase.VACUUM,
		"default_mass_mg": 0 * MG,
	},
	SubstanceStore.SubstanceId.ICE: {
		"phase": PhaseStore.Phase.SOLID,
		"default_mass_mg": 900_000_000 * MG,   # 900 kg
	},
	SubstanceStore.SubstanceId.GROUND: {
		"phase": PhaseStore.Phase.SOLID,
		"default_mass_mg": 1_200_000_000 * MG, # 1200 kg
	},
	SubstanceStore.SubstanceId.URANIUM: {
		"phase": PhaseStore.Phase.SOLID,
		"default_mass_mg": 1_900_000_000 * MG, # 1900 kg
	},
	SubstanceStore.SubstanceId.WATER: {
		"phase": PhaseStore.Phase.LIQUID,
		"default_mass_mg": 1_000_000 * MG,     # 1 kg
	},
}

const EMPTY := { "phase": PhaseStore.Phase.VACUUM, "default_mass_mg": 0 }

static func has(id: int) -> bool:
	return DEFS.has(id)

static func get_def(id: int) -> Dictionary:
	return DEFS.get(id, EMPTY)

static func phase_of(id: int) -> int:
	return get_def(id).get("phase")

static func default_mass_of(id: int) -> int:
	return get_def(id).get("default_mass_mg")
