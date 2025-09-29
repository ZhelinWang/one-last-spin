extends TokenAbility
class_name PermanentAddAllTriggeredAbility

@export var amount: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty() or int(self_c.get("offset", 99)) != 0:
		return []
	var out: Array = []
	for c in contribs:
		if c is Dictionary:
			out.append({
				"op": "permanent_add",
				"target_kind": "offset",
				"target_offset": int((c as Dictionary).get("offset", 0)),
				"amount": int(amount),
				"destroy_if_zero": false
			})
	return out
