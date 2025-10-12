## TileChange
##
## Durability에 영향을 주는 모든 타일 변경의 필수 통과점.
## DataLayer를 직접 수정하되, 변경 사항을 시그널로 방송하여
## Durability가 HP 상태를 자동으로 동기화하도록 보장한다.
##
## [b]핵심 역할:[/b]
## 1. 타일 변경의 단일 진입점 (replace_cell, destroy_cell, harvest_mass_from_cell)
## 2. 변경 시그널 발행 (tile_replaced, tile_destroyed, mass_harvested)
## 3. Durability와의 양방향 연결 유지
##
## [b]TileChange를 반드시 거쳐야 하는 작업:[/b]
## - 채굴: 질량 감소 → HP 감소 필요
## - 건설: 새 타일 배치 → HP 초기화 필요
## - 파괴: 타일 제거 → HP 해제 필요
## - 교체: 물질 변경 → HP 재계산 필요
##
## [b]TileChange를 거치지 않아도 되는 작업:[/b]
## - 상전이(PhaseChange): 이미 HP가 설정된 물질의 phase만 변경
## - 온도/조명 변경: HP와 무관한 속성 변경
##
## [b]단위 변환:[/b]
## - DataLayer는 mg(int), centi-K(int) 사용
## - 외부 시스템은 kg(float), K(float) 사용
## - TileChange가 중간에서 단위 변환 담당
extends Node
class_name TileChange

signal tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName)
signal tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName)
signal mass_harvested(cell: Vector2i, material_sid: int, mass_kg: float, temperature_K: float, reason: StringName)

var _data: DataLayer
var _index: GridIndex
var _size: Vector2i = Vector2i.ZERO

# ── 타일/물질 ID 매핑 ────────────────────────────────────────────────────────
# JSON 스키마 기준
const TILE_ICE:     int = 10001
const TILE_SOIL:    int = 10002
const TILE_URANIUM: int = 10003
const TILE_COPPER:  int = 10004
const TILE_WATER:   int = 20001
const TILE_STEAM:   int = 30001
const TILE_VACUUM:  int = 0

# ── 단위 변환/스냅 ───────────────────────────────────────────────────────────
const MASS_SNAP_KG := 1e-6 # 1 mg

static func _snap_mass_kg(x: float) -> float:
	return floor((x / MASS_SNAP_KG) + 0.5) * MASS_SNAP_KG

static func _kg_to_mg(kg: float) -> int:
	return int(round(kg * 1_000_000.0))

static func _mg_to_kg(mg: int) -> float:
	return float(mg) / 1_000_000.0

static func _centiK_to_K(ck: int) -> float:
	return float(ck) / 100.0

# ── 수명주기 ─────────────────────────────────────────────────────────────────
func setup(data: DataLayer) -> void:
	_data = data
	_index = _data.index
	_size = _index.size

# Durability 초기 시딩: DataLayer 단위(mg) → Durability 단위(kg) 변환
func seed_durability(dur: Durability) -> void:
	if _data == null:
		push_warning("[TileChange] seed_durability: DataLayer not set")
		return
	var size := _index.size
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var i := _index.idx(cell)
			var sid := _data.substance.get_by_index(i)
			var mass_mg := _data.mass.get_by_index(i)       # int mg
			var mass_kg := _mg_to_kg(mass_mg)               # float kg
			dur.reset_cell(cell, sid, mass_kg)

# ── API ─────────────────────────────────────────────────────────────────────
## 교체: 단일 셀 교체 (스키마 기본값을 활용하여 phase/mass/temp 초기화)
func replace_cell(cell: Vector2i, to_tile: int, reason: StringName = &"replace") -> void:
	if _data == null:
		push_warning("[TileChange] replace_cell: DataLayer not set")
		return
	if not _index.in_bounds_cell(cell):
		return
	var i := _index.idx(cell)
	var from_sid := _data.substance.get_by_index(i)

	# sid만 명시, 나머지는 null → DataLayer 스키마 기본값을 적용
	_data.set_cell_with_spec(cell, {
		"sid": to_tile,
		"phase": null,
		"mass": null,
		"temp": null,
	}, reason)

	tile_replaced.emit(cell, from_sid, to_tile, reason)

## 파괴: 단일 셀 VACUUM으로 교체
func destroy_cell(cell: Vector2i, reason: StringName = &"destroy") -> void:
	if _data == null:
		push_warning("[TileChange] destroy_cell: DataLayer not set")
		return
	if not _index.in_bounds_cell(cell):
		return
	var i := _index.idx(cell)
	var from_sid := _data.substance.get_by_index(i)

	_data.clear_cell(cell, reason)

	# 명시적으로 진공으로 설정(스키마 의존 X)
	#_data.set_cell_with_spec(cell, {
		#"sid": TILE_VACUUM,
		#"phase": PhaseStore.Phase.VACUUM,
		#"mass": 0,
		#"temp": 0,
		#"hp": 0
	#}, reason)

	tile_destroyed.emit(cell, from_sid, reason)

## 질량 수확(부분/전량): Mining/Durability에서 호출
func harvest_mass_from_cell(cell: Vector2i, requested_mass_kg: float, reason: StringName = &"") -> void:
	if _data == null:
		push_warning("[TileChange] harvest_mass_from_cell: DataLayer not set")
		return
	if not _index.in_bounds_cell(cell):
		return
	if requested_mass_kg <= 0.0:
		return

	var i := _index.idx(cell)
	var sid := _data.substance.get_by_index(i)
	if sid == TILE_VACUUM:
		return

	# DataLayer 단위: mass=mg(int), temp=centi-K(int)
	var cur_mg : int = _data.mass.get_by_index(i)
	if cur_mg <= 0:
		return
	var cur_ck : int = _data.temperature.get_by_index(i)
	var cur_K  : float = _centiK_to_K(cur_ck)

	# 요청값 스냅/변환/클램프
	var req_kg  := _snap_mass_kg(requested_mass_kg) # 1 mg 격자에 스냅
	var req_mg  : int = _kg_to_mg(req_kg)
	var take_mg : int = min(req_mg, cur_mg)
	if take_mg <= 0:
		return

	var rest_mg : int = cur_mg - take_mg

	# 월드 반영: 남으면 mass만, 0이면 VACUUM으로
	if rest_mg > 0:
		# 보존 규칙: sid/phase/temp는 보존, mass만 새 값
		_data.set_cell_with_spec(cell, { "mass": rest_mg }, reason)
	else:
		# 전량 채굴: 명시적으로 진공
		destroy_cell(cell, reason)  # 내부에서 tile_destroyed emit

	# 드롭 알림(kg & K로 변환하여 상위 계층과 단위 일관성 유지)
	mass_harvested.emit(cell, sid, _mg_to_kg(take_mg), cur_K, reason)

# ── 내부 유틸 ────────────────────────────────────────────────────────────────
static func _key(cell: Vector2i) -> int:
	return (cell.y << 16) | (cell.x & 0xFFFF)

func _on_tool_manager_request_vacuum(cell: Vector2i) -> void:
	destroy_cell(cell)
