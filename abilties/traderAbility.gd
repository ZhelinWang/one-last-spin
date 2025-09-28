extends TokenAbility
class_name TraderAbility

@export var min_gain: int = 1
@export var max_gain: int = 3

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
    if not ctx.has("rng"): rng.randomize()
    var amt := rng.randi_range(min_gain, max(min_gain, max_gain))
    var out: Array = []
    out.append({"op":"permanent_add","target_kind":"self","amount": int(amt),"destroy_if_zero": false})
    # Apply same change to adjacent coins only
    var self_c := _find_self_contrib(contribs, source_token)
    if not self_c.is_empty():
        for nc in _adjacent_contribs(contribs, self_c):
            var tok = nc.get("token")
            if _token_has_tag(tok, "coin"):
                var off := int(nc.get("offset", 0))
                out.append({"op":"permanent_add","target_kind":"offset","target_offset": off, "amount": int(amt),"destroy_if_zero": false})
    return out

