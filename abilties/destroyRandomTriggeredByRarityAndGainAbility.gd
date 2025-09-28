extends TokenAbility
class_name DestroyRandomTriggeredByRarityAndGainAbility

@export var rarity: String = "common"
@export var gain_to_self: bool = true

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    return [{"op":"destroy_random_triggered_by_rarity_and_gain", "rarity": String(rarity).to_lower()}]

