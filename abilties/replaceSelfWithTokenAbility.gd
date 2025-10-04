extends TokenAbility
class_name ReplaceSelfWithTokenAbility

@export var replacement_path: String = ""
@export var preserve_tags: bool = false
@export var set_value: int = -1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var path := String(replacement_path).strip_edges()
	if path == "":
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty() or int(self_c.get("offset", 99)) != 0:
		return []
	return [{
		"op": "replace_at_offset",
		"offset": int(self_c.get("offset", 0)),
		"token_path": path,
		"set_value": set_value,
		"preserve_tags": preserve_tags
	}]
