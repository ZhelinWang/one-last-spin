extends TokenAbility
class_name RestartRoundAbility

## Active (non-target): Destroy this token and restart the current round.

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var out: Array = []
    # Destroy self (offset=0)
    out.append({"op":"destroy", "target_offset": 0, "__effect_source_token": source_token})
    # Request round restart
    out.append({"op":"restart_round"})
    return out

