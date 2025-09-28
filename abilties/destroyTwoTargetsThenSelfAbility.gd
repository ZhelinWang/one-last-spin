extends TokenAbility
class_name DestroyTwoTargetsThenSelfAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    out.append({"op":"destroy", "target_kind":"choose"})
    out.append({"op":"destroy", "target_kind":"choose"})
    var self_c := _find_self_contrib(contribs, source_token)
    var off := 0
    if not self_c.is_empty(): off = int(self_c.get("offset", 0))
    out.append({"op":"destroy", "target_offset": off})
    return out

