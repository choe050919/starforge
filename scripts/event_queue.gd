extends RefCounted
class_name EventQueue

var events: Array = []

func push_replace(cell: Vector2i, to_tile: int, reason: StringName = &"") -> void:
    events.append({
        "type": "replace_tile",
        "cell": cell,
        "to": to_tile,
        "reason": reason,
    })

func pop_all() -> Array:
    var out := events
    events = []
    return out
