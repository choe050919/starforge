extends Control

@onready var panel_container: PanelContainer = $PanelContainer

@export var offset := Vector2(14, 18)   # 커서와 겹치지 않도록
@export var edge_margin := 8.0          # 화면 가장자리 여백
@export var smoothing := 0.0            # 0이면 즉시, 0.0~1.0이면 스무딩 강도

func _process(delta: float) -> void:
	if not visible:
		return

	var target := get_viewport().get_mouse_position()# + offset
	target = _anti_clip(target)
	if smoothing > 0.0:
		panel_container.global_position = global_position.lerp(target, clamp(smoothing, 0.0, 1.0))
	else:
		panel_container.global_position = target

func _anti_clip(p: Vector2) -> Vector2:
	# 화면 밖 방지(우하 우선 배치, 안되면 좌/상쪽으로 밀어넣기)
	var view := get_viewport_rect().size
	var sz := size
	var pos := p
	#if pos.x + sz.x + edge_margin > view.x:
		#pos.x = max(edge_margin, view.x - sz.x - edge_margin)
	#if pos.y + sz.y + edge_margin > view.y:
		#pos.y = max(edge_margin, view.y - sz.y - edge_margin)
	return pos
