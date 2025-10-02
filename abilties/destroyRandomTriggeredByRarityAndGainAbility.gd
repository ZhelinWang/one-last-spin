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
	var rar_norm := String(rarity).strip_edges().to_lower()
	return [{
		"op": "destroy_random_triggered_by_rarity_and_gain",
		"rarity": rar_norm,
		"match_any_rarity": rar_norm == "" or rar_norm == "any" or rar_norm == "all",
		"gain_to_self": gain_to_self
	}]
