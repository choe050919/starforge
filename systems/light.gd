## Light.gd
## -------------------------------------------------------------------
## "항성광"을 격자에 투사해 각 셀의 복사조도(W/m²)를 계산/기록하는 시스템.
## - 공기/진공: 감쇠 없이 통과
## - 투광 매질(물/얼음 등): Beer–Lambert (칸당 alpha=exp(-k))로 지수 감쇠
## - 차광 매질(토양/암석 등): 해당 지점에서 칼럼 차단(이하 0)
##
## 설계 포인트
## - 이벤트 드리븐 + 값싼 틱 호출 혼합: 틱마다 호출하지만 변경 없으면 즉시 return
## - 변경 원인: (1) I0(상단 경계광) 변경 → 전장 스케일 곱, (2) 물질 변경 → 해당 칼럼만 재계산
## - 규칙/룰은 SubstanceRuleCache(optical*)에서 얇게 조회
##
## ⚠️ 향후 확장 메모 (Core 분리 여지)
## - 산란/반사/국소광원(에미시브) 등이 도입되면, 계산부를 LightCore로 분리할 수 있음.
extends Node
class_name Light

# ── 설정 ───────────────────────────────────────────────────────────
@export var enabled: bool = true                 ## 시스템 on/off
@export var debug_log: bool = false              ## 디버그 로그 출력 여부
@export var I0_surface_wm2: float = 1000.0       ## 상단 경계에서 주어지는 항성광 (W/m²)
@export var tick_interval: int = 0               ## >0이면 N틱마다 강제 점검, 0이면 항상 점검(변경 없으면 즉시 return)

# ── 의존성 ─────────────────────────────────────────────────────────
var _data: DataLayer                             ## DataLayer 참조(인덱스/스토어 접근)
var _rules: SubstanceRuleCache                   ## 물질별 optical 룰 캐시

# ── 단축 참조(캐시) ───────────────────────────────────────────────
var _index: GridIndex                            ## 그리드 인덱스
var _subs: SubstanceStore                        ## 물질 스토어 (sid)
var _light: LightStore                           ## 복사조도 스토어 (float, W/m²)

# ── 내부 상태 ─────────────────────────────────────────────────────
var _tick_count: int = 0                         ## 틱 카운터(간헐 점검용)
var _has_dirty: bool = true                      ## 더러운 칼럼 존재 플래그(초기 1회 전장 계산 위해 true)
var _dirty_cols: PackedByteArray = PackedByteArray() ## 칼럼 단위 비트셋: size=width, 값=0/1

var _I0_prev: float = 1000.0                     ## 직전 I0 저장
var _I0_scale_pending: float = 1.0               ## I0 변경 누적 스케일 (전장 스케일 곱만으로 반영)

# ── 생명주기/주입 ─────────────────────────────────────────────────
func setup(data: DataLayer, rule_cache: SubstanceRuleCache) -> void:
	## 의존성 주입 + 내부 캐시 세팅
	_data = data
	_rules = rule_cache
	_index = _data.index
	_subs = _data.substance
	_light = _data.light

	if _index == null or _subs == null or _light == null or _rules == null:
		push_error("[Light.setup] missing dependency")

	_I0_prev = I0_surface_wm2
	_ensure_dirty_bitset()

	## DataLayer의 변경 신호를 구독해, 물질/상 변경 시 해당 칼럼만 더티 마킹
	## (프로젝트 시그널: tiles_changed(changed_indices, reason, payload))
	if not _data.is_connected("tiles_changed", Callable(self, "_on_tiles_changed")):
		_data.connect("tiles_changed", Callable(self, "_on_tiles_changed"))

	## 최초 1회 전장 계산을 위해 전 칼럼 더티 처리
	_mark_all_dirty()

# ── 외부 제어 API ─────────────────────────────────────────────────
func set_I0(new_I0: float) -> void:
	## I0(상단 경계광)을 갱신. Beer–Lambert가 선형 스케일을 유지하므로,
	## 전장을 재계산하지 않고 light[] *= (new/old)로 반영 가능.
	new_I0 = max(new_I0, 0.0)
	if new_I0 == _I0_prev:
		return
	if _light == null:
		_I0_prev = new_I0
		return
	var ratio: float = (new_I0 / max(_I0_prev, 0.000001))
	_I0_prev = new_I0
	_I0_scale_pending *= ratio

func mark_columns_dirty(xs: PackedFloat32Array) -> void:
	## 외부에서 특정 x 칼럼들을 더티 처리할 때 사용
	if xs.is_empty():
		return
	_ensure_dirty_bitset()
	for x in xs:
		if x >= 0 and x < _index.size.x:
			_dirty_cols[x] = 1
	_has_dirty = true

func mark_all_dirty() -> void:
	## 전장 재계산 예약
	_mark_all_dirty()

