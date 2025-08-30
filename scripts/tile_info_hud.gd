extends Control
class_name TileInfoHUD

@onready var tile_info_tracker: TileInfoTracker = $TileInfoTracker

@onready var _panel: PanelContainer = $TileInfoPanel
@onready var _substance_label: Label = $TileInfoPanel/VBoxContainer/Substance/SubstanceLabel
@onready var _phase_label: Label = $TileInfoPanel/VBoxContainer/Phase/PhaseLabel
@onready var _mass_label: Label = $TileInfoPanel/VBoxContainer/Mass/MassLabel
@onready var _temperature_label: Label = $TileInfoPanel/VBoxContainer/Temperature/TemperatureLabel

@export var offset := Vector2(14, 18)   # 커서와 겹치지 않도록
@export var edge_margin := 8.0          # 화면 가장자리 여백
@export var smoothing := 0.0            # 0이면 즉시, 0.0~1.0이면 스무딩 강도

# 표시 자리수 조정(kg/g일 때)
@export var mass_decimals := 2
@export var temperature_decimals := 2

@export var use_celsius := true

const SUBSTANCE_TEXT := {
	-1: "—",
	 0: "VACUUM",
	 1: "ICE",
	 2: "GROUND",
	 3: "URANIUM",
	 4: "WATER",
}
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

func setup(hs: HoverService, gi: GridIndex, ss: SubstanceStore, ps: PhaseStore, ms: MassStore, ts: TemperatureStore) -> void:
	tile_info_tracker.setup(hs, gi, ss, ps, ms, ts)
	tile_info_tracker.connect("info_updated", _on_info_updated)

func _on_info_updated(info: Dictionary) -> void:
	_update_substance(info)
	_update_phase(info)
	_update_mass(info)
	_update_temperature(info)

func _update_substance(info: Dictionary) -> void:
	var s: int = info.get("substance", -1)
	var text: String = SUBSTANCE_TEXT.get(s, "UNKNOWN")
	_substance_label.text = "SUBSTANCE: " + text

func _update_phase(info: Dictionary) -> void:
	var p: int = info.get("phase", -1)
	var text: String = PHASE_TEXT.get(p, "UNKNOWN")
	_phase_label.text = "PHASE: " + text

	# 색/아이콘 갱신
	var col: Color = PHASE_COLOR.get(p, Color.WHITE)
	_phase_label.add_theme_color_override("font_color", col)

func _update_mass(info: Dictionary) -> void:
	var m = info.get("mass", null)
	var text := _format_mass(-1 if m == null else m)
	_mass_label.text = "MASS: " + text

func _update_temperature(info: Dictionary) -> void:
	var t = info.get("temperature", -1)
	var text := _format_temperature(-1 if t == null else t)
	_temperature_label.text = "TEMPERATURE: " + text

## mg → g → kg 자동 포맷터 (HUD 전용)
## 추후 다른 패널에서도 사용될 수 있지만 일단 빠른 개발을 위해 여기서 구현하였음.
func _format_mass(mg: int) -> String:
	const MG_PER_G := 1000
	const MG_PER_KG := 1000000

	if mg < 0:
		return "—"

	if mg >= MG_PER_KG:
		var kg := float(mg) / MG_PER_KG
		return _trim_zeros(kg, mass_decimals) + " kg"
	elif mg >= MG_PER_G:
		var g := float(mg) / MG_PER_G
		return _trim_zeros(g, mass_decimals) + " g"
	else:
		return "%d mg" % mg

func _format_temperature(ck: int) -> String:
	const CK_PER_K := 100
	const CK_0C := 27315

	if ck <= 0:
		return "—"

	if use_celsius:
		var cc := float(ck - CK_0C)
		cc /= 100
		return _trim_zeros(cc, temperature_decimals) + " °C"
	else:
		if ck >= CK_PER_K:
			var k := float(ck) / CK_PER_K
			return _trim_zeros(k, temperature_decimals) + " K"
		else:
			return "%d cK" % ck

## 소수부 불필요한 0 제거 (예: 12.340 → 12.34, 10.000 → 10)
func _trim_zeros(val: float, decimals: int) -> String:
	var fmt := "%." + str(max(0, decimals)) + "f"
	var s := fmt % val
	# 오른쪽 0과 마지막 점 제거
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

func _process(delta: float) -> void:
	if not visible:
		return

	var target := get_viewport().get_mouse_position() + offset
	#target = _anti_clip(target)
	if smoothing > 0.0:
		_panel.global_position = _panel.global_position.lerp(target, clamp(smoothing, 0.0, 1.0))
	else:
		_panel.global_position = target

#func _anti_clip(p: Vector2) -> Vector2:
	## 화면 밖 방지(우하 우선 배치, 안되면 좌/상쪽으로 밀어넣기)
	#var view := get_viewport_rect().size
	#var sz := size
	#var pos := p
	##if pos.x + sz.x + edge_margin > view.x:
		##pos.x = max(edge_margin, view.x - sz.x - edge_margin)
	##if pos.y + sz.y + edge_margin > view.y:
		##pos.y = max(edge_margin, view.y - sz.y - edge_margin)
	#return pos
