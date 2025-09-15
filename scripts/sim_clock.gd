extends Node
class_name SimClock

signal tick_sim(tag: StringName, dt: float)

@export var sim_rate_hz: int = 10      # 기본 10Hz(0.1s)
@export var temp_rate_hz: float = 5.0  # 온도는 5Hz
@export var speed: float = 1.0         # 배속 (0.5x, 1x, 2x, 4x 등)

var _step_sim: float
var _step_temp: float
var _accum_sim: float = 0.0
var _accum_temp: float = 0.0

func _ready() -> void:
	_step_sim = 1.0 / sim_rate_hz
	_step_temp = 1.0 / temp_rate_hz

func _process(delta: float) -> void:
	_accum_sim += delta * speed
	_accum_temp += delta * speed

	while _accum_temp >= _step_temp:
		_accum_temp -= _step_temp
		tick_sim.emit("temp", _step_temp) # 온도 신호
	while _accum_sim >= _step_sim:
		_accum_sim -= _step_sim
		tick_sim.emit("sim",  _step_sim)   # 기본 시뮬레이션 신호
