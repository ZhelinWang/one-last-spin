extends TokenAbility
class_name AdjacentAnyOfTagsPermanentAddAbility

@export var tags_list: PackedStringArray = PackedStringArray(["coin", "human"])
@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var ok := false
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        for t in tags_list:
            if _token_has_tag(tok, String(t)):
                ok = true
                break
        if ok: break
    if not ok or amount == 0:
        return []
    return [{"op":"permanent_add","target_kind":"self","amount": int(amount), "destroy_if_zero": false}]

