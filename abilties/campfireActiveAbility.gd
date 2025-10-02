extends TokenAbility
class_name CampfireActiveAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var campfire_value := _contrib_value(self_c)
	if campfire_value == 0:
		return []
	var out: Array = []
	for c in contribs:
		if c is Dictionary and c.get("token") != source_token:
			var off := int(c.get("offset", 0))
			out.append({
				"kind": "add",
				"amount": campfire_value,
				"factor": 1.0,
				"desc": "+%d Campfire" % campfire_value,
				"source": "ability:%s" % String(id),
				"target_kind": "offset",
				"target_offset": off,
				"_temporary": true
			})
	return out

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	return [{"op": "destroy", "target_offset": int(self_c.get("offset", 0))}]
