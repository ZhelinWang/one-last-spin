extends TokenAbility
class_name TreasureRatActiveAbility

@export var worn_map_path: String = "res://tokens/TreasureHunters/wornMap.tres"

func _init():
	trigger = Trigger.ACTIVE_DURING_SPIN
	winner_only = true

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var map_path := String(worn_map_path).strip_edges()
	if map_path == "":
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty() or int(self_c.get("offset", 99)) != 0:
		return []
	return [{
		"op": "replace_at_offset",
		"token_path": map_path,
		"set_value": -1,
		"preserve_tags": false,
		"target_kind": "choose",
		"choose": true
	}]
