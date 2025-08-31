extends Node
class_name Liquid

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled: bool = true
@export var debug_log: bool = false
@export var water_capacity_mg_per_cell: int = 1_000_000_000

# JSON sid 주입
var _sid_water: int
var _sid_vacuum: int

## 1회 경고 방지용
var _warned_missing_sid_once := false

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
	if not enabled or data == null:
		return
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

	# 적용(간단 적용기: Liquid 내부에서 트랜잭션 처리)
	var moved_total: int = diff.get("moved_total", 0)

	# 1) 질량 적용
	if moved_total > 0:
		mass.begin_write()
		var dm: PackedInt64Array = diff["mass_delta"]
		for i in dm.size():
			var delta := dm[i]
			if delta != 0:
				mass.add(i, delta)
		mass.commit()

	# 2) 첫 유입 온도 계승 적용
	var tw: Array = diff["temp_writes"]
	if tw.size() > 0:
		temp.begin_write()
		for t in tw:
			# 안전 가드(형/범위 도중 오류 방지)
			if t.has("i") and t.has("T"):
				temp.set_by_index(int(t["i"]), int(t["T"]))
		temp.commit()

	_sync_liquid_vs_vacuum()

	if debug_log and (moved_total > 0 or tw.size() > 0):
		print("[Liquid] moved_total=%d, temp_writes=%d" % [moved_total, tw.size()])

func _sync_liquid_vs_vacuum():
	var phase := data.phase
	var subs  := data.substance
	var mass  := data.mass

	var m := mass.get_read()
	var ph := phase.get_raw_read()
	var sid := subs.get_raw_read()

	var wrote_ph := false
	var wrote_sid := false

	var can_sync_sid := _sid_water >= 0 and _sid_vacuum >= 0
	if not can_sync_sid and not _warned_missing_sid_once:
		_warned_missing_sid_once = true
		push_warning("[Liquid] WATER/VACUUM sid not set. Call set_liquid_sids(water_sid, vacuum_sid). Substance sync skipped (phase sync continues).")

	for i in m.size():
		# 고체면 패스 (PhaseChange 관할)
		if ph[i] == PhaseStore.Phase.SOLID:
			continue

		var has := m[i] > 0

		# Phase 동기화 (VACUUM ↔ LIQUID)
		var want_ph := PhaseStore.Phase.LIQUID if has else PhaseStore.Phase.VACUUM
		if ph[i] != want_ph:
			if not wrote_ph:
				phase.begin_write(); wrote_ph = true
			phase.set_by_index(i, want_ph)

		# Substance 동기화 (WATER ↔ VACUUM) — sid가 설정된 경우에만
		if can_sync_sid:
			var want_sid := _sid_water if has else _sid_vacuum
			if sid[i] != want_sid:
				if not wrote_sid:
					subs.begin_write(); wrote_sid = true
				subs.set_by_index(i, want_sid)

	if wrote_ph:
		phase.commit()
	if wrote_sid:
		subs.commit()


# ── 타일 이벤트 ───────────────────────────────────────────────────
# PhaseChange가 보낸 이유(reason)인지 구분하여 충돌 회피
func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	# 상변화: 얼음→물로 녹는 과정에서 타일 파괴 이벤트가 올 수 있음.
	# 이 경우 Liquid가 phase/mass를 다시 만지지 않도록 무시.
	if reason == &"phase_change:ice_to_water":
		if debug_log:
			print("[Liquid] ignore on_tile_destroyed (phase_change:ice_to_water) at ", cell)
		return

	# 일반 타일 파괴에 대한 최소 처리(원한다면 확장)
	# 현재는 '물 로직'이 별도 조치를 요구하지 않음.

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
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
