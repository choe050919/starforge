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

# ✅ 새로 추가: flows를 Temperature에 전달하기 위해 저장
var _last_flows: Array = []

func setup(layer: DataLayer, spring_cells: PackedVector2Array = PackedVector2Array()) -> void:
	data = layer
	if data == null:
		push_error("[Liquid.setup] DataLayer is null")
	springs = PackedVector2Array(spring_cells)

func set_liquid_sids(water_sid: int = 20001, vacuum_sid: int = 0) -> void:
	_sid_water = water_sid
	_sid_vacuum = vacuum_sid

# ── 틱 ─────────────────────────────────────────────────────────────
func tick_liquid(dt: float) -> void:
	if not enabled or data == null: 
		return
		
	var idx   := data.index
	var phase := data.phase
	var mass  := data.mass
	var temp  := data.temperature

	# ✅ 새로운 방식: 압력 기반 계산
	var flows: Array = core.compute_diff(
		phase.get_raw_read(),
		mass.get_raw_read(),
		temp.get_raw_read(),  # 압력 계산용 (읽기만)
		idx,
		water_capacity_mg_per_cell,
		dt
	)
	
	if flows.is_empty():
		_last_flows = []
		return
	
	# flows 저장 (Temperature가 사용)
	_last_flows = flows
	
	# 질량 변화 적용
	commit_flows(flows)

## ✅ 새로 추가: flows를 Temperature가 읽을 수 있도록 제공
func get_last_flows() -> Array:
	return _last_flows

func commit_flows(flows: Array) -> void:
	var phase := data.phase
	var subs  := data.substance
	var mass  := data.mass

	var n := mass.get_raw_read().size()
	var mass_delta := PackedInt64Array()
	mass_delta.resize(n)
	for i in n:
		mass_delta[i] = 0
	
	# flows를 mass_delta로 변환
	for flow in flows:
		mass_delta[flow.from] -= flow.amount
		mass_delta[flow.to] += flow.amount
	
	# 새 질량 계산
	var m_read := mass.get_raw_read()
	var m_new := PackedInt64Array()
	m_new.resize(n)
	for i in n:
		var v := m_read[i] + mass_delta[i]
		m_new[i] = clampi(v, 0, water_capacity_mg_per_cell)
	
	# 1) 질량 적용
	mass.begin_write()
	for i in n:
		mass.set_by_index(i, m_new[i])
	mass.commit()
	
	# 2) 상/물질 동기화
	var ph_r := phase.get_raw_read()
	phase.begin_write()
	subs.begin_write()
	for i in n:
		if ph_r[i] == PhaseStore.Phase.SOLID:
			continue
		if m_new[i] == 0:
			phase.set_by_index(i, PhaseStore.Phase.VACUUM)
			subs.set_by_index(i, _sid_vacuum)
		else:
			phase.set_by_index(i, PhaseStore.Phase.LIQUID)
			subs.set_by_index(i, _sid_water)
	phase.commit()
	subs.commit()
	
	# ✅ 변경: 온도는 더 이상 여기서 처리 안 함
	# Temperature 시스템이 flows를 받아서 대류 열 계산

# ── 유틸 ────────────────────────────────────────────────────────────
func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	var read_mass := data.mass.get_raw_read()
	var ph_read := data.phase.get_raw_read()
	var out := PackedInt64Array()
	out.resize(read_mass.size())
	for i in read_mass.size():
		out[i] = read_mass[i] if ph_read[i] == PhaseStore.Phase.LIQUID else 0
	return out

func apply_external_delta(d_liquid: PackedInt64Array) -> void:
	if not enabled:
		return
	if data == null:
		push_warning("[Liquid.apply_external_delta] DataLayer is null (ignored)")
		return

	var mass_read: PackedInt64Array = data.mass.get_raw_read()
	var n: int = mass_read.size()
	if d_liquid.size() != n:
		push_warning("[Liquid.apply_external_delta] delta size mismatch. n=%d, got=%d (ignored)" % [n, d_liquid.size()])
		return

	var any_nonzero: bool = false
	for i in n:
		if d_liquid[i] != 0:
			any_nonzero = true
			break
	if not any_nonzero:
		return

	# 단순 적용
	var m_new := PackedInt64Array()
	m_new.resize(n)
	var cap := water_capacity_mg_per_cell
	for i in n:
		var v := mass_read[i] + d_liquid[i]
		if v < 0: v = 0
		elif v > cap: v = cap
		m_new[i] = v
	
	# 질량만 적용 (온도는 Temperature가 관리)
	data.mass.begin_write()
	for i in n:
		data.mass.set_by_index(i, m_new[i])
	data.mass.commit()
	
	# 상/물질 동기화
	var ph_r := data.phase.get_raw_read()
	data.phase.begin_write()
	data.substance.begin_write()
	for i in n:
		if ph_r[i] == PhaseStore.Phase.SOLID:
			continue
		if m_new[i] == 0:
			data.phase.set_by_index(i, PhaseStore.Phase.VACUUM)
			data.substance.set_by_index(i, _sid_vacuum)
		else:
			data.phase.set_by_index(i, PhaseStore.Phase.LIQUID)
			data.substance.set_by_index(i, _sid_water)
	data.phase.commit()
	data.substance.commit()
