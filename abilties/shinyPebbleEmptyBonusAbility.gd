extends TokenAbility
class_name ShinyPebbleEmptyBonusAbility

@export var bonus_increment: float = 0.01

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if bonus_increment == 0.0:
		return []
	return [{"op": "adjust_empty_rarity_bonus", "amount": bonus_increment}]
