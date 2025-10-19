extends Node
class_name SimClock

## 시뮬레이션 틱 신호
##
## 모든 틱마다 "sim" 신호 발생
## 내부적으로 _tick_count를 관리하여 일부 시스템이 선택적으로 실행 가능
signal tick_sim(tag: StringName, dt: float, tick_count: int)

@export var sim_rate_hz: int = 10  # 시뮬레이션 주파수 (10Hz = 0.1초마다)
@export var speed: float = 1.0     # 배속 (0.5x, 1x, 2x, 4x 등)

var _step: float
var _accum: float = 0.0
var _tick_count: int = 0  # 틱 카운터 (외부에서 홀짝 판별용)

func _ready() -> void:
	_step = 1.0 / sim_rate_hz
	print("[SimClock] Rate: %d Hz" % sim_rate_hz)
	print("[SimClock] Step: %.3f s" % _step)

func _process(delta: float) -> void:
	_accum += delta * speed

	while _accum >= _step:
		_accum -= _step
		
		# 모든 틱마다 "sim" 신호 발생
		# tick_count를 함께 전달하여 수신자가 홀짝 판별 가능
		tick_sim.emit("sim", _step, _tick_count)
		
		_tick_count += 1

## 현재 틱 카운트 확인
func get_tick_count() -> int:
	return _tick_count

## 짝수 틱인지 확인
func is_even_tick() -> bool:
	return _tick_count % 2 == 0

## 홀수 틱인지 확인
func is_odd_tick() -> bool:
	return _tick_count % 2 == 1
