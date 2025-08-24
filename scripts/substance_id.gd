class_name SubstanceId

enum ID {
	VACUUM  = 0,
	ICE     = 1,
	GROUND  = 2,
	URANIUM = 3,
	WATER   = 4,
}

static func is_valid(id:int) -> bool:
	return id >= ID.VACUUM and id <= ID.WATER
