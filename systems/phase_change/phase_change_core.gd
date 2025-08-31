## 순수 상전이 로직만 담당.
extends RefCounted
class_name PhaseChangeCore

# 룰 공급자
var _rules: SubstanceRuleCache

func bind_rule_cache(cache: SubstanceRuleCache) -> void:
	_rules = cache

	if _rules != null:
		var keys := _rules.rules_by_sid.keys()
		print("[PCore][dbg] rules_by_sid.size=", keys.size())
		# 앞 몇 개만 미리보기
		for i in min(5, keys.size()):
			var k = keys[i]
			print("  - sid=", k, " phase=", _rules.phase_of_sid.get(k, -1), " rules=", _rules.rules_by_sid[k].size())

# ─────────────────────────────────────────────────────────
# 풀 스캔 실행:
# 반환 형식 변경:
# {
#   "changes": Array[{ "cell": Vector2i, "from_sid": int, "to_sid": int }],
#   "stats": Dictionary # (optional) ( (from_sid<<32)|to_sid : count )
# }
func tick_fullscan(phase_store, substance_store, temp_store, index: GridIndex) -> Dictionary:
	var n := index.size.x * index.size.y
	if n <= 0 or _rules == null:
		return { "changes": [], "stats": {} }

	var P: PackedByteArray   = phase_store.get_raw_read()
	var S: PackedInt32Array  = substance_store.get_raw_read()
	var T: PackedInt32Array  = temp_store.get_raw_read()

	var changes: Array = []
	var stats: Dictionary = {}

	# 고정 스캔 순서 유지(결정성)
	for i in n:
		var from_sid: int = S[i]
		# 룰이 없으면 스킵
		if not _rules.rules_by_sid.has(from_sid):
			continue

		var rules_for_sid: Array = _rules.rules_by_sid[from_sid]
		if rules_for_sid.is_empty():
			continue

		var t_ck: int = int(T[i])

		# JSON 기재 순서 = 우선순위
		for rule in rules_for_sid:
			var to_sid: int = rule["to_sid"]
			if _rule_triggers(t_ck, from_sid, to_sid, rule):
				var cell := index.cell(i)
				changes.append({ "cell": cell, "from_sid": from_sid, "to_sid": to_sid })
				var key := (int(from_sid) << 32) | int(to_sid)
				stats[key] = int(stats.get(key, 0)) + 1
				break # 한 틱, 한 셀, 첫 매칭만
			# 매칭 실패면 다음 룰 검사

	return { "changes": changes, "stats": stats }

# ─────────────────────────────────────────────────────────
# 룰 만족 판정(히스테리시스 적용 포함)
# 규칙:
# - 상향(phase(from) < phase(to))  : t_ck_min → (min + hyst), t_ck_max(있다면 그대로 ≤)
# - 하향(phase(from) > phase(to))  : t_ck_max → (max - hyst), t_ck_min(있다면 그대로 ≥)
# - 양쪽 키가 모두 있으면 두 조건을 모두 만족해야 함(구간)
func _rule_triggers(t_ck: int, from_sid: int, to_sid: int, rule: Dictionary) -> bool:
	var from_ph := int(_rules.phase_of_sid.get(from_sid, 0))
	var to_ph   := int(_rules.phase_of_sid.get(to_sid,   0))
	var hyst    := int(rule.get("hyst_ck", 0))

	var has_min := rule.has("t_ck_min")
	var has_max := rule.has("t_ck_max")

	var min_thr := int(rule["t_ck_min"]) if has_min else 0
	var max_thr := int(rule["t_ck_max"]) if has_max else 0

	# 방향에 따른 히스테리시스 보정
	if to_ph > from_ph:
		# 상향: min에 +hyst
		if has_min:
			min_thr += hyst
	elif to_ph < from_ph:
		# 하향: max에 -hyst
		if has_max:
			max_thr -= hyst
	# 같은 phase 이동은 히스테리시스 보정 없음

	# 조건 판정
	if has_min and has_max:
		return (t_ck >= min_thr) and (t_ck <= max_thr)
	elif has_min:
		return (t_ck >= min_thr)
	elif has_max:
		return (t_ck <= max_thr)
	else:
		# 둘 다 없으면 무시(2단계에서는 조용히 실패 처리)
		return false
