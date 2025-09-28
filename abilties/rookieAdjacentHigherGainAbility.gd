extends TokenAbility
class_name RookieAdjacentHigherGainAbility

@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var self_val := _contrib_value(self_c)
    for nc in _adjacent_contribs(contribs, self_c):
        if _contrib_value(nc) > self_val:
            return [{"op":"permanent_add","target_kind":"self","amount": int(amount), "destroy_if_zero": false}]
    return []

