extends TokenAbility
class_name DestroySelfPayoutAbility

@export var numer: int = 3
@export var denom: int = 2

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	return [{"op":"destroy", "target_offset": int(self_c.get("offset", 0))}]

func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, _source_token: Resource) -> Array:
	if removed_token == null:
		return []
	var val := 0
	if (removed_token as Object).has_method("get"):
		var raw = removed_token.get("value")
		if raw != null:
			val = max(0, int(raw))
	var payout := int(floor(float(val) * float(max(0, numer)) / float(max(1, denom))))
	if payout <= 0:
		return []
	return [{"op":"adjust_run_total", "amount": payout}]
