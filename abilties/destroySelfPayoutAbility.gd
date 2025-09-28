extends TokenAbility
class_name DestroySelfPayoutAbility

@export var numer: int = 3
@export var denom: int = 2

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return []
    var v := _contrib_value(self_c)
    var payout := int(floor(float(max(0, v)) * float(max(0, numer)) / float(max(1, denom))))
    var out: Array = []
    if payout > 0:
        out.append({"op":"adjust_run_total", "amount": payout})
    out.append({"op":"destroy", "target_offset": int(self_c.get("offset", 0))})
    return out

