extends TokenAbility
class_name OnAdjacentDestroyedGainAbility

@export var fraction_numer: int = 1
@export var fraction_denom: int = 2

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
    var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
    if not (contribs is Array):
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var self_off := int(self_c.get("offset", 999))
    # find destroyed token in contribs
    var tgt_off := 999
    var tgt_c := {}
    for c in contribs:
        if c is Dictionary and c.get("token") == destroyed_token:
            tgt_c = c
            tgt_off = int(c.get("offset", 999))
            break
    if tgt_off == 999:
        return []
    if abs(tgt_off - self_off) != 1:
        return []
    var v := _contrib_value(tgt_c)
    var gain := int(floor(float(max(0, v)) * float(max(0, fraction_numer)) / float(max(1, fraction_denom))))
    if gain <= 0:
        return []
    return [{"op":"permanent_add","target_kind":"self","amount": gain, "destroy_if_zero": false}]

