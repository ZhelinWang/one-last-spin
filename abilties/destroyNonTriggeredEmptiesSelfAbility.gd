extends TokenAbility
class_name DestroyNonTriggeredEmptiesSelfAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out
	var self_off := int(self_c.get("offset", 0))
	out.append({"op": "destroy", "target_offset": self_off})
	out.append({"op": "destroy_non_triggered_empties"})
	return out
