extends TokenAbility
class_name RerollTargetSameRarityAbility

## Active (target): Replace the target with a random token of the same rarity.
@export var tokens_root: String = "res://tokens"
@export var exclude_names: PackedStringArray = ["Empty"]

func _list_token_paths() -> Array[String]:
	var out: Array[String] = []
	var da = DirAccess.open(tokens_root)
	if da == null:
		return out
	var files = da.get_files()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		out.append(tokens_root.path_join(f))
	return out

func _pick_same_rarity_path(target_token) -> String:
	if target_token == null or not target_token.has_method("get"):
		return ""
	var r = String(target_token.get("rarity")).to_lower()
	var name = String(target_token.get("name"))
	var candidates: Array[String] = []
	for p in _list_token_paths():
		var res = ResourceLoader.load(p)
		if res == null or not (res as Object).has_method("get"):
			continue
		if String(res.get("name")) == name:
			continue
		if exclude_names.has(String(res.get("name"))):
			continue
		if String(res.get("rarity")).to_lower() == r:
			candidates.append(p)
	if candidates.is_empty():
		return ""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if ctx_has_rng():
		rng = _ctx_rng()
	else:
		rng.randomize()
	return candidates[rng.randi_range(0, candidates.size()-1)]

func ctx_has_rng() -> bool:
	return false

func _ctx_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	# Defer target selection to executor with interactive choose
	out.append({
		"op": "reroll_same_rarity",
		"target_kind": "choose",
		"tokens_root": tokens_root,
		"exclude_names": exclude_names,
	})
	return out
