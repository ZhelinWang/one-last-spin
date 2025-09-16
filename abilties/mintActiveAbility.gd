extends TokenAbility
class_name MintActiveAbility

@export var coin_token_path: String = "res://tokens/coin.tres"

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Winner-only recommended (executor runs commands for winner)
	var out: Array = []
	if coin_token_path.strip_edges() != "":
		# Inventory-level replacement (future spins)
		out.append({"op":"replace_all_empties","token_path": coin_token_path})
		# Board-level visual replacement (current spinner viewport)
		out.append({"op":"replace_board_empties","token_path": coin_token_path})
	# Decrease value of all coins by 1 across inventory
	out.append({"op":"permanent_add","target_kind":"tag","target_tag":"coin","amount": -1, "destroy_if_zero": false})
	return out
