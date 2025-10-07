extends TokenAbility
class_name RandomTriggeredAddAbility

@export var amount: int = 1
@export var include_self: bool = false

func _init():
	desc_template = "+%d Lucky"
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	var candidates: Array[Dictionary] = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if tok == null:
			continue
		if not include_self and tok == source_token:
			continue
		candidates.append(c)
	if candidates.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var pick: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var off: int = int(pick.get("offset", 0))
	var desc: String = desc_template
	if desc.find("%d") != -1:
		desc = desc % amount
	return [{
		"kind": "add",
		"amount": int(amount),
		"factor": 1.0,
		"desc": desc,
		"source": "ability:%s" % str(id),
		"target_kind": "offset",
		"target_offset": off,
		"_temporary": true
	}]
