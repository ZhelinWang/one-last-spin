extends TokenAbility
class_name DestroyCoinsOnRemovedAbility

func _init():
	trigger = Trigger.ON_REMOVED

func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, source_token: Resource) -> Array:
	if ctx == null:
		return []
	var board_tokens_var: Variant = ctx.get("board_tokens", [])
	if board_tokens_var == null or not (board_tokens_var is Array):
		return []
	var board_tokens: Array = board_tokens_var
	var coins_by_name: Dictionary = {}
	for t in board_tokens:
		if not _token_has_tag(t, "coin"):
			continue
		var nm: String = _token_name(t)
		if nm == "":
			continue
		coins_by_name[nm] = true
	if coins_by_name.is_empty():
		return []
	var cmds: Array = []
	for name in coins_by_name.keys():
		cmds.append({
			"op": "destroy_all_copies_by_name",
			"token_name": String(name),
			"source": "ability:%s" % str(id)
		})
	return cmds
