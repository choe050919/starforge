extends Node
class_name Liquid

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled: bool = true
@export var debug_log: bool = false
@export var water_capacity_mg_per_cell: int = 1_000_000

# JSON sid 주입
var _sid_water: int
var _sid_vacuum: int

# ── 의존성 ─────────────────────────────────────────────────────────
var data: DataLayer
var core: LiquidCore = LiquidCore.new()
var springs: PackedVector2Array = PackedVector2Array()

func setup(layer: DataLayer, spring_cells: PackedVector2Array = PackedVector2Array()) -> void:
	data = layer
	if data == null:
		push_error("[Liquid.setup] DataLayer is null")
	springs = PackedVector2Array(spring_cells)

## 외부에서 JSON 기준 sid를 주입
func set_liquid_sids(water_sid: int = 20001, vacuum_sid: int = 0) -> void:
	_sid_water = water_sid
	_sid_vacuum = vacuum_sid

# ── 틱 ─────────────────────────────────────────────────────────────
func tick_liquid(dt: float) -> void:
	if not enabled or data == null: return
	var idx   := data.index
	var phase := data.phase
	var subs  := data.substance
	var mass  := data.mass
	var temp  := data.temperature

	# 읽기 스냅샷 구성
	var R := {
		"idx": idx,
		"ph": phase.get_raw_read(),
		"sid": subs.get_raw_read(),
		"m": mass.get_raw_read(),
		"T": temp.get_raw_read(),
		"cap": water_capacity_mg_per_cell,
	}

	# 코어 계산
	var diff := core.compute_diff(R, dt)
	if diff.get("moved_total", 0) <= 0: return

	commit_liquid(diff)

func commit_liquid(core_out: Dictionary) -> void:
	# 0) 읽기 스냅샷 (write 시작 전에!)
	var phase := data.phase
	var subs  = data.substance
	var mass  = data.mass
	var temp  = data.temperature

	var ph_r : PackedByteArray   = phase.get_raw_read()
	var m_r  : PackedInt64Array  = mass.get_raw_read()
	var n := m_r.size()
	var cap := water_capacity_mg_per_cell

	var dM: PackedInt64Array = core_out["mass_delta"]
	var tW: Array            = core_out["temp_writes"]

	# 1) 새 질량/플래그 계산
	var m_new := PackedInt64Array(); m_new.resize(n)
	var became_vacuum := PackedByteArray(); became_vacuum.resize(n)
	var first_inflow  := PackedByteArray(); first_inflow.resize(n)

	for i in n:
		var v := m_r[i] + dM[i]
		if v < 0: v = 0
		elif v > cap: v = cap
		m_new[i] = v
		became_vacuum[i] = 1 if (m_r[i] > 0 and v == 0) else 0
		first_inflow[i]  = 1 if (m_r[i] == 0 and v > 0) else 0

	# 2) 질량 write
	mass.begin_write()
	for i in n:
		mass.set_by_index(i, m_new[i])
	mass.commit()

	# 3) 상/물질 동기화 (고체 건드리지 않음)
	phase.begin_write()
	subs.begin_write()
	for i in n:
		if ph_r[i] == phase.Phase.SOLID: # 고체는 PhaseChange 관할
			continue
		if m_new[i] == 0:
			phase.set_by_index(i, phase.Phase.VACUUM)
			subs.set_by_index(i, _sid_vacuum)
		else:
			phase.set_by_index(i, phase.Phase.LIQUID)
			subs.set_by_index(i, _sid_water)
	phase.commit()
	subs.commit()

	# 4) 온도 처리
	temp.begin_write()
	# 4a) VACUUM으로 비워진 칸은 0으로 리셋
	for i in n:
		if became_vacuum[i]:
			temp.set_by_index(i, 0)

	# 4b) 최초 유입 온도 초기화 (안전하게 first_inflow 재확인)
	for e in tW:
		var ti: int = e["i"]
		var t_src: int = e["T"]
		if ti >= 0 and ti < n and first_inflow[ti] == 1:
			temp.set_by_index(ti, t_src)
	temp.commit()

# ── 유틸(선택) ────────────────────────────────────────────────────
func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	var read_mass := data.mass.get_raw_read()
	var ph_read := data.phase.get_raw_read()
	var out := PackedInt64Array(); out.resize(read_mass.size())
	for i in read_mass.size():
		out[i] = read_mass[i] if ph_read[i] == PhaseStore.Phase.LIQUID else 0
	return out

## 외부 시스템(예: Moisture)에서 보낸 액체 질량 델타를 적용
## d_liquid[i] < 0 : 해당 칸 액체 → 토양으로 침투
## d_liquid[i] > 0 : 토양 → 해당 칸으로 용출
func apply_external_delta(d_liquid: PackedInt64Array) -> void:
	if not enabled:
		return
	if data == null:
		push_warning("[Liquid.apply_external_delta] DataLayer is null (ignored)")
		return

	# 길이 검증
	var mass_read: PackedInt64Array = data.mass.get_raw_read()
	var n: int = mass_read.size()
	if d_liquid.size() != n:
		push_warning("[Liquid.apply_external_delta] delta size mismatch. n=%d, got=%d (ignored)" % [n, d_liquid.size()])
		return

	# 전체 0이면 스킵
	var any_nonzero: bool = false
	for i in n:
		if d_liquid[i] != 0:
			any_nonzero = true
			break
	if not any_nonzero:
		return

	# 기존 커밋 경로 재사용 (phase/substance/온도 동기화 포함)
	var core_out: Dictionary = {
		"mass_delta": d_liquid,
		"temp_writes": [],  # v0: 온도 초기화 정책 보류
	}
	commit_liquid(core_out)
