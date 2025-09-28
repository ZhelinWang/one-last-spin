extends TokenAbility
class_name AdjacentWardAbility

## Registers this token as a Ward: when an adjacent token would be destroyed this spin, destroy this token instead.

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    return [{"op":"register_ward", "offset": int(self_c.get("offset", 0))}]

