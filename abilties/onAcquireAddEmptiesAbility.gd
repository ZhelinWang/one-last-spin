extends TokenAbility
class_name OnAcquireAddEmptiesAbility

## When the token is added to inventory (loot), add N Empty tokens to inventory.
@export var count: int = 3

func on_added_to_inventory(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void:
	if count <= 0:
		return
	# Expect spin_root helper in ctx (spinRoot.gd). Fall back to appending directly.
	var sr = ctx.get("spin_root") if ctx.has("spin_root") else null
	if sr != null and (sr as Object).has_method("add_empty_slots"):
		sr.call("add_empty_slots", int(count))
		return
	# Fallback: try to resolve empty token path from CoinManager and append directly to board_tokens
	var cm = ctx.get("coin_mgr") if ctx.has("coin_mgr") else null
	if cm == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			var tree: SceneTree = loop as SceneTree
			var root := tree.get_root()
			if root != null and root.has_node("coinManager"):
				cm = root.get_node_or_null("coinManager")
	var empty_path: String = "res://tokens/empty.tres"
	if cm != null and (cm as Object).has_method("get"):
		var ep = cm.get("empty_token_path")
		if typeof(ep) == TYPE_STRING:
			empty_path = String(ep)
	var empty_res = ResourceLoader.load(empty_path)
	if empty_res == null:
		return
	for i in range(max(0, int(count))):
		var inst: Resource = (empty_res as Resource).duplicate(true)
		if board_tokens is Array:
			(board_tokens as Array).append(inst)
