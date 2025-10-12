extends Node2D
class_name ItemsRoot

@export var ground_item_registry_path: NodePath
@export var cell_pixel_size: Vector2i = Vector2i(32, 32)
@export var draw_label: bool = true
@export var z_index_base: int = 50

var _registry: GroundItemRegistry
# 셀별로 붙여둔 뷰 노드 목록(리빌드시 정리)
var _cell_nodes: Dictionary = {} # key:int -> Array[Node2D]

func _ready() -> void:
	if ground_item_registry_path != NodePath():
		_registry = get_node_or_null(ground_item_registry_path)
	if _registry == null:
		push_warning("[ItemsRoot] GroundItemRegistry not assigned")
		return

	# 신호 연결 (셀 단위 리빌드)
	_registry.stack_created.connect(_on_stack_event)
	_registry.stack_updated.connect(_on_stack_event)
	_registry.stack_removed.connect(_on_stack_event)

func _on_stack_event(cell: Vector2i, _stack_index: int, _sid: int, _a = null, _b = null) -> void:
	_rebuild_cell(cell)

func _rebuild_cell(cell: Vector2i) -> void:
	var key := _key(cell)

	# 기존 노드 제거
	if _cell_nodes.has(key):
		for n in _cell_nodes[key]:
			if is_instance_valid(n):
				n.queue_free()
		_cell_nodes.erase(key)

	# 최신 스택 조회
	if _registry == null:
		return
	var stacks: Array = _registry.get_stacks_in_cell(cell)
	if stacks.is_empty():
		return

	# 생성
	var list: Array[Node2D] = []
	var base_pos := _cell_to_world_center(cell)

	# 여러 스택이 한 셀에 있으면 약간씩 흩뿌리기
	var offsets := _ring_offsets(max(1, stacks.size()))

	for i in stacks.size():
		var s: Dictionary = stacks[i]
		var sid := int(s.get("material_sid", 0))
		var mass_kg := float(s.get("mass_kg", 0.0))
		var temp_K := float(s.get("temperature_K", 293.15))

		var v := GroundItemView.new()
		add_child(v)
		v.z_index = z_index_base
		v.position = base_pos + offsets[i]
		v.show_label = draw_label
		v.set_data(sid, mass_kg, temp_K)

		list.append(v)

	_cell_nodes[key] = list

# ── 유틸 ─────────────────────────────────────────────────────────────────────
func _cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_pixel_size.x + cell_pixel_size.x * 0.5,
				   cell.y * cell_pixel_size.y + cell_pixel_size.y * 0.5)

static func _key(cell: Vector2i) -> int:
	return (cell.y << 16) | (cell.x & 0xFFFF)

func _ring_offsets(n: int) -> Array[Vector2]:
	# n=1이면 (0,0). 그 외엔 작은 원형 배치
	var out: Array[Vector2] = []
	if n <= 1:
		out.append(Vector2.ZERO)
		return out
	var r := 6.0
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector2(cos(a), sin(a)) * r)
	return out
