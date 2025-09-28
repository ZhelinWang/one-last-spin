extends TokenAbility
class_name PermanentAddSelfValueToTriggeredAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var out: Array = []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return out
    var val := _contrib_value(self_c)
    for c in contribs:
        if c is Dictionary:
            var off := int(c.get("offset", 0))
            out.append({"op":"permanent_add","target_kind":"offset","target_offset": off, "amount": int(val), "destroy_if_zero": false})
    return out

