## 데이터 접근/커밋/시그널·로그/액체 연동 담당
extends Node
class_name Moisture

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled: bool = true
@export var debug_log: bool = false

# ── 의존성 ─────────────────────────────────────────────────────────
var core: MoistureCore = MoistureCore.new()

var index: GridIndex
var soil_view: SoilViewStore
var moisture_store: MoistureStore
var hydrology_field: HydrologyField
var substance_store: SubstanceStore      # (옵션) 크기 검증용
var liquid_mass_reader

signal liquid_delta_ready(d_liquid: PackedInt64Array)  # 외부 Liquid 시스템이 적용하도록 던짐

func setup(
	_index: GridIndex,
	_soil_view: SoilViewStore,
	_moisture: MoistureStore,
	_hydro_field: HydrologyField,
	_substance: SubstanceStore,
	_liquid_mass_reader
) -> void:
	index = _index
	soil_view = _soil_view
	moisture_store = _moisture
	hydrology_field = _hydro_field
	substance_store = _substance
	liquid_mass_reader = _liquid_mass_reader

# ── 틱 ─────────────────────────────────────────────────────────────
func moisture_tick(dt: float) -> void:
	if not enabled: return
	# v0: 파라미터는 "per tick" 단위. dt 스케일은 아직 적용하지 않음.

	var w: int = index.size.x
	var h: int = index.size.y
	var n: int = w * h

	var soil_idx: PackedInt32Array = soil_view.get_indices()
	var soil_mask: PackedByteArray = soil_view.get_raw_read()

	var m_read: PackedInt32Array = moisture_store.get_raw_read()
	var cap: PackedInt32Array = hydrology_field.capacity
	var infil: PackedInt32Array = hydrology_field.infil
	var leak: PackedInt32Array = hydrology_field.leak
	var diffu: PackedInt32Array = hydrology_field.diff

	# 표면 액체 질량 읽기 (READ ONLY)
	var liq_read: PackedInt64Array = PackedInt64Array()
	if liquid_mass_reader != null:
		liq_read = liquid_mass_reader.get_read()

	var result: Dictionary = core.step(
		w, h, n,
		soil_idx, soil_mask,
		m_read, cap, infil, leak, diffu,
		liq_read
	)

	var d_soil: PackedInt32Array = result["d_soil"]
	var d_liquid: PackedInt64Array = result["d_liquid"]

	# ── Moisture 적용(클램프 포함)
	moisture_store.begin_write()
	# 1) 델타 적용(토양만 순회)
	var m_write: PackedInt32Array = moisture_store.get_raw_write()
	for k in soil_idx.size():
		var i: int = soil_idx[k]
		var v: int = m_read[i] + d_soil[i]
		if v < 0: v = 0
		var cap_i: int = cap[i]
		if cap_i >= 0 and v > cap_i:
			v = cap_i
		if v != m_read[i]:
			m_write[i] = v
			# 더티 마킹은 MoistureStore 내부가 처리(배치 시그널)

	# 2) 비토양은 강제 0
	moisture_store.zero_non_soil(soil_mask)

	moisture_store.commit()

	# ── 액체 델타 전달: 외부 Liquid 시스템이 적용하도록 시그널(또는 포트)로 넘김
	#  - infiltration: 같은 칸 음수
	#  - 용출: 아래칸 양수
	emit_signal("liquid_delta_ready", d_liquid)

	if debug_log:
		var sum_m_before: int = 0
		for v in m_read: sum_m_before += v
		var sum_m_after: int = 0
		var m_new: PackedInt32Array = moisture_store.get_raw_read()
		for v2 in m_new: sum_m_after += v2

		var moved_infil: int = 0
		var moved_leak_out: int = 0
		for i in n:
			var dl: int = int(d_liquid[i]) if i < d_liquid.size() else 0
			if dl < 0: moved_infil += -dl
			elif dl > 0: moved_leak_out += dl

		print("[Moisture] soilΔ=", sum_m_after - sum_m_before,
			" infil→soil=", moved_infil,
			" soil→liq=", moved_leak_out,
			" changed=", soil_idx.size())
