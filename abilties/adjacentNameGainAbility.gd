extends TokenAbility
class_name AdjacentNameGainAbility

@export var name_to_check: String = "Empty"
@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        if tok != null and (tok as Object).has_method("get") and String(tok.get("name")) == name_to_check:
            return [{"op":"permanent_add","target_kind":"self","amount": int(amount), "destroy_if_zero": false}]
    return []

