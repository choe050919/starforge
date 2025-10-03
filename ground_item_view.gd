extends Node2D
class_name GroundItemView

@export var sid: int = 0
@export var mass_kg: float = 0.0
@export var temperature_K: float = 293.15
@export var show_label: bool = true

var _radius: float = 6.0
var _color: Color = Color.WHITE

# 폰트: Node2D에서는 ThemeDB의 폴백 폰트를 사용
var _font: Font
var _font_size: int = 10

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size
	_update_visuals()
	queue_redraw()

func set_data(new_sid: int, new_mass_kg: float, new_temp_K: float) -> void:
	sid = new_sid
	mass_kg = new_mass_kg
	temperature_K = new_temp_K
	_update_visuals()
	queue_redraw()

func _update_visuals() -> void:
	# 반지름: sqrt(log10(mg)) 기반 스케일 (1mg~1kg 범위 대충 대응)
	var mg: float = max(1.0, mass_kg * 1_000_000.0)
	var log10_mg: float = log(mg) / log(10.0)
	_radius = clamp(3.0 + 3.0 * sqrt(max(0.0, log10_mg)), 3.0, 18.0)

	# 색상: sid 기반 Hue + 온도에 따른 밝기 보정
	var hue: float = float((sid * 31) % 360) / 360.0
	var base: Color = Color.from_hsv(hue, 0.6, 0.9)
	var temp_norm: float = clamp((temperature_K - 250.0) / 150.0, 0.0, 1.0) # ~250K..400K
	_color = base.lerp(Color.WHITE, 0.15 + 0.25 * (1.0 - temp_norm))

func _draw() -> void:
	# 본체
	draw_circle(Vector2.ZERO, _radius, _color)
	# 테두리
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 24, _color.darkened(0.3), 1.0)

	# 라벨
	if show_label and _font != null:
		var grams: float = mass_kg * 1000.0
		var txt: String = (("%.1fg" % grams) if grams < 1000.0 else ("%.3fkg" % mass_kg))
		var bb: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size)
		var pos: Vector2 = Vector2(-bb.x * 0.5, _radius + 10.0)
		draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, Color(1,1,1,0.9))
