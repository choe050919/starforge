extends Node
class_name HoverService

signal hover_changed(cell: Vector2i)

var data_layer: DataLayer
var _current: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
        if data_layer == null:
                push_warning("[HoverService] DataLayer not set; waiting")

func set_data_layer(dl: DataLayer) -> void:
        data_layer = dl
        if dl == null:
                push_warning("[HoverService] DataLayer injected as null")
        else:
                print("[HoverService] DataLayer injected")

func update_hover(cell: Vector2i) -> void:
        if data_layer == null:
                return
        if not data_layer.index.in_bounds(cell):
                cell = Vector2i(-1, -1)
        if cell == _current:
                return
        _current = cell
        hover_changed.emit(cell)
