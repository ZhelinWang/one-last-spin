extends TokenAbility
class_name PermanentSetTargetToSelfValueAbility

## Active (target): Set the target's permanent value to this token's current spin value.
## Emits a high-level command handled by executor to support interactive target selection.

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var out: Array = []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return out
    out.append({
        "op": "set_perm_to_self_current",
        "target_kind": "choose",
        "__effect_source_token": source_token,
    })
    return out
