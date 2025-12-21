## [DataLayer]의 변경 신호를 받아 시각화 컴포넌트들에 전파하는 중재자.
## [br][br]
## 책임:[br]
## - 변경 신호의 정규화 및 검증[br]
## - full/partial 분기 결정[br]
## - 적절한 시각화 컴포넌트에 위임
class_name VisualSync
extends Node

const _PAYLOAD_FLAGS := {
	"sid_changed": false,
	"phase_changed": false,
	"mass_changed": false,
	"temp_changed": false,
	"light_changed": false,
	"full_refresh": false,
}

# ── 설정 ───────────────────────────────────────────────────────────
@export var debug_enabled := false

# ── 의존성 ─────────────────────────────────────────────────────────
var index: GridIndex
var substance: SubstanceStore
var phase: PhaseStore
var mass: MassStore
var temp: TemperatureStore
var light: LightStore

# ── 시각화 ─────────────────────────────────────────────────────────
@onready var ground: Ground = %Ground
@onready var liquid_overlay: LiquidOverlay = %LiquidOverlay
@onready var crack_overlay: CrackOverlay = %CrackOverlay
@onready var corner_highlight: CornerHighlight = %CornerHighlight

# ── 오버레이 ───────────────────────────────────────────────────────
@onready var overlay_manager: OverlayManager = %OverlayManager
@onready var heatmap_overlay: HeatmapOverlay = %HeatmapOverlay
@onready var heat_src_overlay: HeatSourceOverlay = %HeatSourceOverlay
@onready var light_overlay: LightOverlay = %LightOverlay

# ── 레이아웃 정보 캐싱 ─────────────────────────────────────────────
var _world_size: Vector2i
var _tile_size: Vector2i
var _is_initialized := false

func _ready() -> void:
	if ground.tile_set == null:
		Debug.error(self, "Ground tileset is null")
		return
	_tile_size = ground.tile_set.tile_size

func setup(data_layer: DataLayer) -> void:
	index = data_layer.index
	substance = data_layer.substance
	phase = data_layer.phase
	mass = data_layer.mass
	temp = data_layer.temperature
	light = data_layer.light

	Debug.log(self, "DataLayer connected")

## 레이아웃 초기화 (world generation 완료 후)
func initialize_layout(world_size: Vector2i) -> void:
	_world_size = world_size
	
	# 게임 시각화 요소들 초기화
	_setup_game_visuals()
	
	# 오버레이 초기화
	_setup_overlays()
	
	_is_initialized = true
	
	Debug.log(self, "Layout initialized: size=%v, tile_size=%v", [_world_size, _tile_size])

## 게임 시각화 요소 설정
func _setup_game_visuals() -> void:
	# LiquidOverlay
	if liquid_overlay:
		liquid_overlay.set_layout(_world_size, _tile_size)
		Debug.log(self, "LiquidOverlay layout set")
	
	# CrackOverlay
	if crack_overlay:
		crack_overlay.set_layout(_world_size)
		Debug.log(self, "CrackOverlay layout set")
	
	# CornerHighlight
	if corner_highlight:
		corner_highlight.setup(ground)
		Debug.log(self, "CornerHighlight setup complete")

## 오버레이 설정
func _setup_overlays() -> void:
	if heatmap_overlay:
		heatmap_overlay.set_layout(_world_size, _tile_size)
	
	if heat_src_overlay:
		heat_src_overlay.set_layout(_world_size, _tile_size)
	
	if light_overlay:
		light_overlay.set_layout(_world_size, _tile_size)
	
	Debug.log(self, "overlays layout set")

## 초기 상태 렌더링
func render_initial_state(initial_mass: PackedInt64Array) -> void:
	if not _is_initialized:
		Debug.warn(self, "render_initial_state called before initialization")
		return
	
	# 액체 초기 렌더링
	if liquid_overlay:
		liquid_overlay.render(initial_mass)
		Debug.log(self, "Initial liquid state rendered")

## 외부 계약(퍼블릭): 신호는 여기에 연결.[br]
## [param payload]의 [code]full_refresh[/code] 값에 따라
## [method _refresh_full] 또는 [method _refresh_indices]로 분기한다.
func on_tiles_changed(idxs: PackedInt32Array, reason: StringName, payload: Dictionary) -> void:
	# payload 정규화(허용 키만, bool 캐스트)
	var flags := _normalize_payload(payload)
	
	# full_refresh 우선 처리
	if flags.full_refresh:
		Debug.log(self, "full_refresh: reason = %s", [reason])
		_refresh_full(flags)  # 내부 전체 재생성
		return
	
	# 부분 업데이트인데 인덱스 없음 → 계약 위반
	assert(not idxs.is_empty(), "partial update with empty indices; reason=%s" % [str(reason)])
	
	# 검증 통과 → 부분 새로고침 함수로 위임
	Debug.log(self, "partial update: reason=%s, count=%d", [reason, idxs.size()])
	_refresh_indices(idxs, flags)

## 내부 유틸(가벼운 정규화)
func _normalize_payload(src: Dictionary) -> Dictionary:
	var out := _PAYLOAD_FLAGS.duplicate()
	for k in out.keys():
		if src.has(k):
			out[k] = bool(src[k])
	return out

## 전체 갱신.
## 어떤 정보를 동기화하느냐에 대한 입력만 받으며, 구체적 갱신은 직접 한다.
func _refresh_full(payload: Dictionary) -> void:
	#var ch_sid   : bool = payload.get("sid_changed", false)
	#var ch_phase : bool = payload.get("phase_changed", false)
	#var ch_mass  : bool = payload.get("mass_changed", false)
	var ch_temp  : bool = payload.get("temp_changed", false)
	var ch_light : bool = payload.get("light_changed", false)

	if ch_temp:
		heatmap_overlay.render_full_with_mask(temp.get_raw_read(), phase.get_raw_read())
	if ch_light:
		light_overlay.render_full(light.get_raw_read())

## 부분 갱신.
func _refresh_indices(idxs: PackedInt32Array, payload: Dictionary) -> void:
	var ch_sid   : bool = payload.get("sid_changed", false)
	var ch_phase : bool = payload.get("phase_changed", false)
	#var ch_mass  : bool = payload.get("mass_changed", false)
	#var ch_temp  : bool = payload.get("temp_changed", false)
	#var ch_light : bool = payload.get("light_changed", false)
	
	for i in idxs:
		var cell := index.cell(i)
		
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
