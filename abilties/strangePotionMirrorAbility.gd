extends TokenAbility
class_name StrangePotionMirrorAbility

## When this token's value changes, a random other triggered token gets the same delta.

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
    if target_token != source_token:
        return
    var delta := new_val - prev_val
    if delta == 0:
        return
    var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
    if not (contribs is Array):
        return
    # Build a candidate list excluding self
    var cands: Array[Dictionary] = []
    for c in contribs:
        if c is Dictionary and c.get("token") != source_token:
            cands.append(c)
    if cands.is_empty():
        return
    var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
    if not ctx.has("rng"): rng.randomize()
    var pick: Dictionary = cands[rng.randi_range(0, cands.size()-1)]
    # Apply delta immediately to the picked contrib
    pick["delta"] = int(pick.get("delta", 0)) + int(delta)
    # Optional: log step into picked contrib
    var steps_var = pick.get("steps")
    var steps: Array = (steps_var if steps_var is Array else [])
    steps.append({"source":"ability:%s" % str(id), "kind":"mirror", "desc":"Strange Potion mirror", "delta": delta})
    pick["steps"] = steps
