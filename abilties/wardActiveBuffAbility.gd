extends TokenAbility
class_name WardActiveBuffAbility

@export var amount: int = 1

func _init():
	desc_template = "+%d Ward"
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if amount == 0:
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var out: Array = []
	var desc: String = desc_template
	if desc.find("%d") != -1:
		desc = desc % amount
	for c in _adjacent_contribs(contribs, self_c):
		out.append({
			"kind": "add",
			"amount": int(amount),
			"factor": 1.0,
			"desc": desc,
			"source": "ability:%s" % String(id),
			"target_kind": "offset",
			"target_offset": int(c.get("offset", 0)),
			"_temporary": true
		})
	return out
