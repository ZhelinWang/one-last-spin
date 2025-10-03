extends TokenAbility
class_name StrangePotionGainAbility

@export var min_amount: int = 1
@export var max_amount: int = 2

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var lo: int = min(min_amount, max_amount)
	var hi: int = max(min_amount, max_amount)
	var amt: int = rng.randi_range(lo, hi)
	if amt == 0:
		return []
	return [{"op": "permanent_add", "target_kind": "self", "amount": amt, "destroy_if_zero": false}]
