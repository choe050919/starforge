## 역할 태그 비트 플래그 (중복 가능)
## 정적 성격
enum PlantPart {
	NONE  = 0,
	LEAF  = 1 << 0,  # 잎: 빛 흡수/증산 1
	STEM  = 1 << 1,  # 줄기: 지지/전달 2
	ROOT  = 1 << 2,  # 뿌리: 물/무기물 흡수 4
	FRUIT = 1 << 3,  # 열매: 수확/저장 8
	THORN = 1 << 4,  # 가시: 접촉 피해 16
}

static func has(tag: int, flag: int) -> bool:
	return (tag & flag) != 0

static func add(tag: int, flag: int) -> int:
	return tag | flag

static func remove(tag: int, flag: int) -> int:
	return tag & ~flag
