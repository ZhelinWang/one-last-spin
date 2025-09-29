extends TokenAbility
class_name DestroyRandomTriggeredByRarityAndGainAbility

@export var rarity: String = "common"
@export var gain_to_self: bool = true

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	return [{"op":"destroy_random_triggered_by_rarity_and_gain", "rarity": String(rarity).to_lower()}]
