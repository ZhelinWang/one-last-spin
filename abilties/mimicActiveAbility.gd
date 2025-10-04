extends TokenAbility
class_name MimicActiveAbility

@export var require_different_name: bool = true

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _collect_inventory_tokens(ctx: Dictionary, source_token: Resource) -> Array:
	var board = ctx.get("board_tokens") if ctx.has("board_tokens") else []
	if not (board is Array):
		return []
	var out: Array = []
	for t in board:
		if t == null or not (t as Object).has_method("get"):
			continue
		if t == source_token:
			continue
		if require_different_name and String(t.get("name")) == String(source_token.get("name")):
			continue
		out.append(t)
	return out

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var candidates := _collect_inventory_tokens(ctx, source_token)
	if candidates.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var pick = candidates[rng.randi_range(0, candidates.size() - 1)]
	var path := ""
	var token_ref = null
	if pick is Resource:
		token_ref = pick
		path = String((pick as Resource).resource_path)
	if path.strip_edges() == "" and token_ref == null:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var cmd := {
		"op": "replace_at_offset",
		"offset": int(self_c.get("offset", 0)),
		"token_path": path,
		"set_value": -1,
		"preserve_tags": false
	}
	if token_ref != null:
		cmd["token_ref"] = token_ref
	return [cmd]
