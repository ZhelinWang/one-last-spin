extends TokenAbility
class_name MastermindActiveAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	return [{"op":"mastermind_destroy_all_copies", "target_kind":"choose"}]
