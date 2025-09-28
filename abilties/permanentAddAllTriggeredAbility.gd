extends TokenAbility
class_name PermanentAddAllTriggeredAbility

@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    for c in contribs:
        if c is Dictionary:
            out.append({"op":"permanent_add","target_kind":"offset","target_offset": int((c as Dictionary).get("offset", 0)), "amount": int(amount), "destroy_if_zero": false})
    return out

