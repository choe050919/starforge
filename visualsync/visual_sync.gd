extends Node
class_name VisualSync

const _PAYLOAD_FLAGS := {
	"sid_changed": false,
	"phase_changed": false,
	"mass_changed": false,
	"temp_changed": false,
	"full_refresh": false,
}
const _LOG_SAMPLE := 8

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled := true
@export var debug_log := false

# ── 의존성 ─────────────────────────────────────────────────────────
var _data_layer: DataLayer
var substance: SubstanceStore
var phase: PhaseStore
var mass: MassStore
var temp: TemperatureStore
var light: LightStore

@onready var ground: Ground = %Ground
@onready var heatmap_overlay: HeatmapOverlay = %HeatmapOverlay
@onready var light_overlay: LightOverlay = %LightOverlay

func setup(data_layer: DataLayer) -> void:
	_data_layer = data_layer
	substance = _data_layer.substance
	phase = _data_layer.phase
	mass = _data_layer.mass
	temp = _data_layer.temperature
	light = _data_layer.light

## 외부 계약(퍼블릭): 신호는 여기에 연결
func on_tiles_changed(idxs: PackedInt32Array, reason: StringName, payload: Dictionary) -> void:
	# 1) payload 정규화(허용 키만, bool 캐스트)
	var flags := _normalize_payload(payload)

	# 2) full_refresh 우선 처리
	if flags.full_refresh:
		if debug_log:
			print("[VisualSync] full_refresh: reason=", reason)
		_refresh_all(flags)  # 내부 전체 재생성
		return

	# 3) 부분 업데이트인데 인덱스 없음 → no-op 또는 경고
	if idxs.is_empty():
		if debug_log:
			push_warning("[VisualSync] partial update with empty indices; reason=%s" % [str(reason)])
		return

	# 4) 라이트 로깅(샘플링)
	if debug_log:
		var n := idxs.size()
		var show: int = min(n, _LOG_SAMPLE)
		print("[VisualSync] update n=", n, " reason=", reason, " sample=", idxs.slice(0, show))

	# 5) 검증 통과 → 본체로 위임 (얇게 유지)
	_on_tiles_changed(idxs, reason, flags)

## 본체
## DataLayer의 set_cells_with_spec함수에서 인자 전달됨
## payload 키:
## "sid_changed" | "phase_changed" | "mass_changed" | "temp_changed"
func _on_tiles_changed(
	idxs: PackedInt32Array,
	_reason: StringName,
	payload: Dictionary
) -> void:
	# 1) 전체 무효화 신호면 풀 리프레시
	if payload.get("full_refresh", false):
		_refresh_all(payload) # ← 내부에서 각 레이어/텍스처 전체 재생성
		return

	# 2) 부분 업데이트 경로
	_refresh_indices(idxs, payload)

## 내부 유틸(가벼운 정규화)
func _normalize_payload(src: Dictionary) -> Dictionary:
	var out := _PAYLOAD_FLAGS.duplicate()
	for k in out.keys():
		if src.has(k):
			out[k] = bool(src[k])
	return out

## 전체 갱신. 어떤 정보를 동기화하느냐에 대한 입력만 받으며, 구체적 갱신은 직접 한다.
func _refresh_all(payload: Dictionary) -> void:
	var ch_sid   : bool = payload.get("sid_changed", false)
	var ch_phase : bool = payload.get("phase_changed", false)
	var ch_mass  : bool = payload.get("mass_changed", false)
	var ch_temp  : bool = payload.get("temp_changed", false)
	var ch_light : bool = payload.get("light_changed", false)

	if ch_temp:
		heatmap_overlay.render_full_with_mask(temp.get_raw_read(), phase.get_raw_read())
	if ch_light:
		light_overlay.render_full(light.get_raw_read())

func _refresh_indices(idxs: PackedInt32Array, payload: Dictionary) -> void:
	var ch_sid   : bool = payload.get("sid_changed", false)
	var ch_phase : bool = payload.get("phase_changed", false)
	var ch_mass  : bool = payload.get("mass_changed", false)
	var ch_temp  : bool = payload.get("temp_changed", false)
	var ch_light : bool = payload.get("light_changed", false)

	for i in idxs:
		var cell := _data_layer.index.cell(i)

		# ── Substance/Phase 변경 → Terrain 쪽 갱신
		if ch_sid or ch_phase:
			var sid   := substance.get_by_index(i)
			ground.apply_cell_change(cell, sid)

		# ── Mass 변경 → 액체 오버레이
		#if ch_mass:
			#var m := mass.get_by_index(i)
			#_lo.update_cell(cell, m)

		# ── Temperature 변경 → 히트맵 오버레이
		#if ch_temp:
			#var t := temp.get_by_index(i)
			#_lo.update_heat(cell, t)
