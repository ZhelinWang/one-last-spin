extends TokenAbility
class_name DestroyTargetAndGainValueAbility

## Active (target): Destroy the target and gain a portion of its value permanently.
@export var gain_fraction_numer: int = 1
@export var gain_fraction_denom: int = 2
@export var also_replace_with_path: String = ""  ## e.g., res://tokens/coin.tres

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	out.append({
		"op": "destroy_and_gain_fraction",
		"target_kind": "choose",
		"gain_numer": int(gain_fraction_numer),
		"gain_denom": int(max(1, gain_fraction_denom)),
		"replace_path": String(also_replace_with_path).strip_edges()
	})
	return out
