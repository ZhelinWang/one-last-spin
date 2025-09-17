extends TokenAbility
class_name ExecutiveReplaceLowestAbility

@export var coin_token_path: String = "res://tokens/coin.tres"

func _init():
	trigger = Trigger.ACTIVE_DURING_SPIN
	winner_only = true
	target_kind = TargetKind.ANY

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	if coin_token_path.strip_edges() == "":
		return []

	var lowest_contrib: Dictionary = {}
	var lowest_val: int = 2147483647
	for entry in contribs:
		if not (entry is Dictionary):
			continue
		if int(entry.get("offset", 0)) == 0:
			continue
		var val: int = _contrib_value(entry)
		if lowest_contrib.is_empty() or val < lowest_val:
			lowest_contrib = entry
			lowest_val = val

	if lowest_contrib.is_empty():
		return []

	var offset := int(lowest_contrib.get("offset", 0))
	var cmds: Array = []
	cmds.append({
		"op": "replace_at_offset",
		"offset": offset,
		"token_path": coin_token_path,
		"set_value": max(lowest_val, 0),
		"preserve_tags": false
	})
	return cmds
