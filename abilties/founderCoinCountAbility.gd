extends TokenAbility
class_name FounderCoinCountAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

# Founder active: gain +1 permanently for each Coin in inventory.
func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var coin_count: int = _count_in_inventory(ctx, "coin")
	if coin_count <= 0:
		return []
	return [{
		"op": "permanent_add",
		"target_kind": "self",
		"amount": int(coin_count),
		"destroy_if_zero": false
	}]
