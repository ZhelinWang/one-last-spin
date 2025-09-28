extends TokenAbility
class_name DestroyTriggeredTagAbility

@export var target_tag: String = "chest"

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    return [{"op":"destroy_triggered_tag", "target_tag": String(target_tag)}]

