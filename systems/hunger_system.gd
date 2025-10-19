## HungerSystem: 엄밀한 칼로리 기반 허기 시스템
## 
## 현실 기반 스케일:
## - 게임 캐릭터 크기: 0.2m (2셀)
## - 현실 환산: ~170cm 성인
## - 기초대사량: 약 1800 kcal/10시간 플레이
## 
## SubstanceRuleCache를 통해 물질의 영양 정보(칼로리, 소화 시간) 조회
extends Node
class_name HungerSystem

@export var debug_log := false

signal hunger_changed(current: float, max: float, ratio: float)
signal hunger_state_changed(state: State)
signal starving_damage(damage: float)

enum State {
	OVERFED,     # 100%+ (포만감 한계 초과)
	SATISFIED,   # 30-100% (정상)
	HUNGRY,      # 10-30% (경고)
	STARVING,    # 0-10% (위험)
	CRITICAL     # 0% 이하 (체력 감소)
}

# ── 칼로리 저장소 ─────────────────────────────────────────
@export var max_calories: float = 2500.0         # 최대 저장 칼로리 (포만감 한계)
@export var start_calories: float = 1800.0       # 시작 칼로리
@export var min_survival: float = 250.0          # 생존 최소 칼로리

var current_calories: float = 1800.0

# ── 소모율 (kcal/sec) ─────────────────────────────────────
@export var base_metabolism: float = 0.05        # 기본 대사 (1800 kcal/10h)
@export var moving_cost: float = 0.02            # 이동 추가
@export var mining_cost: float = 0.05            # 채굴 추가
@export var construction_cost: float = 0.03      # 건설 추가

# ── 상태 효과 ─────────────────────────────────────────────
var current_state: State = State.SATISFIED

# 상태별 이동속도 배율
const STATE_SPEED_MULT := {
	State.OVERFED: 0.7,
	State.SATISFIED: 1.0,
	State.HUNGRY: 0.8,
	State.STARVING: 0.5,
	State.CRITICAL: 0.3
}

# ── 기아 대미지 ───────────────────────────────────────────
@export var starvation_damage_per_sec: float = 1.0  # CRITICAL 상태에서 체력 감소율

# ── 소화 중인 음식 ────────────────────────────────────────
var _digesting_food: Array[Dictionary] = []  # {sid, calories, time_left}

# ── 외부 참조 ─────────────────────────────────────────────
var _rule_cache: SubstanceRuleCache
var _player: Player

# ══════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════

func setup(player: Player, rule_cache: SubstanceRuleCache) -> void:
	_player = player
	_rule_cache = rule_cache
	current_calories = start_calories
	_update_state()
	if debug_log:
		print("[HungerSystem] Setup complete with rule_cache")

func _ready() -> void:
	set_process(false)  # setup 호출 전까지 대기

func _process(delta: float) -> void:
	_tick(delta)

# ══════════════════════════════════════════════════════════
# 시뮬레이션 틱
# ══════════════════════════════════════════════════════════

func _tick(delta: float) -> void:
	# 1. 기본 대사 소모
	var consumption := base_metabolism * delta
	
	# 2. 활동 추가 소모
	if _player:
		if _player._mode == Player.Mode.MOVING:
			consumption += moving_cost * delta
		elif _player._mode == Player.Mode.MINING:
			consumption += mining_cost * delta
	
	# 3. 소화 진행
	_process_digestion(delta)
	
	# 4. 칼로리 소모
	current_calories -= consumption
	
	# 5. 기아 대미지 (CRITICAL 상태)
	if current_state == State.CRITICAL:
		var damage := starvation_damage_per_sec * delta
		starving_damage.emit(damage)
	
	# 6. 상태 업데이트
	_update_state()
	
	# 7. UI 신호
	hunger_changed.emit(current_calories, max_calories, get_hunger_ratio())

# ══════════════════════════════════════════════════════════
# 음식 섭취
# ══════════════════════════════════════════════════════════

