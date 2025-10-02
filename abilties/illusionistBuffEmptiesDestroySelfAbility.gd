extends TokenAbility
class_name IllusionistBuffEmptiesDestroySelfAbility

@export var buff_amount_per: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var board: Array = []
	if ctx.has("board_tokens") and ctx["board_tokens"] is Array:
		board = ctx["board_tokens"]
	var illusion_count: int = 0
	for t in board:
		if t != null and (t as Object).has_method("get") and String(t.get("name")) == "Illusionist":
			illusion_count += 1
	if illusion_count > 0 and buff_amount_per != 0:
		out.append({
			"op": "permanent_add",
			"target_kind": "name",
			"target_name": "Empty",
			"amount": int(illusion_count * buff_amount_per),
			"destroy_if_zero": false
		})
	out.append({
		"op": "destroy_all_copies_by_name",
		"token_name": "Illusionist"
	})
	return out
