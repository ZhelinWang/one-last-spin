extends TokenAbility
class_name ReplaceSelfRandomByTagAbility

@export var target_tag: String = "human"
@export var tokens_root: String = "res://tokens"

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    return [{"op":"replace_self_random_by_tag", "target_tag": String(target_tag), "tokens_root": tokens_root}]

