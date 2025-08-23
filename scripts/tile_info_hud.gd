extends Control
class_name TileInfoHUD

@onready var tile_info_panel: PanelContainer = $TileInfoPanel
@onready var tile_info_tracker: TileInfoTracker = $TileInfoTracker

@onready var _panel: PanelContainer = $TileInfoPanel
@onready var _phase_label: Label = $TileInfoPanel/Phase/PhaseLabel

@export var offset := Vector2(14, 18)   # 커서와 겹치지 않도록
@export var edge_margin := 8.0          # 화면 가장자리 여백
@export var smoothing := 0.0            # 0이면 즉시, 0.0~1.0이면 스무딩 강도

const PHASE_TEXT := {
	-1: "—",
	 0: "VACUUM",
	 1: "SOLID",
	 2: "LIQUID",
	 3: "GAS",
}
const PHASE_COLOR := {                 # 선택: Label 폰트 색 등
	-1: Color(0.8,0.8,0.8),
	 0: Color(0.75,0.75,0.85),
	 1: Color(0.7,0.5,0.35),
	 2: Color(0.4,0.6,0.95),
	 3: Color(0.7,0.8,0.95),
}

func setup(hs: HoverService, gi: GridIndex, ps: PhaseStore) -> void:
	tile_info_tracker.setup(hs, gi, ps)
	tile_info_tracker.connect("info_updated", _on_info_updated)

func _on_info_updated(info: Dictionary) -> void:
	var phase_val: int = int(info.get("phase", -1))
	var text: String = PHASE_TEXT.get(phase_val, "UNKNOWN")
	_phase_label.text = "PHASE: " + text

	# 선택: 색/아이콘 갱신
	var col: Color = PHASE_COLOR.get(phase_val, Color.WHITE)
	_phase_label.add_theme_color_override("font_color", col)
	# _phase_icon.texture = ... (아이콘 매핑을 쓴다면 여기서 교체)

	# 패널이 꺼져 있으면 켠다(hover 연결을 안 쓴 경우 대비)
	if not _panel.visible:
		_panel.show()

func _process(delta: float) -> void:
	if not visible:
		return

	var target := get_viewport().get_mouse_position()# + offset
	target = _anti_clip(target)
	if smoothing > 0.0:
		tile_info_panel.global_position = global_position.lerp(target, clamp(smoothing, 0.0, 1.0))
	else:
		tile_info_panel.global_position = target

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
