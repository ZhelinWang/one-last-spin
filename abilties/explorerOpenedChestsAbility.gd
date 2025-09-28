extends TokenAbility
class_name ExplorerOpenedChestsAbility

## Grants +1 permanently for each Chest opened this game; applies only the delta each spin.

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var total := int(ctx.get("chests_opened_total", 0))
    if total <= 0:
        return []
    var applied := 0
    if source_token != null and (source_token as Object).has_method("has_meta") and source_token.has_meta("explorer_applied"):
        var v = source_token.get_meta("explorer_applied")
        if v != null:
            applied = int(v)
    var delta := total - applied
    if delta <= 0:
        return []
    if (source_token as Object).has_method("set_meta"):
        source_token.set_meta("explorer_applied", total)
    return [{"op":"permanent_add","target_kind":"self","amount": int(delta), "destroy_if_zero": false}]

