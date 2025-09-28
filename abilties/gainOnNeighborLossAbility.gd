extends TokenAbility
class_name GainOnNeighborLossAbility

## When an adjacent token loses value during spin, this token gains that amount permanently.

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
	if target_contrib == null or not (target_contrib is Dictionary):
		return
	# Only react to decreases on adjacent neighbors
	var delta := new_val - prev_val
	if delta >= 0:
		return
	# Determine adjacency relative to owner by comparing offsets
	var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
	if not (contribs is Array):
		return
	# Find self contrib and target contrib offsets
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return
	var tgt_off: int = int(target_contrib.get("offset", 999))
	var self_off: int = int(self_c.get("offset", 999))
	if abs(tgt_off - self_off) != 1:
		return
	var gain_amt = abs(delta)
	if gain_amt <= 0:
		return
	var cmd := {"op":"permanent_add", "target_kind":"self", "amount": int(gain_amt), "destroy_if_zero": false}
	var pend = ctx.get("__pending_commands", [])
	if not (pend is Array):
		pend = []
	(pend as Array).append(cmd)
	ctx["__pending_commands"] = pend
