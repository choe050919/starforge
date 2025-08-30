extends Node
class_name PhaseChange
## 씬 트리에 붙는 시스템 래퍼.
## - 의존성 주입
## - SimClock 신호 연결
## - 디버그/토글/프로파일

@export var enabled := true
@export var debug_log := false

# 히스테리시스/임계값 규칙 파라미터 (Core로 전달)
@export var hyst_ck := 100        # ICE/WATER 공용 히스테리시스 폭
@export var melt_ck := 27315        # ICE 쪽 융해 기준(상향)
@export var freeze_ck := 27314     # WATER 쪽 응고 기준(하향)

# 의존성
var _phase_store: PhaseStore
var _substance_store: SubstanceStore
var _temperature_store: TemperatureStore
var _index: GridIndex
var _clock : SimClock

## 코어: 계산만 담당
var _core: PhaseChangeCore
## 적용기: 계산 결과를 수요자들에게 전달
var _applier: PhaseChangeApplier

func setup(phase_store: PhaseStore, substance_store: SubstanceStore, temperature_store: TemperatureStore, index: GridIndex, visual_sync: VisualSync, clock: SimClock) -> void:
	_phase_store = phase_store
	_substance_store = substance_store
	_temperature_store = temperature_store
	_index = index
	_clock = clock

	@warning_ignore("shadowed_variable_base_class")
	for name in ["_phase_store", "_substance_store", "_temperature_store", "_index", "_clock"]:
		var value = get(name)
		if value == null:
			push_error("[PhaseChange.setup]%s is null" % name)

	_core = PhaseChangeCore.new()
	_core.setup_rules(hyst_ck, melt_ck, freeze_ck)
	_applier = PhaseChangeApplier.new()
	_applier.setup(_index, _phase_store, _substance_store, visual_sync)

func _on_sim_tick(dt: float, sim_time: float) -> void:
	# 시뮬레이션 틱마다 실행
	if not enabled:
		return

	# 1) Core: diff 생성 (셀 목록)
	var diff: Dictionary = _core.tick_fullscan(_phase_store, _substance_store, _temperature_store, _index)
	if diff.is_empty():
		return

	var melt: PackedVector2Array   = diff.get("ice_to_water", PackedVector2Array())
	var freeze: PackedVector2Array = diff.get("water_to_ice", PackedVector2Array())
	var total := melt.size() + freeze.size()

	# 2) Applier: 스토어에 반영 + VisualSync 라우팅 (commit 포함)
	if total > 0:
		_applier.apply(diff, sim_time)

		# 3) 디버그 로그
		if debug_log:
			print("[t=%.2f s][PhaseChange] Δ=%d (ICE→WATER=%d, WATER→ICE=%d)" % [
				sim_time, total, melt.size(), freeze.size()
			])

## 런타임에서 파라미터를 바꿨다면 규칙 재적용
func rebuild_rules() -> void:
	if _core == null:
		_core = PhaseChangeCore.new()
	_core.setup_rules(hyst_ck, melt_ck, freeze_ck)
