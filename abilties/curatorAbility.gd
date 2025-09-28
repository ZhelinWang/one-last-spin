extends TokenAbility
class_name CuratorAbility

@export var self_amount: int = 1
@export var chest_amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    # Active (target): +1 perm to chosen
    out.append({"op":"permanent_add","target_kind":"choose","amount": int(self_amount), "destroy_if_zero": false})
    # Passive: All Chests +1 permanently
    out.append({"op":"permanent_add","target_kind":"tag","target_tag":"chest","amount": int(chest_amount), "destroy_if_zero": false})
    return out

