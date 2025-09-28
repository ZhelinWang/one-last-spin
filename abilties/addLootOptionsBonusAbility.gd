extends TokenAbility
class_name AddLootOptionsBonusAbility

## When this ability triggers, add a bonus to the next loot options count at end of round.
@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    return [{"op":"add_loot_options_bonus", "amount": int(max(0, amount))}]

