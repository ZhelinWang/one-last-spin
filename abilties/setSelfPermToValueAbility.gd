extends TokenAbility
class_name SetSelfPermToValueAbility

@export var target_value: int = 5

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var curr := _contrib_value(self_c)
	var delta := int(target_value) - int(curr)
	if delta == 0:
		return []
	return [{"op":"permanent_add","target_kind":"self","amount": delta, "destroy_if_zero": false}]
