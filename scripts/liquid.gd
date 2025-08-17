extends Node
class_name Liquid


# 상수 추가(파일 상단)
const UNDER_RELAX: float = 0.5   # 0.3~0.7에서 튜닝
# 추가 상수 (파일 상단)
const GRAV_Z: float = 1.0   # 고도 항 가중치 (0.5~2.0 범위에서 튜닝)
# 추가: 전역 상수
const G_BIAS: float = 1.0   # 중력 바이어스(아래로 흐르게). 필요시 0.5~2.0에서 조정.
const OUTFLOW_FRAC: float = 0.5  # 한 틱에 최대 50%만 뺌
# 상단에 상수 추가
const SURFACE_EPS: float = 0.015    # 타일 용량의 ~1% 이하는 '공기 취급'
const DIRTY_EPS:   float = 0.002   # 이보다 작은 변화는 무시


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

const B_DOWN: float = 0.7      # 방향별 전도율(아래 우선) # 0.6 → 0.7 (아래 전도 강화)
const B_SIDE: float = 0.15 # 0.25 → 0.15 (옆 전도 약화)
const B_UP: float = 0.00 # 위 전도 잠정 금지 (나중에 0.02~0.05로 복구)

const FLOW_CAP_DOWN: float = 0.4  # 틱당 유량 상한(안정화용) # 0.5 → 0.4
const FLOW_CAP_SIDE: float = 0.15 # 0.25 → 0.15
const FLOW_CAP_UP: float = 0.05 # 0.2  → 0.05

const VISC: float = 0.9        # 점성 감쇠(진동 억제)
const EPS_H: float = 0.05      # 미세 압력차 무시 임계치 # 0.01 → 0.05 (압력차 문턱)
const SUBSTEPS: int = 1        # 한 틱 내 서브스텝 반복(빠른 평형화) # 3 → 1 (발산/점멸 줄이기 위해 우선 낮춤)

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

		var over = max(amounts[i] - CAP, 0.0)
		var p_h := G_HYDRO * head[i]
		var p_c = K_COMP * over

		# 표면 완충: 아주 얇은 층은 압력 약화
		if amounts[i] < SURFACE_EPS * 4.0:
			p_h *= 0.25
			p_c *= 0.25

		# 기존 스무딩 유지(줄무늬 억제)
		pressure[i] = lerp(pressure[i], p_h + p_c, 0.4)

# _flow_once 시그니처/본문 교체 (dx,dy 안 써도 됨)
func _flow_once(idx_from: int, idx_to: int, coeff: float, flow_cap: float, local_from_amt: float) -> float:
	local_from_amt = min(local_from_amt, OUTFLOW_FRAC * amounts[idx_from])
	if coeff <= 0.0 or flow_cap <= 0.0:
		return 0.0
	if solid_mask[idx_to] != 0:
		return 0.0

	# 총 포텐셜 = 압력 + 고도항(-y)
	var y_from := _y_of(idx_from)
	var y_to   := _y_of(idx_to)
	var phi_from := pressure[idx_from] + GRAV_Z * float(-y_from)
	var phi_to   := pressure[idx_to]   + GRAV_Z * float(-y_to)
	var dphi := phi_from - phi_to
	# _flow_once 안에서 dphi 계산 후, 위로 흐르는 경우 추가 문턱
	# 위로 가는 이동인지 검사 (to가 from보다 y가 작음)
	var going_up := y_to < y_from
	if going_up and dphi <= (EPS_H * 2.0):
		return 0.0
	if dphi <= EPS_H:
		return 0.0

	var base_flow := coeff * dphi
	if base_flow <= 0.0:
		return 0.0

	var room := MAX_CAP - amounts[idx_to]
	if room <= EPS:
		return 0.0

	var f = min(base_flow, local_from_amt, room, flow_cap)
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
		#_tick_parity ^= 1

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
			#var left_first := ((x + y + _tick_parity) & 1) == 0
			var left_first := ((x + y) & 1) == 0   # parity 없이 고정
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

			var raw_new: float = amounts[idc] + _delta[idc]

			# --- 윗줄 보수 모드 선택 ---
			var y2 := idc / size.x
			var local_under := UNDER_RELAX
			var local_delta_eps := DIRTY_EPS
			if y2 == 0:
				local_under = min(0.35, UNDER_RELAX)   # 윗줄: 변화를 더 천천히
				local_delta_eps = max(0.003, DIRTY_EPS)# 윗줄: 더 작은 변화는 무시

			# --- 언더릴랙스 적용 ---
			var relaxed: float = amounts[idc] + local_under * (raw_new - amounts[idc])

			# --- 클램프 & 표면 스냅 ---
			var new_amt: float = clamp(relaxed, 0.0, MAX_CAP)
			if new_amt < SURFACE_EPS:
				if amounts[idc] != 0.0:
					amounts[idc] = 0.0   # 아주 얇은 막은 0으로 스냅
				continue                 # 이웃 dirty 전파 안 함 (미세 깜빡임 차단)

			# --- 변화량 문턱 체크 ---
			if abs(new_amt - amounts[idc]) > local_delta_eps:
				amounts[idc] = new_amt
				_mark_next_dirty(idc)
				var x2 := idc % size.x
				var y2b := idc / size.x
				if x2 > 0: _mark_next_dirty(idc - 1)
				if x2 + 1 < size.x: _mark_next_dirty(idc + 1)
				if y2b > 0: _mark_next_dirty(idc - size.x)
				if y2b + 1 < size.y: _mark_next_dirty(idc + size.x)
			# else: 변화가 너무 작으면 스킵 → 깜빡임 감소

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


# 유틸
func _y_of(i:int) -> int: return i / size.x
