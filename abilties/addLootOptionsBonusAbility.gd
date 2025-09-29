extends TokenAbility
class_name AddLootOptionsBonusAbility

## When this ability triggers, destroy a chosen token, add a bonus to next loot options, and immediately trigger a new selection.
@export var amount: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	return [
		{"op": "destroy", "target_kind": "choose"},
		{"op": "add_loot_options_bonus", "amount": int(max(0, amount))},
		{"op": "trigger_loot_selection"}
	]
