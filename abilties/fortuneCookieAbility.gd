extends TokenAbility
class_name FortuneCookieAbility

@export var chance: float = 0.5
@export var min_amount: int = 1
@export var max_amount: int = 10

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	if rng.randf() > max(0.0, min(1.0, chance)):
		return []
	if contribs.is_empty():
		return []
	var k := rng.randi_range(0, contribs.size()-1)
	var c = contribs[k]
	if not (c is Dictionary):
		return []
	var off := int((c as Dictionary).get("offset", 0))
	var amt := rng.randi_range(min(min_amount, max_amount), max(min_amount, max_amount))
	return [{"kind":"add", "amount": int(amt), "factor": 1.0, "desc": "+%d Fortune" % amt, "source":"ability:%s" % String(id), "target_kind":"offset", "target_offset": off}]
