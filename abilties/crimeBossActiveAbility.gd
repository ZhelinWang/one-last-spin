extends TokenAbility
class_name CrimeBossActiveAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var lowest: Dictionary = {}
	var lowest_val := INF
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var tied: Array[Dictionary] = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if tok == null or tok == source_token:
			continue
		var val := _compute_value(c)
		if val < lowest_val:
			lowest_val = val
			tied.clear()
			tied.append(c)
		elif val == lowest_val:
			tied.append(c)
	if tied.is_empty():
		return []
	var target := tied[rng.randi_range(0, tied.size() - 1)]
	return [{"op": "destroy", "target_offset": int(target.get("offset", 0))}]
