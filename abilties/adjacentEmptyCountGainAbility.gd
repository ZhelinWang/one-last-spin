extends TokenAbility
class_name AdjacentEmptyCountGainAbility

@export var amount_per: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var count := 0
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        if tok != null and (tok as Object).has_method("get") and String(tok.get("name")) == "Empty":
            count += 1
    if count <= 0:
        return []
    return [{"op":"permanent_add","target_kind":"self","amount": int(count*amount_per), "destroy_if_zero": false}]

