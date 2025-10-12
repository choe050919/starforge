extends Node2D
class_name FishCorpse

@export var mass_g := 100.0
@export var nutrition_j := 3000.0
var decay_progress := 0.0  # 자동 소멸 없음

func set_stats(mass: float, nutrition: float) -> void:
	mass_g = mass
	nutrition_j = nutrition
