extends TokenAbility
class_name SetSelfPermToTargetCurrentAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Defer to executor choose target; executor will compute delta
	return [{"op":"set_self_perm_to_target_current", "target_kind":"choose"}]
