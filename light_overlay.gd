## 노란 라이트맵(irradiance, W/m²)을 타일 단위로 시각화하는 오버레이.
## - 입력: PackedFloat32Array(light_wm2), (선택) PackedByteArray(mask)
## - 출력: 1텍셀=1타일 이미지 텍스처를 Sprite2D("Map")에 바인딩
## - 값 스케일: 0..I0_VISUAL_MAX_WM2(임시) 또는 auto-max
## - 색상: 검정(0) → 노랑(최대)
## - 알파: overlay opacity(고정), 0일 때 완전 투명
extends Node2D
class_name LightOverlay

@onready var sprite: Sprite2D = get_node("Map")

# ── 설정값 ─────────────────────────────────────────────────────────
@export var opacity: float = 0.9         ## 오버레이 투명도(0~1)

@export var use_auto_max: bool = false   ## true면 현재 프레임의 최대값으로 자동 정규화
@export var auto_max_epsilon: float = 1e-6 ## auto-max가 0에 수렴할 때의 안전 하한

## ⚠️ 임시 정규화 상한. 나중에 Light 노드의 I0_surface_wm2와 연결하세요.
## TODO: Light(I0_surface_wm2)와 직접 연동하도록 교체
const I0_VISUAL_MAX_WM2 := 1000.0

# ── 레이아웃(월드 크기/타일 픽셀) ───────────────────────────────────
var grid_size: Vector2i
var tile_px: Vector2i = Vector2i(32, 32)  ## 타일 픽셀(외부에서 set_layout으로 세팅 권장)

func _ready() -> void:
	## 스프라이트 픽셀 맞춤 & 최상단 표시
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1000

	## Ground와 동일 원점/스케일 컨벤션
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	## 스케일링은 스프라이트에서만 처리(텍스처 1픽셀=1타일)
	sprite.scale = Vector2(tile_px)
	sprite.modulate.a = opacity

## 외부에서 월드 크기/타일 픽셀 크기를 전달
func set_layout(size: Vector2i, tile_size: Vector2i) -> void:
	grid_size = size
	tile_px = tile_size
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(tile_px)
	sprite.modulate.a = opacity

# ── 렌더 API ───────────────────────────────────────────────────────
## 전체 리렌더(마스크 없음): 값이 0이면 완전 투명
func render_full(light_wm2: PackedFloat32Array) -> void:
	_render_internal(light_wm2)

## 전체 리렌더(마스크 포함):
## - mask[i]==0 → 완전 투명
## - mask[i]!=0 → 값에 따라 노란색
func render_full_with_mask(light_wm2: PackedFloat32Array, mask: PackedByteArray) -> void:
	_render_internal(light_wm2, mask)

# ── 내부 구현 ─────────────────────────────────────────────────────
func _render_internal(light_wm2: PackedFloat32Array, mask: PackedByteArray = PackedByteArray()) -> void:
	# 0) 사이즈 검증
	var n_expected := grid_size.x * grid_size.y
	if n_expected <= 0:
		push_error("[LightOverlay] layout not set. Call set_layout() first.")
		return
	if light_wm2.size() != n_expected:
		push_error("[LightOverlay] size mismatch: n=%d, light=%d" % [n_expected, light_wm2.size()])
		return
	var use_mask := false
	if mask.size() == n_expected:
		use_mask = true
	elif mask.size() == 0:
		use_mask = false
	else:
		push_warning("[LightOverlay] mask size mismatch: n=%d, mask=%d (mask ignored)" % [n_expected, mask.size()])
		use_mask = false

	# 1) 정규화 상한 결정
	var vmax: float
	if use_auto_max:
		vmax = _max_value(light_wm2)
		if vmax < auto_max_epsilon:
			# 모두 0에 가깝다면 전체 투명으로 빠르게 처리
			_set_empty_texture()
			return
	else:
		vmax = max(I0_VISUAL_MAX_WM2, 1.0) # 임시 상수 사용(⚠️ TODO 교체)

	# 2) 이미지 생성(텍스처 1픽셀=1타일)
	var img: Image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	var inv := 1.0 / vmax

	for y in grid_size.y:
		var row := y * grid_size.x
		for x in grid_size.x:
			var idx: int = row + x
			# 마스크 0 → 완전 투명
			if use_mask and mask[idx] == 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var v: float = light_wm2[idx]
			if v <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t: float = clamp(v * inv, 0.0, 1.0)
			var col := _color_map_yellow(t)
			img.set_pixel(x, y, col)

	# 3) 텍스처 업데이트
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = tex

## 0..1 정규화된 값 t를 노란 계열 컬러로 매핑
## - 0 → 완전 투명
## - 1 → 밝은 노랑(불투명도=opacity)
func _color_map_yellow(t: float) -> Color:
	var c_off := Color(0.0, 0.0, 0.0, 0.0)
	var c_on  := Color(1.0, 1.0, 0.0, opacity)
	return c_off.lerp(c_on, t)

## light 배열의 최대값을 구함(성능 이슈가 크지 않음)
func _max_value(arr: PackedFloat32Array) -> float:
	var m: float = 0.0
	for i in arr.size():
		if arr[i] > m:
			m = arr[i]
	return m

## 모든 픽셀을 완전 투명으로 채운 텍스처 지정(빠른 early-exit 경로)
func _set_empty_texture() -> void:
	var img: Image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	sprite.texture = tex
