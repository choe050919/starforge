extends Node
class_name Liquid

# Liquid distribution and simple flow logic.

var size: Vector2i
var amounts: PackedFloat32Array = PackedFloat32Array()
var springs: PackedVector2Array = PackedVector2Array()
var solid_mask: PackedByteArray = PackedByteArray()

var _delta: PackedFloat32Array
var _dirty: PackedInt32Array
var _dirty_flags: PackedByteArray
var _next_dirty: PackedInt32Array
var _next_flags: PackedByteArray
var _changed: PackedInt32Array
var _changed_flags: PackedByteArray

const EPS: float = 0.0001

func setup(initial_amounts: PackedFloat32Array, spring_cells: PackedVector2Array, grid_size: Vector2i, solid: PackedByteArray) -> void:
	# Store liquid distribution, spring positions and solid mask
	size = grid_size
	amounts = PackedFloat32Array(initial_amounts)
	springs = PackedVector2Array(spring_cells)
	solid_mask = PackedByteArray(solid)
	var total := size.x * size.y
	_delta = PackedFloat32Array(); _delta.resize(total)
	_dirty = PackedInt32Array()
	_next_dirty = PackedInt32Array()
	_changed = PackedInt32Array()
	_dirty_flags = PackedByteArray(); _dirty_flags.resize(total); _dirty_flags.fill(0)
	_next_flags = PackedByteArray(); _next_flags.resize(total); _next_flags.fill(0)
	_changed_flags = PackedByteArray(); _changed_flags.resize(total); _changed_flags.fill(0)
	for i in total:
		if amounts[i] > 0.0:
			_mark_dirty(i)

func tick_liquid(_dt: float) -> void:
	# Process cells marked dirty and update liquid amounts atomically
	if _dirty.size() == 0:
		return
	for i in _delta.size():
		_delta[i] = 0.0
	_changed = PackedInt32Array()
	_changed_flags.fill(0)
	_next_dirty = PackedInt32Array()
	_next_flags.fill(0)

	var w := size.x
	var h := size.y
	for di in _dirty.size():
		var idx: int = _dirty[di]
		var amt: float = amounts[idx]
		if amt <= 0.0:
			continue
		var x: int = idx % w
		var y: int = idx / w
		var moved := false

		var idx_down: int = idx + w
		if y + 1 < h and solid_mask[idx_down] == 0:
			var cap: float = 1.0 - amounts[idx_down]
			if cap > 0.0:
				var flow: float = min(amt, cap)
				if flow > 0.0:
					_add_delta(idx, -flow)
					_add_delta(idx_down, flow)
					_mark_next_dirty(idx)
					_mark_next_dirty(idx_down)
					moved = true
		if not moved:
			if x > 0 and solid_mask[idx - 1] == 0:
				var diff_l: float = (amt - amounts[idx - 1]) * 0.5
				if diff_l > 0.0:
					var flow_l: float = min(diff_l, amt)
					flow_l = min(flow_l, 1.0 - amounts[idx - 1])
					if flow_l > 0.0:
						_add_delta(idx, -flow_l)
						_add_delta(idx - 1, flow_l)
						_mark_next_dirty(idx)
						_mark_next_dirty(idx - 1)
			if x + 1 < w and solid_mask[idx + 1] == 0:
				var diff_r: float = (amt - amounts[idx + 1]) * 0.5
				if diff_r > 0.0:
					var flow_r: float = min(diff_r, amt)
					flow_r = min(flow_r, 1.0 - amounts[idx + 1])
					if flow_r > 0.0:
						_add_delta(idx, -flow_r)
						_add_delta(idx + 1, flow_r)
						_mark_next_dirty(idx)
						_mark_next_dirty(idx + 1)

	for ci in _changed.size():
		var idx: int = _changed[ci]
		var new_amt: float = clamp(amounts[idx] + _delta[idx], 0.0, 1.0)
		if abs(new_amt - amounts[idx]) > EPS:
			amounts[idx] = new_amt
			_mark_next_dirty(idx)
			var x2: int = idx % w
			var y2: int = idx / w
			if x2 > 0:
				_mark_next_dirty(idx - 1)
			if x2 + 1 < w:
				_mark_next_dirty(idx + 1)
			if y2 > 0:
				_mark_next_dirty(idx - w)
			if y2 + 1 < h:
				_mark_next_dirty(idx + w)

	_dirty = _next_dirty
	_dirty_flags = _next_flags
	_next_dirty = PackedInt32Array()
	_next_flags = PackedByteArray(); _next_flags.resize(amounts.size()); _next_flags.fill(0)

func get_amounts() -> PackedFloat32Array:
	return amounts

func on_tile_destroyed(cell: Vector2i, from_tile: int, reason: StringName) -> void:
	if size == Vector2i.ZERO:
		return
	var idx: int = _cell_to_index(cell)
	if idx < 0 or idx >= solid_mask.size():
		return
	solid_mask[idx] = 0
	_mark_dirty(idx)
	_mark_dirty_neighbors(idx)

func on_tile_replaced(cell: Vector2i, from_tile: int, to_tile: int, reason: StringName) -> void:
	if size == Vector2i.ZERO:
		return
	var idx: int = _cell_to_index(cell)
	if idx < 0 or idx >= solid_mask.size():
		return
	solid_mask[idx] = int(to_tile != 0)
	_mark_dirty(idx)
	_mark_dirty_neighbors(idx)

func _mark_dirty_neighbors(idx: int) -> void:
	var w := size.x
	var h := size.y
	var x: int = idx % w
	var y: int = idx / w
	if x > 0:
		_mark_dirty(idx - 1)
	if x + 1 < w:
		_mark_dirty(idx + 1)
	if y > 0:
		_mark_dirty(idx - w)
	if y + 1 < h:
		_mark_dirty(idx + w)

func _mark_dirty(idx: int) -> void:
	if _dirty_flags[idx] == 0:
		_dirty_flags[idx] = 1
		_dirty.append(idx)

func _mark_next_dirty(idx: int) -> void:
	if _next_flags[idx] == 0:
		_next_flags[idx] = 1
		_next_dirty.append(idx)

func _record_change(idx: int) -> void:
	if _changed_flags[idx] == 0:
		_changed_flags[idx] = 1
		_changed.append(idx)

func _add_delta(idx: int, v: float) -> void:
	_delta[idx] += v
	_record_change(idx)

func _cell_to_index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x
