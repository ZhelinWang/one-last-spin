extends TokenAbility
class_name TreasureRatAbility

@export var chest_path: String = "res://tokens/TreasureHunters/smallChest.tres"
@export var spawn_chance: float = 0.25

func _init():
	trigger = Trigger.ACTIVE_DURING_SPIN
	winner_only = false

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out

	var empty_offsets: Array[int] = []
	for nc in _adjacent_contribs(contribs, self_c):
		var tok = nc.get("token")
		if tok != null and (tok as Object).has_method("get") and String(tok.get("name")).strip_edges().to_lower() == "empty":
			empty_offsets.append(int(nc.get("offset", 0)))
	if empty_offsets.is_empty():
		return out

	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	if rng.randf() > clamp(spawn_chance, 0.0, 1.0):
		return out

	var chest_path_s := String(chest_path).strip_edges()
	if chest_path_s == "":
		return out

	var off_choice: int = empty_offsets[rng.randi_range(0, empty_offsets.size() - 1)]
	out.append({
		"op": "replace_at_offset",
		"offset": off_choice,
		"token_path": chest_path_s,
		"set_value": -1,
		"preserve_tags": false
	})
	return out
