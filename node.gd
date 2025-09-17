extends Node

const FLAG_VISIBLE = 1 << 0
const FLAG_ACTIVE  = 1 << 1
const FLAG_SOLID   = 1 << 2

var state: int = 0

func _ready():
	print(FLAG_VISIBLE)

	for i in 5:
		print(1 << i)

	# 플래그 켜기
	state |= FLAG_VISIBLE
	state |= FLAG_SOLID
	print("초기 state:", state)  # 0101 → 5

	# 특정 플래그 확인
	if state & FLAG_SOLID != 0:
		print("SOLID 켜져 있음!")

	# 플래그 끄기
	state &= ~FLAG_VISIBLE
	print("VISIBLE 끄고 나서 state:", state)  # 0100 → 4

	# 플래그 토글
	state ^= FLAG_ACTIVE
	print("ACTIVE 토글 후 state:", state)  # 0110 → 6
