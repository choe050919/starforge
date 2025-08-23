extends Node
class_name TileInfoTracker
## 세분화된 푸시 패턴용 트래커
## - 현재 hover 셀에 한해서만, Store들의 변경 신호에 반응하여 최신 TileInfo를 발행한다.

signal info_updated(info)                 # 갱신된 TileInfo를 외부(패널 등)로 알림
signal current_cell_changed(cell: Vector2i)

var info_provider := TileInfoProvider.new()

## ── 외부 주입 객체들 ──────────────────────────────────────────────────
var hover_service: HoverService

# 세분화 푸시: 필요한 스토어들
var phase_store: PhaseStore
var mass_store: MassStore

# 경계 체크용 인덱스
var index: GridIndex

## ── 내부 상태 ─────────────────────────────────────────────────────────
var _current_cell: Vector2i = Vector2i(-1, -1)
var _has_focus: bool = false             # hover 중 여부(hover_cleared 대응)

func _ready() -> void:
	_connect_sources()

func setup(hs: HoverService, gi: GridIndex, ps: PhaseStore, ms: MassStore) -> void:
	hover_service = hs
	index = gi
	phase_store = ps
	_connect_sources()

	if info_provider:
		info_provider.setup(ps, ms, gi)
	else:
		push_error("[TileInfoTracker] 어쩌구저쩌구 귀찮다")

## ── 연결부 ────────────────────────────────────────────────────────────
func _connect_sources() -> void:
	# Hover
	#if hover_service: 이건 world.gd에서 구현해서 연결되어야 할 부분.
		#if hover_service.has_signal("hover_cleared"):
			#hover_service.hover_cleared.connect(_on_hover_cleared)

	# Stores (세분화된 푸시)
	if phase_store and phase_store.has_signal("phase_changed"):
		phase_store.phase_changed.connect(_on_phase_changed)
	if mass_store and mass_store.has_signal("mass_changed"):
		mass_store.mass_changed.connect(_on_mass_changed)

## ── Hover 수신 ────────────────────────────────────────────────────────
func on_hover_changed(cell: Vector2i,) -> void:
	if not _in_bounds(cell):
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

## ── 조회 & 발행 ───────────────────────────────────────────────────────
func _emit_full_info_now() -> void:
	if not _has_focus:
		return
	if not _in_bounds(_current_cell):
		return
	if info_provider.has_method("query"):
		var info = info_provider.query(_current_cell)
		if info != null:
			emit_signal("info_updated", info)
		else:
			push_error("[TileInfoTracker] info is null")
	else:
		push_error("[TileInfoTracker] Missing method: TileInfoProvider.query")
		# Provider가 아직 없다면 최소 Fallback(Phase만) — 필요시 지워도 됨
		#var info = _fallback_min_info(_current_cell)
		#if info != null:
			#emit_signal("info_updated", info)

## ── 유틸 ─────────────────────────────────────────────────────────────
func _in_bounds(cell: Vector2i) -> bool:
	if index and index.has_method("in_bounds"):
		return index.in_bounds(cell)
	push_error("[TileInfoTracker] failed to use method in_bounds: temporary return true")
	return true

"""
# Provider가 준비되기 전 임시용: Phase만 채운 TileInfo
func _fallback_min_info(cell: Vector2i):
	# TileInfo 타입이 프로젝트에 있다면 사용, 없다면 Dictionary로도 충분
	var info := null
	if ClassDB.class_exists("TileInfo"):
		info = TileInfo.new()
		info.cell = cell
		info.name = "Tile"
		# Phase 숫자값 → 문자열 매핑은 프로젝트 상수에 맞게 바꾸세요.
		var phase_str := _read_phase_str(cell)
		info.phase = phase_str if info.has_method("get") == false else phase_str # (유연성 보존)
	else:
		info = {
			"cell": cell,
			"name": "Tile",
			"phase": _read_phase_str(cell)
		}
	return info
"""

"""
func _read_phase_str(cell: Vector2i) -> String:
	if phase_store:
		# 가능한 메서드 패턴을 순차적으로 시도 (프로젝트 구현 체계에 맞게 하나만 남겨도 됨)
		if phase_store.has_method("get_phase_at"):
			return str(phase_store.get_phase_at(cell))
		if phase_store.has_method("get"):
			return str(phase_store.get(cell))
		if phase_store.has_method("at"):
			return str(phase_store.at(cell))
	return "UNKNOWN"
"""