## 음식 섭취 시도
## mass_mg: 섭취할 질량 (mg)
## 반환: 실제 섭취한 질량 (mg)
func consume_food(sid: int, mass_mg: int) -> int:
	if not _rule_cache:
		push_warning("[HungerSystem] SubstanceRuleCache not set")
		return 0
	
	# 소화 불가능한 물질
	if not _rule_cache.is_digestible(sid):
		if debug_log:
			print("[HungerSystem] Material %d is not digestible" % sid)
		return 0
	
	# 칼로리 계산
	var total_calories := _rule_cache.calculate_calories(sid, mass_mg)
	
	if total_calories <= 0.0:
		return 0
	
	# 포만감 체크 (최대치 초과 방지)
	var capacity_left := max_calories - current_calories
	
	# 소화 중인 음식의 칼로리도 고려
	var digesting_total := 0.0
	for food in _digesting_food:
		digesting_total += food.calories
	
	capacity_left -= digesting_total
	
	if capacity_left <= 0.0:
		if debug_log:
			print("[HungerSystem] Too full to eat")
		return 0
	
	# 실제 섭취 가능한 양 계산
	var consumable_calories : float = min(total_calories, capacity_left)
	var consumed_ratio : float = consumable_calories / total_calories
	var consumed_mg := int(float(mass_mg) * consumed_ratio)
	
	# 소화 큐에 추가
	var digestion_time := _rule_cache.get_digestion_time(sid)
	_digesting_food.append({
		"sid": sid,
		"calories": consumable_calories,
		"time_left": digestion_time
	})
	
	if debug_log:
		print("[HungerSystem] Consuming %d mg of SID %d (%.1f kcal, digestion: %.1f sec)" 
			% [consumed_mg, sid, consumable_calories, digestion_time])
	
	return consumed_mg

## 소화 진행
func _process_digestion(delta: float) -> void:
	var i := 0
	while i < _digesting_food.size():
		var food: Dictionary = _digesting_food[i]
		food.time_left -= delta
		
		# 소화 완료
		if food.time_left <= 0.0:
			current_calories += food.calories
			if debug_log:
				print("[HungerSystem] Digestion complete: +%.1f kcal" % food.calories)
			_digesting_food.remove_at(i)
			continue
		
		i += 1

# ══════════════════════════════════════════════════════════
# 상태 관리
# ══════════════════════════════════════════════════════════

func _update_state() -> void:
	var old_state := current_state
	var ratio := get_hunger_ratio()
	
	if current_calories > max_calories:
		current_state = State.OVERFED
	elif ratio >= 0.30:
		current_state = State.SATISFIED
	elif ratio >= 0.10:
		current_state = State.HUNGRY
	elif ratio > 0.0:
		current_state = State.STARVING
	else:
		current_state = State.CRITICAL
	
	if old_state != current_state:
		hunger_state_changed.emit(current_state)
		if debug_log:
			print("[HungerSystem] State changed: %s -> %s" % [State.keys()[old_state], State.keys()[current_state]])

func get_hunger_ratio() -> float:
	return clamp(current_calories / max_calories, 0.0, 1.0)

func get_speed_multiplier() -> float:
	return STATE_SPEED_MULT.get(current_state, 1.0)

func get_can_mine() -> bool:
	return current_state != State.CRITICAL

func get_state_color() -> Color:
	match current_state:
		State.OVERFED:
			return Color(0.8, 0.6, 0.2)  # 주황
		State.SATISFIED:
			return Color(0.2, 0.8, 0.2)  # 녹색
		State.HUNGRY:
			return Color(0.9, 0.9, 0.2)  # 노랑
		State.STARVING:
			return Color(0.9, 0.4, 0.2)  # 빨강-주황
		State.CRITICAL:
			return Color(0.9, 0.1, 0.1)  # 빨강
		_:
			return Color.WHITE

func get_state_text() -> String:
	match current_state:
		State.OVERFED:
			return "Overfed"
		State.SATISFIED:
			return "Satisfied"
		State.HUNGRY:
			return "Hungry"
		State.STARVING:
			return "Starving"
		State.CRITICAL:
			return "CRITICAL"
		_:
			return "Unknown"

# ══════════════════════════════════════════════════════════
# 디버그 & 치트
# ══════════════════════════════════════════════════════════

func add_calories_direct(amount: float) -> void:
	current_calories = clamp(current_calories + amount, 0.0, max_calories * 1.5)
	_update_state()
	hunger_changed.emit(current_calories, max_calories, get_hunger_ratio())

func reset_hunger() -> void:
	current_calories = start_calories
	_digesting_food.clear()
	_update_state()
	hunger_changed.emit(current_calories, max_calories, get_hunger_ratio())
