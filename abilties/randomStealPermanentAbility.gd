extends TokenAbility
class_name RandomStealPermanentAbility

@export var amount: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if amount <= 0:
		return []
	var targets: Array[Dictionary] = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if tok == null or tok == source_token:
			continue
		if String(tok.get("name")) == "Empty":
			continue
		targets.append(c)
	if targets.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var pick: Dictionary = targets[rng.randi_range(0, targets.size() - 1)]
	var off := int(pick.get("offset", 0))
	var commands: Array = []
	var amt := int(amount)
	commands.append({"op": "permanent_add", "target_kind": "self", "amount": amt, "destroy_if_zero": false})
	commands.append({"op": "permanent_add", "target_kind": "offset", "target_offset": off, "amount": -amt, "destroy_if_zero": true})
	return commands
