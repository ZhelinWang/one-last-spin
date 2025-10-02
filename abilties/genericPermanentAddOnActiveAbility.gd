extends TokenAbility
class_name GenericPermanentAddOnActiveAbility

@export var amount: int = 1
@export var destroy_if_zero: bool = false

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN: return []
	return [{"op":"permanent_add","target_kind":"self","amount":amount,"destroy_if_zero":destroy_if_zero}]
