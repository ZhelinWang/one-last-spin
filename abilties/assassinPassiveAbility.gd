extends TokenAbility
class_name AssassinPassiveAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var adj := _adjacent_contribs(contribs, self_c)
	if adj.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	var pick = adj[rng.randi_range(0, adj.size()-1)]
	var off := int(pick.get("offset", 0))
	var val := _contrib_value(pick)
	var gain := val if val > 0 else 1
	return [
		{"op":"destroy", "target_offset": off},
		{"op":"permanent_add","target_kind":"self","amount": int(gain), "destroy_if_zero": false}
	]
