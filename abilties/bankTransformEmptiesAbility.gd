extends TokenAbility
class_name BankTransformEmptiesAbility

@export var fallback_path: String = "res://tokens/Hoarder/coin.tres"
@export var coin_paths: PackedStringArray = PackedStringArray([
	"res://tokens/Hoarder/coin.tres",
	"res://tokens/Hoarder/copperCoin.tres",
	"res://tokens/TreasureHunters/rustedCoin.tres"
])

func _init():
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var out: Array = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if not _token_is_empty(tok):
			continue
		var pick_path := _pick_coin_path(rng)
		if pick_path == "":
			continue
		out.append({
			"op": "replace_at_offset",
			"target_offset": int(c.get("offset", 0)),
			"token_path": pick_path,
			"set_value": -1,
			"preserve_tags": false
		})
	return out

func _pick_coin_path(rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for p in coin_paths:
		var ps := String(p).strip_edges()
		if ps != "":
			pool.append(ps)
	if pool.is_empty():
		var fallback := String(fallback_path).strip_edges()
		if fallback != "":
			pool.append(fallback)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]

func _token_is_empty(tok: Variant) -> bool:
	if tok == null:
		return false
	if tok is Resource:
		var rp := String((tok as Resource).resource_path).strip_edges()
		if rp != "" and rp == "res://tokens/empty.tres":
			return true
	if tok is Object and (tok as Object).has_method("get"):
		var is_empty = tok.get("isEmpty")
		if is_empty != null and bool(is_empty):
			return true
		var nm = tok.get("name")
		if typeof(nm) == TYPE_STRING:
			var s := String(nm).strip_edges().to_lower()
			if s == "empty" or s == "empty token":
				return true
	return false
