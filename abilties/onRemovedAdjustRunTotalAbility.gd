extends TokenAbility
class_name OnRemovedAdjustRunTotalAbility

## When this token is removed/destroyed, adjust the run total by (multiplier * token value).
@export var multiplier: float = 1.5

func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, source_token: Resource) -> Array:
    var out: Array = []
    if removed_token == null:
        return out
    var v = 0
    if removed_token.has_method("get"):
        var vv = removed_token.get("value")
        if vv != null:
            v = int(vv)
    var amt: int = int(round(max(0.0, float(v)) * max(0.0, float(multiplier))))
    if amt == 0:
        return out
    out.append({
        "op": "adjust_run_total",
        "amount": amt,
        "source": "ability:%s" % String(id)
    })
    return out

