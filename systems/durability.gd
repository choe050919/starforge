extends Node
class_name Durability

# ─────────────────────────────────────────────────────────
# 시그널
signal threshold_chunk_requested(cell: Vector2i, chunk_mass_kg: float, threshold_value: float)
signal break_requested(cell: Vector2i)

# ─────────────────────────────────────────────────────────
# 외부 참조
var _data: DataLayer
var _index: GridIndex

# ─────────────────────────────────────────────────────────
# Config
## 문턱 비율(내림차순) — 기본: 80/60/40/20/0%
@export var threshold_ratios: PackedFloat32Array = PackedFloat32Array([0.8, 0.6, 0.4, 0.2, 0.0])

## 디버그 로그
@export var debug_log: bool = false

# Epsilon / Snap
const EPS := 1e-6
const MASS_SNAP_KG := 1e-6

func _snap_mass_kg(x: float) -> float:
	return floor((x / MASS_SNAP_KG) + 0.5) * MASS_SNAP_KG

# ─────────────────────────────────────────────────────────
# Preprocessed thresholds (descending, clamped)
var _thresholds: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	# 정렬·정합성 보정
	var arr: Array = []
	for i in threshold_ratios.size():
		arr.append(float(threshold_ratios[i]))
	arr.sort()
	arr.reverse()
	if arr.is_empty() or abs(arr.back() - 0.0) > EPS:
		arr.append(0.0)
	_thresholds = PackedFloat32Array(arr)
	if debug_log:
		print("[Dur] thresholds(desc) = ", _thresholds)

# ─────────────────────────────────────────────────────────
# Public API

func setup(data: DataLayer) -> void:
	_data = data
	_index = data.index
	if debug_log:
		print("[Dur] setup done. grid=", _index.size)

## 채굴/피해 적용(HP 단위)
func apply_damage(cell: Vector2i, amount_hp: float) -> void:
	if amount_hp <= 0.0:
		return
	if not _index.in_bounds_cell(cell):
		return
	
	# DurabilityStore에서 현재 상태 읽기
	if not _data.durability.is_initialized(cell):
		if debug_log:
			print("[Dur] apply_damage ignored: not initialized cell=", cell)
		return
	
	var max_hp := _data.durability.get_max_hp(cell)
	if max_hp <= EPS:
		if debug_log:
			print("[Dur] apply_damage ignored: max_hp≈0 cell=", cell)
		return
	
	var hp_prev := _data.durability.get_hp(cell)
	var hp_new: float = max(0.0, hp_prev - amount_hp)
	
	if debug_log:
		print("[Dur] dmg cell=", cell,
			" amount=", amount_hp,
			" hp ", hp_prev, "→", hp_new, " / max=", max_hp)
	
	# DataLayer API를 통해 HP 변경
	_data.set_cell_with_spec(cell, {"hp": hp_new}, &"durability")
	
	# 문턱 처리
	_process_threshold_cross(cell, hp_prev, hp_new, max_hp)
	
	# 파괴 처리
	if hp_new <= EPS:
		if debug_log:
			print("[Dur] break emit cell=", cell)
		break_requested.emit(cell)

## UI/디버깅용 Getter (DurabilityStore로 위임)
func get_hp(cell: Vector2i) -> float:
	return _data.durability.get_hp(cell)

func get_max_hp(cell: Vector2i) -> float:
	return _data.durability.get_max_hp(cell)

func get_hp_ratio(cell: Vector2i) -> float:
	return _data.durability.get_hp_ratio(cell)

# ─────────────────────────────────────────────────────────
# Internal

func _process_threshold_cross(cell: Vector2i, hp_prev: float, hp_new: float, max_hp: float) -> void:
	if max_hp <= EPS:
		return
	
	var ratio_prev: float = clamp(hp_prev / max_hp, 0.0, 1.0)
	var ratio_new: float = clamp(hp_new / max_hp, 0.0, 1.0)
	var next_i := _data.durability.get_next_threshold_index(cell)
	var initial_mass_kg := _data.durability.get_initial_mass_kg(cell)
	
	if debug_log:
		print("[Dur] threshold_cross: cell=", cell, " hp ", hp_prev, "→", hp_new, 
			  " ratio ", ratio_prev, "→", ratio_new, " next_i=", next_i, 
			  " initial_mass=", initial_mass_kg)
	
	while next_i < _thresholds.size():
		var t := _thresholds[next_i]
		
		if ratio_new <= t + EPS:
			var t_prev := 1.0 if next_i == 0 else _thresholds[next_i - 1]
			var quota_ratio: float = max(0.0, t_prev - t)
			var chunk_mass := _snap_mass_kg(initial_mass_kg * quota_ratio)
			
			print("[Dur] EMIT threshold: t=", t, " t_prev=", t_prev, 
				  " quota=", quota_ratio, " chunk=", chunk_mass, "kg")
			
			if chunk_mass > MASS_SNAP_KG:
				threshold_chunk_requested.emit(cell, chunk_mass, t)
			
			next_i += 1
			_data.durability.set_next_threshold_index(cell, next_i)
		else:
			break
