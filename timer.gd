extends Timer

@onready var world: World = $".."

func _on_timeout() -> void:
	world.data_layer.mass.print_total_mass()
