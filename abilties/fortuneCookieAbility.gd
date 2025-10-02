extends TokenAbility
class_name FortuneCookieAbility

@export var chance: float = 0.5
@export var min_amount: int = 1
@export var max_amount: int = 10

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	if winner_only:
		var self_c := _find_self_contrib(contribs, source_token)
		if self_c.is_empty() or int(self_c.get("offset", 99)) != 0:
			return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	if rng.randf() > max(0.0, min(1.0, chance)):
		return []
	var options: Array = []
	for c in contribs:
		if c is Dictionary:
			options.append(c)
	if options.is_empty():
		return []
	var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	var target_offset := int(pick.get("offset", 0))
	var lo := min(min_amount, max_amount)
	var hi := max(min_amount, max_amount)
	var amount := rng.randi_range(lo, hi)
	if amount == 0:
		return []
	return [{
		"op": "permanent_add",
		"target_kind": "offset",
		"target_offset": target_offset,
		"amount": int(amount),
		"destroy_if_zero": false,
		"source": "ability:%s" % String(id)
	}]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	return []
