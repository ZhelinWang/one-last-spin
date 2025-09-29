extends TokenAbility
class_name SpawnTokensByPathAbility

@export var token_path: String = "res://tokens/empty.tres"
@export var count: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var p := String(token_path).strip_edges()
	if p == "":
		return []
	return [{"op":"spawn_token_in_inventory","token_path": p, "count": int(max(1, count))}]
