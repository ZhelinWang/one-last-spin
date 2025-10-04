extends TokenAbility
class_name PoacherPassiveAbility

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
	if ctx == null or destroyed_token == null:
		return []
	ctx["destroyed_by_token"] = destroyed_token
	return []
