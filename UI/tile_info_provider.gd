extends RefCounted
class_name TileInfoProvider
## 한 셀의 표시용 정보를 묶어서 돌려주는 조회기.

# ── 의존성 ────────────────────────────────────────────────
var _grid_index: GridIndex
var _substance_store: SubstanceStore
var _phase_store: PhaseStore
var _mass_store: MassStore
var _temperature_store: TemperatureStore

# ── 설정 ─────────────────────────────────────────────────
func setup(gi: GridIndex, ss: SubstanceStore, ps: PhaseStore, ms: MassStore, ts: TemperatureStore) -> void:
	_grid_index = gi
	_substance_store = ss
	_phase_store = ps
	_mass_store = ms
	_temperature_store = ts

func is_ready() -> bool:
	if not _substance_store.has_method("get_by_cell"):
		push_warning("[TileInfoProvider] Missing method: SubstanceStore.get_by_cell")
		return false
	if not _phase_store.has_method("get_phase"):
		push_warning("[TileInfoProvider] Missing method: PhaseStore.get_phase")
		return false
	if not _mass_store.has_method("get_by_index"):
		push_warning("[TileInfoProvider] Missing method: MassStore.get_by_index")
		return false
	else: return true

# ── 조회 API ──────────────────────────────────────────────
func query(cell: Vector2i):
	# 반환: TileInfo(권장) 또는 Dictionary(대체). 패널이 enum→문자열 매핑을 맡는다.
	if not is_ready():
		return _make_info(cell, -1, -1, -1, -1)

	if _grid_index and _grid_index.has_method("in_bounds") and not _grid_index.in_bounds(cell):
		push_warning("[TileInfoProvider] cell is not in bounds")
		return _make_info(cell, -1, -1, -1, -1)

	var substance_val := _read_substance(cell)
	var phase_val := _read_phase(cell)
	var mass_val := _read_mass(cell)  # 없으면 NAN
	var temperature_val := _read_temperature(cell)

	return _make_info(cell, substance_val, phase_val, mass_val, temperature_val)

# ── 내부 유틸 ─────────────────────────────────────────────
func _read_substance(cell: Vector2i) -> int:
	return _substance_store.get_by_cell(cell)

func _read_phase(cell: Vector2i) -> int:
	return _phase_store.get_phase(cell)

func _read_mass(cell: Vector2i) -> int:
	return _mass_store.get_by_index(_grid_index.idx(cell))

func _read_temperature(cell: Vector2i) -> int:
	return _temperature_store.get_by_cell(cell)

func _make_info(cell: Vector2i, substance_val, phase_val: int, mass_val: int, temperature_val: int):
	# 프로젝트에 TileInfo 클래스가 있으면 그걸 사용하고, 없으면 Dictionary로 반환.
	if ClassDB.class_exists("TileInfo"):
		#var info = TileInfo.new()
		#info.cell = cell
		## 필요 최소 필드만 채움 (표시는 패널에서)
		## - info.phase 같은 필드가 없다면, info.set("phase", phase_val)로 유연하게 넣어둘 수도 있음.
		#if info.has_method("set"):
			## TileInfo에 phase 프로퍼티가 정의되어 있지 않은 경우 대비
			#info.set("phase", phase_val)
		#else:
			## 일반적인 경우: info.phase가 프로퍼티로 정의되어 있을 때
			#info.phase = phase_val
		#return info
		return # 작동 목적 임시 주석처리, 추후 처분 결정 필요
	else:
		return {
			"cell": cell,
			"substance": substance_val,
			"phase": phase_val,
			"mass": mass_val,
			"temperature": temperature_val,
		}
