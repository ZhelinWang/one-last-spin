extends TokenAbility
class_name GenericOnRemovedLoseMultipleAbility

# Lose N x this token's value from the bank when this token is removed.
@export var multiple: int = 5

func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, source_token: Resource) -> Array:
	var out: Array = []
	if removed_token == null:
		return out
	var val_v = removed_token.get("value") if removed_token.has_method("get") else 0
	var val_i: int = int(val_v) if val_v != null else 0
	if val_i <= 0 or multiple == 0:
		return out
	var mult_abs: int = int(abs(multiple))
	var amt: int = -mult_abs * val_i
	out.append({
		"op": "adjust_run_total",
		"amount": amt,
		"source": "ability:%s" % (id if id != "" else _token_name(source_token)),
		"desc": "Removal penalty"
	})
	return out
