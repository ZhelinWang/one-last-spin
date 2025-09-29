extends TokenAbility
class_name StealPermanentAbility

@export var amount: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	# Defer to executor to choose target; execute two perms: self +amount, target -amount
	out.append({"op":"permanent_add","target_kind":"self","amount": int(max(0, amount)),"destroy_if_zero": false})
	out.append({"op":"permanent_add","target_kind":"choose","amount": -int(max(0, amount)),"destroy_if_zero": true})
	return out
