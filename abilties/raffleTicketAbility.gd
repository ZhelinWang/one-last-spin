extends TokenAbility
class_name RaffleTicketAbility

@export var chance: float = 0.25

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	if rng.randf() > max(0.0, min(1.0, chance)):
		return []
	# Double target permanent value: executor computes delta from current value
	return [{"op":"double_target_permanent", "target_kind":"choose"}]
