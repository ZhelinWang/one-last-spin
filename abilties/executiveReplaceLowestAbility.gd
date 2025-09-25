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
	var coin_base := _resolve_coin_base_value(ctx)
	var cmds: Array = []
	cmds.append({
		"op": "replace_at_offset",
		"offset": offset,
		"token_path": coin_token_path,
		"set_value": coin_base,
		"preserve_tags": false
	})
	return cmds

func _resolve_coin_base_value(ctx: Dictionary) -> int:
	var base_val: int = 1
	var res = ResourceLoader.load(coin_token_path)
	if res is Resource:
		var raw = res.get("value")
		if raw != null:
			base_val = max(int(raw), 1)

	if ctx.has("board_tokens") and (ctx["board_tokens"] is Array):
		for token in ctx["board_tokens"]:
			if token == null:
				continue
			if not _is_coin(token):
				continue
			if (token as Object).has_method("has_meta") and token.has_meta("base_value"):
				var meta_val = token.get_meta("base_value")
				if meta_val != null:
					return max(int(meta_val), 1)
			if (token as Object).has_method("get"):
				var value_prop = token.get("value")
				if value_prop != null:
					return max(int(value_prop), 1)

	return base_val
