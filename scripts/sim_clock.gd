extends Node
class_name SimClock

signal tick_sim(dt: float)

@export var sim_rate_hz: int = 10 # 10Hz(0.1s)로 시작
var _accum: float = 0.0

func _process(delta: float) -> void:
	_accum += delta
	var step := 1.0 / float(sim_rate_hz)
	while _accum >= step:
		_accum -= step
		emit_signal("tick_sim", step)
