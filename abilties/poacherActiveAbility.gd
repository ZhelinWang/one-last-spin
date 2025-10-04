extends TokenAbility
class_name PoacherActiveAbility

func _init():
	trigger = Trigger.ACTIVE_DURING_SPIN
	winner_only = true

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var contrib := _find_self_contrib(contribs, source_token)
	if contrib.is_empty() or int(contrib.get("offset", 99)) != 0:
		return []
	if ctx == null:
		return []
	var last_destroyed = ctx.get("destroyed_by_token", null)
	if last_destroyed == null:
		return []
	return [{"op": "spawn_copy_in_inventory", "token_ref": last_destroyed}]
