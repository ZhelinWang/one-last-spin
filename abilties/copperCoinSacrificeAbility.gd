extends TokenAbility
class_name CopperCoinSacrificeAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var out: Array = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		if c.get("token") == source_token:
			continue
		var off := int(c.get("offset", 0))
		out.append({
			"kind": "add",
			"amount": 1,
			"factor": 1.0,
			"desc": "+1 Copper Coin",
			"source": "ability:%s" % str(id),
			"target_kind": "offset",
			"target_offset": off,
			"_temporary": true
		})
	return out

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	return [{"op": "destroy", "target_offset": int(self_c.get("offset", 0))}]
