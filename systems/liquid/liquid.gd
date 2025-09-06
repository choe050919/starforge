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
		"m": mass.get_read(),
		"T": temp.get_raw_read(),
		"cap": water_capacity_mg_per_cell,
	}

	# 코어 계산
	var diff := core.compute_diff(R, dt)
	if diff.get("moved_total", 0) <= 0: return

	commit_liquid(diff)

	# 1) 질량 적용
	#mass.begin_write()
	#var dm: PackedInt64Array = diff["mass_delta"]
	#for i in dm.size():
		#var delta := dm[i]
		#if delta != 0:
			#mass.add(i, delta)
	#mass.commit()

	# 2) 첫 유입 온도 계승 적용
	#var tw: Array = diff["temp_writes"]
	#if tw.size() > 0:
		#temp.begin_write()
		#for t in tw:
			## 안전 가드(형/범위 도중 오류 방지)
			#if t.has("i") and t.has("T"):
				#temp.set_by_index(int(t["i"]), int(t["T"]))
		#temp.commit()
#
	#_sync_liquid_vs_vacuum()

func commit_liquid(core_out: Dictionary) -> void:
	# 0) 읽기 스냅샷 (write 시작 전에!)
	var phase := data.phase
	var subs  = data.substance
	var mass  = data.mass
	var temp  = data.temperature
	var idx   = data.index

	var ph_r : PackedByteArray   = phase.get_raw_read()
	var m_r  : PackedInt64Array  = mass.get_read()
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

# ── 타일 이벤트 ───────────────────────────────────────────────────
# PhaseChange가 보낸 이유(reason)인지 구분하여 충돌 회피
func on_tile_destroyed(cell: Vector2i, _from_tile: int, reason: StringName) -> void:
	# 상변화: 얼음→물로 녹는 과정에서 타일 파괴 이벤트가 올 수 있음.
	# 이 경우 Liquid가 phase/mass를 다시 만지지 않도록 무시.
	if reason == &"phase_change:ice_to_water":
		if debug_log:
			print("[Liquid] ignore on_tile_destroyed (phase_change:ice_to_water) at ", cell)
		return

	# 일반 타일 파괴에 대한 최소 처리(원한다면 확장)
	# 현재는 '물 로직'이 별도 조치를 요구하지 않음.

func on_tile_replaced(cell: Vector2i, _from_tile: int, _to_tile: int, reason: StringName) -> void:
	# 상변화: 물→얼음으로 바뀌는 경우, 물 질량만 0으로 정리(phase/substance는 PhaseChange가 담당)
	if reason == &"phase_change:water_to_ice":
		if data == null: return
		data.mass.begin_write()
		data.mass.set_cell(cell, 0) # mg 단위
		data.mass.commit()
		if debug_log:
			print("[Liquid] on_tile_replaced (phase_change:water_to_ice) mass→0 at ", cell)
		return

	# 일반 교체(맵 편집 등)일 때만 필요시 별도 처리

## ── 유틸(선택) ────────────────────────────────────────────────────
func get_amounts() -> PackedInt64Array:
	if data == null:
		return PackedInt64Array()
	var read_mass := data.mass.get_read()
	var ph_read := data.phase.get_raw_read()
	var out := PackedInt64Array(); out.resize(read_mass.size())
	for i in read_mass.size():
		out[i] = read_mass[i] if ph_read[i] == PhaseStore.Phase.LIQUID else 0
	return out
