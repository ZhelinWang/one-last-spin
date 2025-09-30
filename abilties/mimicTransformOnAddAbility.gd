extends TokenAbility
class_name MimicTransformOnAddAbility

## On add: Create a copy of a random token currently in inventory.
@export var exclude_self: bool = true
@export var require_different_name: bool = true

func on_added_to_inventory(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void:
	if board_tokens == null or not (board_tokens is Array):
		return
	var candidates: Array = []
	for t in board_tokens:
		if t == null or not (t as Object).has_method("get"):
			continue
		if exclude_self and t == source_token:
			continue
		if require_different_name:
			var n1 := String(source_token.get("name")) if source_token.has_method("get") else ""
			var n2 := String(t.get("name"))
			if n1 == n2:
				continue
		candidates.append(t)
	if candidates.is_empty():
		return
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var pick = candidates[rng.randi_range(0, candidates.size() - 1)]
	if pick == null:
		return
	var sr = ctx.get("spin_root") if ctx.has("spin_root") else null
	if sr == null or not is_instance_valid(sr):
		return
	var base_copy: Resource = (pick as Resource).duplicate(true)
	if base_copy == null:
		return
	var added_variant = sr.call("_insert_token_replacing_empties", base_copy, 1)
	var added_tokens: Array = []
	if typeof(added_variant) == TYPE_ARRAY:
		added_tokens = added_variant
	else:
		added_tokens = [base_copy]
	if (sr as Object).has_method("_apply_on_added_abilities"):
		sr.call_deferred("_apply_on_added_abilities", added_tokens)
	if (sr as Object).has_method("_update_inventory_strip"):
		sr.call_deferred("_update_inventory_strip")
	if (sr as Object).has_method("_refresh_inventory_baseline"):
		sr.call_deferred("_refresh_inventory_baseline")
