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

# --- ONI-like pressure params ---
const CAP: float = 1.0         # 기준 용량(정상 수위)
const MAX_CAP: float = 1.6     # 허용 과충전 한계 (압축 근사)
const K_COMP: float = 50.0     # 압축 압력 강도 (m > CAP일 때 급격히 압력 증가)
const LAMBDA: float = 0.8      # 수두 전파 감쇠(위→아래 누적)
const G_HYDRO: float = 1.0     # 수두 스케일

const B_DOWN: float = 0.6      # 방향별 전도율(아래 우선)
const B_SIDE: float = 0.25
const B_UP: float = 0.15

const FLOW_CAP_DOWN: float = 0.5  # 틱당 유량 상한(안정화용)
const FLOW_CAP_SIDE: float = 0.25
const FLOW_CAP_UP: float = 0.2

const VISC: float = 0.9        # 점성 감쇠(진동 억제)
const EPS_H: float = 0.01      # 미세 압력차 무시 임계치
const SUBSTEPS: int = 3        # 한 틱 내 서브스텝 반복(빠른 평형화)

var head: PackedFloat32Array = PackedFloat32Array()     # 누적 수두 H
var pressure: PackedFloat32Array = PackedFloat32Array() # 최종 압력 P = Ph + Pc
var _tick_parity: int = 0                               # 체커보드 스윕용

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
    head = PackedFloat32Array(); head.resize(total)
    pressure = PackedFloat32Array(); pressure.resize(total)
    for i in total:
        if amounts[i] > 0.0:
            _mark_dirty(i)

# ONI-like pressure model
func _recompute_head_and_pressure() -> void:
    var w := size.x
    var h := size.y

    # Column-wise hydrostatic head accumulation
    for x in w:
        var H := 0.0
        for y in h:
            var idx := x + y * w
            if solid_mask[idx] != 0:
                head[idx] = 0.0
                H = 0.0
                continue
            H = amounts[idx] + LAMBDA * H
            head[idx] = H

    # Pressure = hydrostatic + compression
    for i in pressure.size():
        if solid_mask[i] != 0:
            pressure[i] = 0.0
            continue
        var over := max(amounts[i] - CAP, 0.0)
        var p_h := G_HYDRO * head[i]
        var p_c := K_COMP * over
        pressure[i] = p_h + p_c

# ONI-like pressure model
func _flow_once(idx_from: int, idx_to: int, coeff: float, flow_cap: float, local_from_amt: float) -> float:
    if coeff <= 0.0 or flow_cap <= 0.0:
        return 0.0
    if solid_mask[idx_to] != 0:
        return 0.0

    var dP := pressure[idx_from] - pressure[idx_to]
    if dP <= EPS_H:
        return 0.0

    var base_flow := coeff * dP
    if base_flow <= 0.0:
        return 0.0

    var room := MAX_CAP - amounts[idx_to]
    if room <= EPS:
        return 0.0

    var f := min(base_flow, local_from_amt, room, flow_cap)
    f *= VISC
    if f <= EPS:
        return 0.0

    _add_delta(idx_from, -f)
    _add_delta(idx_to, +f)
    _mark_next_dirty(idx_from)
    _mark_next_dirty(idx_to)
    return f

# ONI-like pressure model
func tick_liquid(_dt: float) -> void:
    if _dirty.size() == 0:
        return

    var w := size.x
    var h := size.y

    for s in SUBSTEPS:
        for i in _delta.size():
            _delta[i] = 0.0
        _changed = PackedInt32Array()
        _changed_flags.fill(0)
        _next_dirty = PackedInt32Array()
        _next_flags.fill(0)

        _recompute_head_and_pressure()
        _tick_parity ^= 1

        for di in _dirty.size():
            var idx: int = _dirty[di]
            if solid_mask[idx] != 0:
                continue
            var a := amounts[idx]
            if a <= EPS:
                continue

            var x: int = idx % w
            var y: int = idx / w

            # ↓ 아래
            if y + 1 < h:
                a -= _flow_once(idx, idx + w, B_DOWN, FLOW_CAP_DOWN, a)
                if a <= EPS:
                    continue

            # ←/→ 좌우 (체커보드 우선순위)
            var left_first := ((x + y + _tick_parity) & 1) == 0
            if x > 0 and a > EPS:
                if left_first:
                    a -= _flow_once(idx, idx - 1, B_SIDE, FLOW_CAP_SIDE, a)
            if x + 1 < w and a > EPS:
                a -= _flow_once(idx, idx + 1, B_SIDE, FLOW_CAP_SIDE, a)
            if x > 0 and a > EPS and not left_first:
                a -= _flow_once(idx, idx - 1, B_SIDE, FLOW_CAP_SIDE, a)

            # ↑ 위 (압축으로 위로도 밀림)
            if y > 0 and a > EPS:
                a -= _flow_once(idx, idx - w, B_UP, FLOW_CAP_UP, a)

        # Apply deltas and clamp
        for ci in _changed.size():
            var idc: int = _changed[ci]
            var new_amt: float = clamp(amounts[idc] + _delta[idc], 0.0, MAX_CAP)
            if abs(new_amt - amounts[idc]) > EPS:
                amounts[idc] = (new_amt if new_amt > EPS else 0.0)
                _mark_next_dirty(idc)
                var x2: int = idc % w
                var y2: int = idc / w
                if x2 > 0: _mark_next_dirty(idc - 1)
                if x2 + 1 < w: _mark_next_dirty(idc + 1)
                if y2 > 0: _mark_next_dirty(idc - w)
                if y2 + 1 < h: _mark_next_dirty(idc + w)

        _dirty = _next_dirty
        _dirty_flags = _next_flags
        _next_dirty = PackedInt32Array()
        _next_flags = PackedByteArray(); _next_flags.resize(amounts.size()); _next_flags.fill(0)

        if _dirty.size() == 0:
            break

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
