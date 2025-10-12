extends Node
class_name Mining

# ─────────────────────────────────────────────────────────
# 외부 연결(노드 경로)
@export var tile_change_path: NodePath
@export var ground_item_registry_path: NodePath

# 채굴 수치
@export var mining_power_per_click_hp: float = 2.0              # 클릭 1회당 HP 피해량
@export var drop_merge_temperature_tolerance_K: float = 5.0     # 드롭 병합 시 온도 허용차

# 선택: 고체만 채굴 허용(경고용)
@export var require_solid_phase: bool = true

# 내부 참조
var _durability_store: DurabilityStore
var _tile_change: TileChange
var _item_registry
@export var _durability : Durability

# 선택: 현재 클릭 중인지(홀드 채굴 확장용, 지금은 미사용)
var _is_mining_in_progress: bool = false

# ─────────────────────────────────────────────────────────
# 생명주기
func setup(data: DataLayer) -> void:
	_durability_store = data.durability

	# Durability 이벤트 수신(문턱 드롭, 파괴)
	# 예상 시그널:
	#   threshold_chunk_requested(cell: Vector2i, chunk_mass_kg: float, threshold_value: float)
	#   break_requested(cell: Vector2i)
	if _durability.has_signal("threshold_chunk_requested"):
		_durability.threshold_chunk_requested.connect(_on_threshold_chunk_requested)
	if _durability.has_signal("break_requested"):
		_durability.break_requested.connect(_on_break_requested)

func _ready() -> void:
	_tile_change = get_node(tile_change_path)
	_item_registry = get_node(ground_item_registry_path)

	# TileChange 이벤트 수신(실제 질량 제거 결과)
	# 예상 시그널:
	#   mass_harvested(cell: Vector2i, material_sid: int, mass_kg: float, temperature_K: float, reason: StringName)
	if _tile_change.has_signal("mass_harvested"):
		_tile_change.mass_harvested.connect(_on_mass_harvested)

# ─────────────────────────────────────────────────────────
# 입력 처리: 클릭 1회 → 피해 1회
func _on_tool_manager_request_mine(cell: Vector2i) -> void:
	# Durability가 HP만 관리하므로 여기서는 피해만 가한다.
	# 하이브리드(구간 드롭) 계산과 브레이크 여부 판단은 Durability가 수행.
	if _durability and _durability.has_method("apply_damage"):
		_durability.apply_damage(cell, mining_power_per_click_hp)
	else:
		push_warning("[Mining] Durability.apply_damage not found")

# ─────────────────────────────────────────────────────────
# Durability → Mining: 문턱 구간 드롭 요청
func _on_threshold_chunk_requested(cell: Vector2i, chunk_mass_kg: float, threshold_value: float) -> void:
	# 이 시점에서 실제 타일 질량이 충분하지 않을 수 있으므로
	# TileChange가 내부에서 클램프(min(current_mass)) 처리하도록 맡긴다.
	if chunk_mass_kg <= 0.0:
		return
	if _tile_change and _tile_change.has_method("harvest_mass_from_cell"):
		_tile_change.harvest_mass_from_cell(cell, chunk_mass_kg, &"mine")
	else:
		push_warning("[Mining] TileChange.harvest_mass_from_cell not found")

# Durability → Mining: 파괴(HP 0) 요청
func _on_break_requested(cell: Vector2i) -> void:
	# 남은 질량을 전부 떼어내고, 타일이 0이 되면 TileChange가 진공으로 치환한다.
	# 남은 질량 전부를 알기 위해서는 TileChange가 내부에서 자동 처리하도록,
	# 충분히 큰 값을 넘겨 '싹쓸이'하도록 한다.
	if _tile_change and _tile_change.has_method("harvest_mass_from_cell"):
		_tile_change.harvest_mass_from_cell(cell, 1_000_000.0, &"mine") # effectively "take all"
	else:
		push_warning("[Mining] TileChange.harvest_mass_from_cell not found for break")

# ─────────────────────────────────────────────────────────
# TileChange → Mining: 실제 질량 제거 결과(드롭 생성)
func _on_mass_harvested(cell: Vector2i, material_sid: int, mass_kg: float, temperature_K: float, reason: StringName) -> void:
	if reason != &"mine":
		return
	if mass_kg <= 0.0:
		return
	if not _item_registry:
		push_warning("[Mining] GroundItemRegistry not assigned")
		return

	# 드롭 생성/병합
	if _item_registry.has_method("add_or_merge"):
		# material_sid를 문자열로 쓸지 정수로 쓸지는 레지스트리 구현에 맞춰 통일
		_item_registry.add_or_merge(cell, str(material_sid), mass_kg, temperature_K, drop_merge_temperature_tolerance_K)
	else:
		push_warning("[Mining] GroundItemRegistry.add_or_merge not found")

# ─────────────────────────────────────────────────────────
# (옵션) 유틸: 고체만 채굴 허용 체크(나중에 실제 phase 검사 연결)
func _is_cell_mineable(cell: Vector2i) -> bool:
	if not require_solid_phase:
		return true
	# 실제 구현에서는 DataLayer에서 phase를 조회해 검사.
	# Mining은 DataLayer를 직접 만지지 않는 원칙이라면,
	# Durability 또는 TileChange 쪽에서 phase 검사를 처리하는 편이 좋다.
	return true
