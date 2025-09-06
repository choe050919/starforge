# ─────────────────────────────────────────────────────────
# HydrologyField.gd
# per-tile 전개 필드: 타일마다 capacity/infil/leak/diff 배열로 뽑아둠
#  - 장점: 순차 접근(캐시 히트↑), 루프에서 해시 조회 제거
#  - 갱신: 풀 리빌드 + 인덱스 단위 증분(타일 교체 시)
# ─────────────────────────────────────────────────────────
extends RefCounted
class_name HydrologyField

var capacity: PackedInt32Array = PackedInt32Array()  # mg
var infil:    PackedInt32Array = PackedInt32Array()  # mg/tick
var leak:     PackedInt32Array = PackedInt32Array()  # mg/tick
var diff:     PackedInt32Array = PackedInt32Array()  # mg/tick

var _size: Vector2i = Vector2i.ZERO
var _version: int = 0

func setup(index: GridIndex) -> void:
	_size = index.size
	var n: int = _size.x * _size.y
	capacity.resize(n); capacity.fill(0)
	infil.resize(n);    infil.fill(0)
	leak.resize(n);     leak.fill(0)
	diff.resize(n);     diff.fill(0)
	_version = 0

# 전체 전개(월드 로드, 대량 변경 시 1회)
func rebuild_all(cache: HydrologyCache, substance_store: SubstanceStore) -> void:
	var sid: PackedInt32Array = substance_store.get_raw_read()
	var n: int = sid.size()
	if capacity.size() != n:
		# setup이 아직 안 되었거나, 크기 불일치 시 재설정
		capacity.resize(n); infil.resize(n); leak.resize(n); diff.resize(n)

	for i in n:
		var s: int = sid[i]
		capacity[i] = cache.capacity_of(s)
		infil[i]    = cache.infil_of(s)
		leak[i]     = cache.leak_of(s)
		diff[i]     = cache.diff_of(s)

	_version += 1

# 일부 인덱스만 갱신(타일 교체 이벤트에서 호출)
func update_indices(cache: HydrologyCache, substance_store: SubstanceStore, indices: PackedInt32Array) -> void:
	var sid: PackedInt32Array = substance_store.get_raw_read()
	var n_total: int = sid.size()
	if capacity.size() != n_total:
		# 안전망: 사이즈가 달라졌으면 전체 리빌드로 대체
		rebuild_all(cache, substance_store)
		return

	var m: int = indices.size()
	for k in m:
		var i: int = indices[k]
		if i < 0 or i >= n_total: continue
		var s: int = sid[i]
		capacity[i] = cache.capacity_of(s)
		infil[i]    = cache.infil_of(s)
		leak[i]     = cache.leak_of(s)
		diff[i]     = cache.diff_of(s)

	_version += 1

func version() -> int: return _version
func size() -> Vector2i: return _size
