extends TokenAbility
class_name IllusionistBuffEmptiesDestroySelfAbility

@export var buff_amount: int = 2

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    if buff_amount != 0:
        out.append({"op":"permanent_add","target_kind":"name","target_name":"Empty","amount": int(buff_amount), "destroy_if_zero": false})
    var self_c := _find_self_contrib(contribs, source_token)
    var off := 0
    if not self_c.is_empty(): off = int(self_c.get("offset", 0))
    out.append({"op":"destroy", "target_offset": off})
    return out

