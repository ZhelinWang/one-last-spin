extends TokenAbility
class_name RandomSelfPermanentAddAbility

@export var min_amount: int = -1
@export var max_amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	var lo = min(min_amount, max_amount)
	var hi = max(min_amount, max_amount)
	var amt := rng.randi_range(lo, hi)
	if amt == 0:
		return []
	return [{"op":"permanent_add","target_kind":"self","amount": int(amt), "destroy_if_zero": false}]
