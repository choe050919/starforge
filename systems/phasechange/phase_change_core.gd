## 순수 상전이 로직 담당
##
## 물질 간 상전이(phase transition) 시뮬레이션의 핵심 계산을 수행합니다.
## - 온도 조건에 따른 상전이 규칙 평가
## - 히스테리시스를 고려한 전이 임계값 보정
## - 틱당 셀별 최대 1회 전이 보장
##
## 저장소: SubstanceStore (phase, substance, temperature)
extends RefCounted
class_name PhaseChangeCore

# ═══════════════════════════════════════════════════════════
# 상수
# ═══════════════════════════════════════════════════════════

## 실패 시 반환값
const EMPTY_RESULT := { "changes": [], "stats": {} }

# ═══════════════════════════════════════════════════════════
# 상태
# ═══════════════════════════════════════════════════════════

## 물질별 상전이 규칙 캐시
var _rules: SubstanceRuleCache

# ═══════════════════════════════════════════════════════════
# 초기화
# ═══════════════════════════════════════════════════════════

## 상전이 규칙 캐시 바인딩
func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rules = cache

	if _rules != null:
		var keys := _rules.rules_by_sid.keys()
		print("[PhaseChangeCore] Loaded rules for %d substances" % keys.size())
		
		# 샘플 출력 (디버그)
		for i in min(5, keys.size()):
			var k = keys[i]
			print("  - sid=%d phase=%d rules=%d" 
				% [k, _rules.phase_of_sid.get(k, -1), _rules.rules_by_sid[k].size()])

# ═══════════════════════════════════════════════════════════
# 메인 시뮬레이션 루프
# ═══════════════════════════════════════════════════════════

## 한 틱의 상전이 시뮬레이션 수행
##
## 모든 셀을 순회하며 온도 조건을 만족하는 상전이를 평가합니다.
## 각 셀은 틱당 최대 하나의 전이만 발생하며, 규칙 배열 순서가 우선순위입니다.
##
## P: 현재 phase (0=SOLID, 1=LIQUID, 2=GAS)
## S: 물질 ID
## T: 온도 (cK)
## index: 그리드 인덱스
##
## 반환: {
##   "changes": Array[{ "cell": Vector2i, "from_sid": int, "to_sid": int }],
##   "stats": Dictionary ( transition_key : count )
## }
func tick_fullscan(
	P: PackedByteArray,  # phase
	S: PackedInt32Array, # substance
	T: PackedInt32Array, # temperature
	index: GridIndex
) -> Dictionary:
	var n := index.size.x * index.size.y
	if n <= 0 or _rules == null:
		return EMPTY_RESULT

	if P.size() != n or S.size() != n or T.size() != n:
		push_error("[PhaseChangeCore.tick_fullscan] Size mismatch")
		return EMPTY_RESULT

	var changes: Array = []
	var stats: Dictionary = {}

	# 고정 스캔 순서 유지 (결정성)
	for i in n:
		var from_sid: int = S[i]
		
		# 룰이 없으면 스킵
		if not _rules.rules_by_sid.has(from_sid):
			continue

		var rules_for_sid: Array = _rules.rules_by_sid[from_sid]
		if rules_for_sid.is_empty():
			continue

		var temp_ck: int = int(T[i])

		# JSON 기재 순서 = 우선순위
		for rule in rules_for_sid:
			var to_sid: int = rule["to_sid"]
			var from_phase := int(_rules.phase_of_sid.get(from_sid, 0))
			var to_phase := int(_rules.phase_of_sid.get(to_sid, 0))

			if _rule_triggers(temp_ck, from_phase, to_phase, rule):
				var cell := index.cell(i)
				changes.append({ 
					"cell": cell, 
					"from_sid": from_sid, 
					"to_sid": to_sid 
				})
				
				var key := _make_transition_key(from_sid, to_sid)
				stats[key] = int(stats.get(key, 0)) + 1
				break # 한 틱, 한 셀, 첫 매칭만

	return { "changes": changes, "stats": stats }

# ═══════════════════════════════════════════════════════════
# 핵심 계산 (순수 함수)
# ═══════════════════════════════════════════════════════════

## 상전이 규칙 만족 여부 판정
##
## 히스테리시스를 고려하여 온도 임계값을 보정합니다:
## - 상향 전이 (고체→액체, 액체→기체): t_ck_min에 +hyst
## - 하향 전이 (기체→액체, 액체→고체): t_ck_max에 -hyst
##
## temp_ck: 현재 온도 (cK)
## from_phase: 현재 phase
## to_phase: 전이 후 phase
## rule: 전이 규칙 (t_ck_min, t_ck_max, hyst_ck 포함)
##
## 반환: 규칙 만족 여부
static func _rule_triggers(
	temp_ck: int,
	from_phase: int,
	to_phase: int,
	rule: Dictionary
) -> bool:
	var hyst := int(rule.get("hyst_ck", 0))

	var has_min := rule.has("t_ck_min")
	var has_max := rule.has("t_ck_max")

	var min_threshold := int(rule["t_ck_min"]) if has_min else 0
	var max_threshold := int(rule["t_ck_max"]) if has_max else 0

	# 방향에 따른 히스테리시스 보정
	if to_phase > from_phase:
		# 상향 전이: 융점/비점에 히스테리시스 추가
		if has_min:
			min_threshold += hyst
	elif to_phase < from_phase:
		# 하향 전이: 응고점/응결점에 히스테리시스 감소
		if has_max:
			max_threshold -= hyst
	# 동일 phase 전이는 히스테리시스 보정 없음

	# 온도 조건 판정
	if has_min and has_max:
		return (temp_ck >= min_threshold) and (temp_ck <= max_threshold)
	elif has_min:
		return (temp_ck >= min_threshold)
	elif has_max:
		return (temp_ck <= max_threshold)
	else:
		return false

# ═══════════════════════════════════════════════════════════
# 유틸리티
# ═══════════════════════════════════════════════════════════

## 상전이 통계 키 생성
##
## from_sid와 to_sid를 64비트 정수로 결합하여 고유 키를 생성합니다.
static func _make_transition_key(from_sid: int, to_sid: int) -> int:
	return (from_sid << 32) | to_sid
