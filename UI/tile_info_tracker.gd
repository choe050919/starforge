## 세분화된 푸시 패턴용 트래커
## - 현재 hover 셀에 한해서만, Store들의 변경 신호에 반응하여 최신 TileInfo를 발행한다.
extends Node
class_name TileInfoTracker

signal info_updated(info)                 # 갱신된 TileInfo를 외부(패널 등)로 알림
signal current_cell_changed(cell: Vector2i)

var info_provider := TileInfoProvider.new()

## ── 외부 주입 객체들 ──────────────────────────────────────────────────
var hover_service: HoverService

var _data: DataLayer

# 세분화 푸시: 필요한 스토어들
var _phase_store: PhaseStore
var _mass_store: MassStore
var _temperature_store: TemperatureStore

# 경계 체크용 인덱스
var _index: GridIndex

## ── 내부 상태 ─────────────────────────────────────────────────────────
var _current_cell: Vector2i = Vector2i(-1, -1)
var _has_focus: bool = false             # hover 중 여부(hover_cleared 대응)

func setup(data:DataLayer, hs: HoverService) -> void:
	_data = data
	hover_service = hs
	_index = _data.index
	_phase_store = _data.phase
	_mass_store = _data.mass
	_temperature_store = _data.temperature

	for name in ["hover_service", "_index", "_phase_store", "_mass_store", "_temperature_store"]:
		var value = get(name)
		if value == null:
			print("%s is null" % name)

	_connect_sources()

	if info_provider:
		info_provider.setup(_data)
	else:
		push_error("[TileInfoTracker.setup] 어쩌구저쩌구 귀찮다")

## ── 연결부 ────────────────────────────────────────────────────────────
func _connect_sources() -> void:
	# Hover
	#if hover_service: 이건 world.gd에서 구현해서 연결되어야 할 부분.
		#if hover_service.has_signal("hover_cleared"):
			#hover_service.hover_cleared.connect(_on_hover_cleared)

	# Stores (세분화된 푸시)
	if _phase_store.has_signal("phase_changed"):
		_phase_store.phase_changed.connect(_on_phase_changed)
	if _mass_store.has_signal("mass_changed"):
		_mass_store.mass_changed.connect(_on_mass_changed)
	if _temperature_store.has_signal("temperature_changed"):
		_temperature_store.temperature_changed.connect(_on_temperature_changed)

## ── Hover 수신 ────────────────────────────────────────────────────────
func on_hover_changed(cell: Vector2i) -> void:
	if not _index.in_bounds_cell(cell):
		_on_hover_cleared()
		return
	if cell == _current_cell and _has_focus:
		return
	_current_cell = cell
	_has_focus = true
	emit_signal("current_cell_changed", cell)
	_emit_full_info_now()  # 최초 1회 즉시 조회(깜빡임 방지)

func _on_hover_cleared() -> void:
	_has_focus = false
	_current_cell = Vector2i(-1, -1)
	# 패널 숨김은 HUD 쪽에서 처리 (여긴 데이터 발행만 담당)

## ── Store 변경 신호 핸들러(현재 셀에만 반응) ─────────────────────────
func _on_phase_changed(cell: Vector2i) -> void:
	if cell == _current_cell:
		_emit_full_info_now()

func _on_mass_changed(cell: Vector2i) -> void:
	if cell == _current_cell:
		_emit_full_info_now()

func _on_temperature_changed(cell: Vector2i) -> void:
	if cell == _current_cell:
		_emit_full_info_now()

## ── 조회 & 발행 ───────────────────────────────────────────────────────
func _emit_full_info_now() -> void:
	if not _has_focus:
		return
	if not _index.in_bounds_cell(_current_cell):
		return
	if info_provider.has_method("query"):
		var info = info_provider.query(_current_cell)
		if info != null:
			emit_signal("info_updated", info)
		else:
			push_error("[TileInfoTracker] info is null")
	else:
		push_error("[TileInfoTracker] Missing method: TileInfoProvider.query")
