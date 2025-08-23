extends RefCounted
class_name TileInfoProvider
## 한 셀의 표시용 정보를 묶어서 돌려주는 조회기.

# ── 의존성 ────────────────────────────────────────────────
var _phase_store: PhaseStore
var _grid_index: GridIndex

func setup(ps: PhaseStore, gi: GridIndex = null) -> void:
	_phase_store = ps
	_grid_index = gi

func is_ready() -> bool:
	if not _phase_store.has_method("get_phase"):
		push_warning("[TileInfoProvider] Missing method: PhaseStore.get_phase")
		return false
	else: return true

# ── 조회 API ──────────────────────────────────────────────
func query(cell: Vector2i):
	# 반환: TileInfo(권장) 또는 Dictionary(대체). 패널이 enum→문자열 매핑을 맡는다.
	if not is_ready():
		return _make_info(cell, UNKNOWN_PHASE())

	if _grid_index and _grid_index.has_method("in_bounds") and not _grid_index.in_bounds(cell):
		push_warning("[TileInfoProvider] cell is not in bounds")
		return _make_info(cell, UNKNOWN_PHASE())

	var phase_val := _read_phase(cell)
	return _make_info(cell, phase_val)

# ── 내부 유틸 ─────────────────────────────────────────────
func _read_phase(cell: Vector2i) -> int:
	# PhaseStore가 enum을 반환한다고 가정. 경계 밖은 PhaseStore가 알아서 처리하거나 UNKNOWN으로.
	var p := UNKNOWN_PHASE()
	if _phase_store and _phase_store.has_method("get_phase"):
		p = int(_phase_store.get_phase(cell))
	return p

func UNKNOWN_PHASE() -> int:
	# 프로젝트 enum에 sentinel이 없다면 -1을 UNKNOWN으로 사용
	return -1

func _make_info(cell: Vector2i, phase_val: int):
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
			"phase": phase_val
		}
