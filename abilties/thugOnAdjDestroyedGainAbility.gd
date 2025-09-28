extends TokenAbility
class_name ThugOnAdjDestroyedGainAbility

@export var amount: int = 1

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
    var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
    if not (contribs is Array):
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var self_off := int(self_c.get("offset", 999))
    for c in contribs:
        if c is Dictionary and c.get("token") == destroyed_token:
            var off := int(c.get("offset", 999))
            if abs(off - self_off) == 1:
                return [{"op":"permanent_add","target_kind":"self","amount": int(amount), "destroy_if_zero": false}]
    return []