# ── 틱 루틴 ───────────────────────────────────────────────────────
func _on_sim_tick(_dt: float) -> void:
	if debug_log:
		print("[Light] tick: dirty=", _has_dirty, " scale=", _I0_scale_pending)
	if not enabled or _data == null or _index == null:
		return

	if tick_interval > 0:
		_tick_count += 1
		if (_tick_count % tick_interval) != 0 and _I0_scale_pending == 1.0 and not _has_dirty:
			return

	if _I0_scale_pending == 1.0 and not _has_dirty:
		return

	if not _has_dirty and _I0_scale_pending != 1.0:
		_apply_global_scale(_I0_scale_pending)
		_I0_scale_pending = 1.0
		return

	_recompute_dirty_columns(I0_surface_wm2)

	if _I0_scale_pending != 1.0:
		_apply_global_scale(_I0_scale_pending)
		_I0_scale_pending = 1.0

# ── 변경 이벤트 핸들러 ───────────────────────────────────────────
func _on_tiles_changed(changed_indices: PackedInt32Array, reason: StringName, payload: Dictionary) -> void:
	# 물질/상 변경이 있었는지만 판단 (reason 문자열이 아니라 payload 플래그 기준)
	var affects_optics := bool(payload.get("sid_changed", false)) or bool(payload.get("phase_changed", false))
	if not affects_optics:
		return

	if changed_indices.is_empty() or bool(payload.get("full_refresh", false)):
		_mark_all_dirty()
		return

	_ensure_dirty_bitset()
	var w := _index.size.x
	for i in changed_indices:
		var cell := _index.cell(i)
		var x := cell.x
		if x >= 0 and x < w:
			_dirty_cols[x] = 1
	_has_dirty = true

# ── 내부 구현 ────────────────────────────────────────────────────
func _recompute_dirty_columns(I0: float) -> void:
	var w := _index.size.x
	var h := _index.size.y
	if w <= 0 or h <= 0:
		return
	I0 = max(I0, 0.0)

	# 현재 라이트 스냅샷을 가져와서 "수정본"을 만든 뒤 한 번에 교체
	var L_read : PackedFloat32Array = _light.get_raw_read()
	var L_new  := PackedFloat32Array(); L_new.resize(L_read.size())
	for i in L_read.size():
		L_new[i] = L_read[i]

	var sid_r: PackedInt32Array = _subs.get_raw_read()

	for x in w:
		if _dirty_cols.is_empty() or _dirty_cols[x] == 0:
			continue

		var I := I0
		var blocked := false

		for y in h:
			var i := _index.idx(Vector2i(x, y))

			if blocked or I <= 0.0:
				L_new[i] = 0.0
				continue

			var sid := sid_r[i]
			# 룰 조회(기본값: 차광 true, alpha=1.0)
			var transparent := bool(_rules.opt_transparent_by_sid.get(sid, true))
			if not transparent:
				L_new[i] = 0.0
				blocked = true
				continue

			# 현재 셀에 도달한 복사조도 기록
			L_new[i] = I

			# 다음 셀로 진행하며 감쇠
			var alpha := float(_rules.opt_alpha_by_sid.get(sid, 1.0))
			if alpha < 0.0: alpha = 0.0
			elif alpha > 1.0: alpha = 1.0
			I *= alpha

		_dirty_cols[x] = 0

	_has_dirty = false

	# DataLayer 경유로 한 번에 반영(시그널/풀리프레시 포함)
	_data.set_bulk_light(L_new, &"light_recompute")


## 전장에 스칼라 곱(낮/밤·옵션 등 I0만 바뀐 경우에 한해 O(WH)로 빠르게 반영)
func _apply_global_scale(scale: float) -> void:
	if _light == null or _index == null:
		return
	if scale == 1.0:
		return

	var n := _index.size.x * _index.size.y
	var L_read : PackedFloat32Array = _light.get_raw_read()

	var idxs := PackedInt32Array(); idxs.resize(n)
	var vals := PackedFloat32Array(); vals.resize(n)

	if scale <= 0.0:
		for i in n:
			idxs[i] = i
			vals[i] = 0.0
		_data.set_cells_with_spec(_index._index_array_to_cells(idxs), {"LIGHT": vals}, &"light_scale_zero")
		return

	for i in n:
		idxs[i] = i
		var v := L_read[i] * scale
		vals[i] = (0.0 if v < 0.0 else v)

	_data.set_cells_with_spec(_index._index_array_to_cells(idxs), {"LIGHT": vals}, &"light_scale")


## dirty 비트셋을 월드 폭에 맞춰 준비
func _ensure_dirty_bitset() -> void:
	if _index == null: return
	var w := _index.size.x
	if _dirty_cols.size() != w:
		_dirty_cols.resize(w)
		for x in w:
			_dirty_cols[x] = 0

## 전 칼럼 더티 처리
func _mark_all_dirty() -> void:
	_ensure_dirty_bitset()
	for x in _dirty_cols.size():
		_dirty_cols[x] = 1
	_has_dirty = true
