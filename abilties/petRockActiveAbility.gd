extends TokenAbility
class_name PetRockActiveAbility

func _init():
	desc_template = "Pet Rock"
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var rock_val: int = _contrib_value(self_c)
	var out: Array = []
	var desc: String = desc_template
	for c in contribs:
		if not (c is Dictionary):
			continue
		var current_val: int = _contrib_value(c)
		var delta: int = rock_val - current_val
		if delta == 0:
			continue
		out.append({
			"kind": "add",
			"amount": delta,
			"factor": 1.0,
			"desc": desc,
			"source": "ability:%s" % String(id),
			"target_kind": "offset",
			"target_offset": int(c.get("offset", 0)),
			"_temporary": true
		})
	return out
