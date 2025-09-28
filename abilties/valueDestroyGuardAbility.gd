extends TokenAbility
class_name ValueDestroyGuardAbility

## Registers a guard that blocks destruction/replace of triggered tokens whose value is below this token's current value.
@export var triggered_only: bool = true

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var val := _contrib_value(self_c)
    return [{
        "op": "register_destroy_guard",
        "offset": int(self_c.get("offset", 0)),
        "min_value_threshold": int(val),
        "triggered_only": bool(triggered_only)
    }]

