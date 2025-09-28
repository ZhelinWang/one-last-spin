extends TokenAbility
class_name DestroyTargetGainFixedAbility

@export var gain_amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    out.append({"op":"destroy", "target_kind":"choose"})
    if gain_amount != 0:
        out.append({"op":"permanent_add","target_kind":"self","amount": int(gain_amount), "destroy_if_zero": false})
    return out

