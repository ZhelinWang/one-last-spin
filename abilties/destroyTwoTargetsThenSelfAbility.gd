extends TokenAbility
class_name DestroyTwoTargetsThenSelfAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	out.append({"op":"destroy", "target_kind":"choose"})
	out.append({"op":"destroy", "target_kind":"choose"})
	var self_c := _find_self_contrib(contribs, source_token)
	var off := 0
	if not self_c.is_empty(): off = int(self_c.get("offset", 0))
	out.append({"op":"destroy", "target_offset": off})
	return out
