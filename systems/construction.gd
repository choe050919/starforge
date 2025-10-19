extends Node
class_name Construction

# ── 외부 참조 ──────────────────────────────────────────────────────
@export var player_path: NodePath
@export var tile_change_path: NodePath

var _player: Player = null
var _tile_change: TileChange = null
var _data: DataLayer = null

# ── 건설 비용 (mg 단위) ────────────────────────────────────────────
const TILE_COST_MG := 1_000_000      # 타일 1개 = 1kg = 1,000,000mg
const LADDER_COST_MG := 100_000      # 사다리 1개 = 0.1kg = 100,000mg

# ── 사다리 SID ─────────────────────────────────────────────────────
const LADDER_SID := 50001

# ── 배치 범위 ──────────────────────────────────────────────────────
@export var placement_reach_cells: int = 3  # 플레이어 근처 3칸

# ── 디버그 ─────────────────────────────────────────────────────────
@export var debug_log: bool = false

# ══════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════

func setup(data: DataLayer) -> void:
	_data = data
	if debug_log:
		print("[Construction] Setup complete")

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
		if _player == null:
			push_error("[Construction] Player node not found at path: ", player_path)
	
	if tile_change_path != NodePath():
		_tile_change = get_node_or_null(tile_change_path)
		if _tile_change == null:
			push_error("[Construction] TileChange node not found at path: ", tile_change_path)
	
	if debug_log:
		print("[Construction] References acquired - Player: ", _player != null, ", TileChange: ", _tile_change != null)

# ══════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════

## 타일 배치 (플레이어가 들고 있는 재료 사용)
func place_tile(cell: Vector2i, material_sid: int) -> bool:
	if not _validate_references():
		return false
	
	# 1. 배치 가능 검증
	if not can_place(cell):
		if debug_log:
			print("[Construction] Cannot place at cell=", cell, " (not vacuum or out of range)")
		return false
	
	# 2. 플레이어 재료 확인
	if not _player.can_afford_material(material_sid, TILE_COST_MG):
		if debug_log:
			print("[Construction] Insufficient material: need ", TILE_COST_MG, "mg of SID=", material_sid)
		return false
	
	# 3. 재료 소모
	if not _player.consume_material(TILE_COST_MG):
		push_error("[Construction] consume_material failed unexpectedly")
		return false
	
	# 4. 타일 배치
	_tile_change.replace_cell(cell, material_sid, &"construct")
	
	if debug_log:
		print("[Construction] Tile placed: cell=", cell, " sid=", material_sid)
	
	return true

## 사다리 배치 (고정 SID)
func place_ladder(cell: Vector2i) -> bool:
	if not _validate_references():
		return false
	
	# 1. 배치 가능 검증
	if not can_place(cell):
		if debug_log:
			print("[Construction] Cannot place ladder at cell=", cell, " (not vacuum or out of range)")
		return false
	
	# 2. 플레이어가 사다리 재료를 들고 있는지 확인
	# (사다리는 특수 재료이므로 LADDER_SID를 들고 있어야 함)
	if not _player.can_afford_material(LADDER_SID, LADDER_COST_MG):
		if debug_log:
			print("[Construction] Insufficient ladder material: need ", LADDER_COST_MG, "mg of SID=", LADDER_SID)
		return false
	
	# 3. 재료 소모
	if not _player.consume_material(LADDER_COST_MG):
		push_error("[Construction] consume_material failed unexpectedly")
		return false
	
	# 4. 사다리 배치
	_tile_change.replace_cell(cell, LADDER_SID, &"construct")
	
	if debug_log:
		print("[Construction] Ladder placed: cell=", cell)
	
	return true

## 배치 가능 여부 확인
func can_place(cell: Vector2i) -> bool:
	if _data == null:
		return false
	
	# 1. 범위 내인지 확인
	if not _is_in_placement_range(cell):
		return false
	
	# 2. 진공 셀인지 확인
	if not _is_vacuum(cell):
		return false
	
	return true

# ══════════════════════════════════════════════════════════════════
# Internal Helpers
# ══════════════════════════════════════════════════════════════════

func _validate_references() -> bool:
	if _player == null:
		push_warning("[Construction] Player reference is null")
		return false
	
	if _tile_change == null:
		push_warning("[Construction] TileChange reference is null")
		return false
	
	if _data == null:
		push_warning("[Construction] DataLayer reference is null")
		return false
	
	return true

func _is_in_placement_range(cell: Vector2i) -> bool:
	if _player == null:
		return false
	
	var player_cell := _world_to_cell(_player.global_position)
	var dx: int = abs(cell.x - player_cell.x)
	var dy: int = abs(cell.y - player_cell.y)
	var dist: int = max(dx, dy)
	
	return dist <= placement_reach_cells

func _is_vacuum(cell: Vector2i) -> bool:
	if _data == null or _data.phase == null:
		return false
	
	if not _data.index.in_bounds_cell(cell):
		return false
	
	var phase := _data.phase.get_phase(cell)
	return phase == PhaseStore.Phase.VACUUM

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	# Player에서 cell_size를 가져오거나, 고정값 사용
	var cell_size := Vector2(32, 32)  # 기본값
	
	if _player != null and _player.has_method("_world_to_cell"):
		# Player의 메서드가 있다면 사용 (private이라 직접 호출 불가)
		# 대신 직접 계산
		pass
	
	return Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))
