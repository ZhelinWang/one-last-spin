extends TokenAbility
class_name PirateMirrorChestValueAbility

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
	if destroyed_token == null or not (destroyed_token as Object).has_method("get"):
		return []
	if not _token_has_tag(destroyed_token, "chest"):
		return []
	var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
	if not (contribs is Array):
		return []
	var target_c := {}
	for c in contribs:
		if c is Dictionary and c.get("token") == destroyed_token:
			target_c = c
			break
	if target_c.is_empty():
		return []
	var val := _contrib_value(target_c)
	if val <= 0:
		return []
	return [{"op": "permanent_add", "target_kind": "self", "amount": int(val), "destroy_if_zero": false}]
