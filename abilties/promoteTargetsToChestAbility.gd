extends TokenAbility
class_name PromoteTargetsToChestAbility

@export var chest_path: String = "res://tokens/TreasureHunters/smallChest.tres"
@export var count: int = 2

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	for i in range(max(1, count)):
		out.append({"op":"replace_at_offset","offset": 0, "token_path": String(chest_path), "set_value": -1, "preserve_tags": false, "target_kind":"choose"})
	return out
